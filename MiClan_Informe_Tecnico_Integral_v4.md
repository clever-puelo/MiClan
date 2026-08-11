# MiClan — Informe Técnico Integral (v4)

**Propósito de este documento:** ser la memoria completa y autosuficiente del proyecto — para retomar el desarrollo en una conversación nueva, o para que **cualquier IA (u otro desarrollador) pueda reconstruir la app desde cero** con el mismo criterio de diseño, sin acceso al código original. Cubre: idea y objetivo del producto, stack, arquitectura, esquema de datos completo, reglas de seguridad, cada pantalla, cada servicio, el flujo de GPS (primer y segundo plano) tal como quedó tras la sesión del 2026-08-10, notificaciones, administración/roles de miembros, y el historial completo de bugs encontrados y resueltos (para no repetirlos).

**Relación con el informe anterior:** este documento **reemplaza a `MiClan_Informe_Tecnico_Integral_v3.md`**. Se mantiene el v3 en el repo por historial, pero está desactualizado en un punto central: describía una arquitectura de GPS que solo funcionaba en primer plano (`flutter_background_service` "declarado pero no usado"). Esa arquitectura cambió por completo en la sesión del 2026-08-10: ahora hay un servicio nativo de Android real corriendo en su propio isolate para el tracking en segundo plano. Este informe documenta el estado **actual y verificado en dispositivo real**.

---

## 1. Resumen del producto — idea y objetivo

MiClan es una app Flutter para Android de **protección familiar por grupos** ("caja negra" + comunicación de emergencia). Un grupo de personas (una familia, por ejemplo) comparte su ubicación en tiempo real en un mapa común, puede mandarse alertas de pánico (S.O.S.), mensajes rápidos preconfigurados y chat grupal con fotos/audios, y el administrador del grupo puede revisar el historial de movimientos ("recorrido") de cada miembro.

**Problema que resuelve:** que una familia (o cualquier grupo cerrado de confianza) sepa en todo momento dónde está cada integrante, sin depender de apps de mensajería genéricas, con un botón de pánico de acceso inmediato y sin fricción para comunicarse ("llegué", "todo bien", "¿dónde estás?") sin tener que escribir.

Conceptos centrales del dominio (**no negociables al rediseñar** — son la base de todo el modelo de datos y las reglas de seguridad):
- Cada usuario pertenece **a un solo grupo a la vez** (`AppUser.groupId`).
- Cada grupo tiene un **código de unión de 6 caracteres**, generado al crear el grupo.
- Quien crea el grupo es automáticamente su **administrador**. **No existe un campo de "rol" separado en la base de datos**: la app compara `group.ownerId == currentUser.uid` en cada lugar donde hace falta saber si alguien es admin (cliente y reglas de seguridad de Firestore por igual).
- Cualquier otro usuario que quiera sumarse a un grupo existente debe **solicitar unión con el código** y esperar **aprobación manual** del administrador — no hay auto-unión.

---

## 2. Categorías / roles de miembros (respuesta explícita)

**Hoy la app tiene exactamente dos "categorías" de miembro, y solo dos, sin ningún campo de configuración adicional:**

1. **Administrador**: el único, `group.ownerId`. Se determina 100% por comparación (`uid == group.ownerId`), nunca se guarda como un campo `role` en el documento del usuario. Privilegios exclusivos:
   - Aprobar/rechazar solicitudes de unión.
   - Expulsar miembros.
   - Configurar los 9 botones de mensajes rápidos del grupo (`groups/{id}/config/quickMessages`).
   - Crear/editar/borrar la zona segura (geofence) del grupo.
   - Ver la "Caja Negra del Grupo" (historial de ubicaciones de **cualquier** miembro, no solo el propio) desde Configuración.
   - Al salir del grupo, el grupo entero se borra (ver sección 12, punto 5).
2. **Miembro**: cualquier otro usuario con `groupId` igual al de ese grupo. En la UI se muestra literalmente como el texto **"Miembro"** (ver `home_screen.dart`, hoja de miembros: `m.uid == group?.ownerId ? 'Administrador' : 'Miembro'`).

**No existen** (ni en el modelo de datos ni en la UI) categorías como "niño/adulto", "puede ver a todos / solo a algunos", permisos granulares, ni sub-roles. Si se quiere reconstruir la app y se desea agregar esto, es una extensión de `AppUser` (agregar un campo `category`/`role` con enum) + ajustar las reglas de Firestore y los filtros del mapa/chips — hoy no existe ese código.

---

## 3. Stack tecnológico

- **Flutter** (Dart SDK `>=3.5.0 <4.0.0`), target **Android** (las carpetas `ios/`, `macos/`, `linux/`, `windows/`, `web/` existen por defecto del template de Flutter pero **no se ajustaron ni probaron** — permisos de `Info.plist`, etc. no están hechos).
- **Gestión de estado:** Riverpod (`flutter_riverpod: ^2.6.1`), con `StreamProvider` para todo lo que viene de Firestore/Auth en tiempo real (ver sección 9, `app_providers.dart`).
- **Navegación:** `go_router: ^14.6.2`, con `refreshListenable` atado a un `ValueNotifier<AsyncValue<AppUser?>>` que reacciona al estado de auth.
- **Backend:** Firebase —
  - **Firebase Auth** (email + contraseña, siempre un **número de 6 dígitos** — decisión de producto, no una restricción de Firebase).
  - **Cloud Firestore** (toda la data: usuarios, grupos, ubicaciones, alertas, chat, configuración).
  - **Firebase Cloud Messaging (FCM)** — payload **"solo data"**, sin campo `notification` (ver sección 11). Decisión de diseño no negociable: evita notificaciones duplicadas.
  - **Firebase Storage** — fotos y audios del chat.
  - **Cloud Functions** (Node.js 20, `firebase-functions` v5, `firebase-admin` v12) — un único trigger `onCreate` sobre `alerts/{alertId}` que arma el push y lo manda vía FCM HTTP v1.
- **Mapa:** OpenStreetMap vía `flutter_map: ^7.0.2` + `latlong2`. Tiles: `https://tile.openstreetmap.org/{z}/{x}/{y}.png` (sin API key, gratuito, con las limitaciones de uso justo de OSM).
- **GPS:**
  - `geolocator: ^13.0.2` — tracking en **primer plano** (stream + foreground service propio del plugin).
  - `flutter_background_service: ^5.1.0` + `flutter_background_service_android: ^6.2.2` — servicio nativo de Android real para el tracking en **segundo plano** (isolate propio). **Activamente usado desde el 2026-08-10** — antes de esa fecha estaba declarado pero sin uso.
- **Persistencia local:**
  - `sqflite` — caché local de ubicaciones ("caja negra" local + cola de sincronización offline) y alertas.
  - Un archivo JSON plano (`user_session.json`, vía `path_provider`) — sesión local liviana, usada para detectar "sesión iniciada en otro dispositivo" y como respaldo de la ruta inicial si Firebase Auth tarda en resolver.
  - `shared_preferences` clásico — flags simples (`battery_saver`, `fcm_server_key` sin uso real).
  - `SharedPreferencesAsync` (del mismo paquete `shared_preferences`, API sin caché por isolate) — usado **específicamente** para el estado compartido entre el tracking de primer y segundo plano (ver sección 10.3, es un punto crítico).
- **Notificaciones locales:** `flutter_local_notifications: ^18.0.0`.
- **Multimedia:** `image_picker` (fotos), `record` (audio), `audioplayers` (reproducción).
- **Otros:** `permission_handler`, `android_intent_plus` (abrir Ajustes de batería y enlace directo a WhatsApp), `share_plus`, `file_picker`, `intl`, `uuid`, `google_fonts` (Inter), `cached_network_image`.

### 3.1 `pubspec.yaml` — dependencias exactas

```yaml
name: miclan
description: Sistema de Proteccion Familiar
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.5.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  go_router: ^14.6.2
  google_fonts: ^6.2.1
  intl: ^0.19.0
  uuid: ^4.5.1
  shared_preferences: ^2.3.3
  cached_network_image: ^3.4.1
  cupertino_icons: ^1.0.8
  firebase_core: ^3.8.1
  firebase_auth: ^5.3.4
  cloud_firestore: ^5.6.0
  firebase_messaging: ^15.1.6
  firebase_storage: ^12.3.7
  flutter_map: ^7.0.2
  latlong2: ^0.9.1
  geolocator: ^13.0.2
  permission_handler: ^11.3.1
  image_picker: ^1.1.2
  record: ^7.0.0
  audioplayers: ^6.1.0
  path_provider: ^2.1.4
  share_plus: ^10.0.2
  file_picker: ^8.1.2
  sqflite: ^2.3.3
  path: ^1.9.0
  flutter_background_service: ^5.1.0
  flutter_background_service_android: ^6.2.2
  android_intent_plus: ^6.1.0
  flutter_local_notifications: ^18.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
```

Cloud Functions (`functions/package.json`):
```json
{
  "name": "miclan-functions",
  "version": "1.0.0",
  "description": "MiClan Cloud Functions",
  "main": "index.js",
  "engines": { "node": "20" },
  "dependencies": {
    "axios": "^1.7.9",
    "firebase-admin": "^12.7.0",
    "firebase-functions": "^5.1.1"
  },
  "private": true
}
```

Android — `android/app/build.gradle.kts` (config clave):
```kotlin
android {
    namespace = "com.agiletask.miclan"
    compileSdk = 36
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    defaultConfig {
        applicationId = "com.agiletask.miclan"
        minSdk = flutter.minSdkVersion   // heredado del template Flutter
        targetSdk = flutter.targetSdkVersion
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")  // ⚠ ver nota abajo
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}
dependencies {
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("com.google.firebase:firebase-messaging:24.1.0")
}
```

> ⚠️ **El build de release usa el keystore de debug** (`signingConfigs.getByName("debug")`). Sirve para instalar y probar libremente, pero **no está apto para publicar en Google Play** — antes de publicar hace falta generar un keystore de release real y configurar `signingConfigs.release` con sus credenciales.

### 3.2 Requisito de entorno para compilar (no es parte de la app, pero bloquea el build si falta)

- **JDK 17** — Gradle 8.14 (el que trae el proyecto) **no soporta** el JBR 25 que trae Android Studio por defecto. Hay que instalar **Eclipse Temurin JDK 17** y apuntar `android/gradle.properties` → `org.gradle.java.home` a esa instalación:
  ```properties
  org.gradle.java.home=C:\\Program Files\\Eclipse Adoptium\\jdk-17.0.20.8-hotspot
  ```
  (ruta de ejemplo en Windows; ajustar según dónde se instale). Sin esto, `flutter build apk` falla con un error de compatibilidad de bytecode.

---

## 4. Estructura de carpetas del proyecto (estado actual)

```
lib/
  main.dart                          # bootstrap, tema, GoRouter, splash, FCM handlers, fix de sesión duplicada
  firebase_options.dart              # generado por flutterfire configure (el que realmente se importa)
  core/firebase_options.dart         # ⚠ ARCHIVO DUPLICADO/HUÉRFANO — mismo contenido que el de arriba,
                                      #   pero NADA lo importa. Candidato a borrar en una limpieza.
  models/
    app_models.dart                  # AppUser, AppGroup, PendingRequest, AppAlert, GeofenceZone,
                                      # QuickMessageItem, QuickMessagesConfig, UserSession
  providers/
    app_providers.dart               # todos los Provider/StreamProvider de Riverpod
  services/
    auth_service.dart                # Firebase Auth + sesión local + fixes de token/carrera
    firestore_service.dart           # toda la lógica de Firestore (grupos, ubicaciones, alertas, config)
    location_service.dart            # GPS en PRIMER PLANO (stream de geolocator + timer de sync)
    background_location_service.dart # GPS en SEGUNDO PLANO (servicio nativo Android, isolate propio)
    location_config.dart             # config/umbrales COMPARTIDOS entre ambos caminos de GPS
    stream_retry.dart                # selfHealingStream(): reintento automático de streams de Firestore
    notification_service.dart        # canales Android + notificaciones locales
    battery_optimization_service.dart
    database_helper.dart             # SQLite (caja negra local + cola offline)
    storage_service.dart             # subida de fotos/audios a Firebase Storage
    backup_service.dart              # exportación E IMPORTACIÓN de backup local (ambas implementadas)
    geofence_service.dart            # lógica de cruce de geofence — implementada pero DESCONECTADA (ver 12.4)
  screens/
    welcome_screen.dart              # splash con animación (no es una ruta de GoRouter, ver sección 8.1)
    auth_screen.dart                 # login / registro
    onboarding_screen.dart           # crear grupo / solicitar unión
    home_screen.dart                 # mapa principal (pantalla más grande, ~1590 líneas)
    chat_screen.dart                 # chat grupal
    settings_screen.dart             # configuración, admin, caja negra (~1290 líneas)
  widgets/
    app_footer.dart                  # pie de copyright reutilizable
android/
  app/src/main/AndroidManifest.xml
  app/build.gradle.kts
  gradle.properties                  # apunta a JDK 17 (ver 3.2)
functions/
  index.js                           # Cloud Function sendAlertNotification
  package.json
firestore.rules
firestore.indexes.json
firebase.json                        # firestore + functions (codebase "default" → carpeta functions/)
.firebaserc                          # proyecto Firebase: "miclan-6dd12"
assets/
  images/app_logo.png, notification_icon.png
  sounds/aviso.wav, alerta.wav, ding_dong.wav
test/
  widget_test.dart
```

**Notas de limpieza pendientes** (no urgentes, pero relevantes si se reconstruye desde cero — no las repitan):
- `lib/core/firebase_options.dart` es un duplicado sin uso de `lib/firebase_options.dart`. Al regenerar con `flutterfire configure`, dejar solo uno.
- `android/app/google-services.json` **está versionado en este repo** (no está en `.gitignore`). Es habitual excluirlo, pero no es estrictamente un secreto (viaja embebido en cualquier APK igual); si se reconstruye el proyecto y se prefiere no versionarlo, agregarlo a `.gitignore` y documentar que hay que generarlo por proyecto de Firebase.

---

## 5. Configuración de Firebase (paso a paso, para recrear el proyecto desde cero)

1. Crear proyecto en Firebase Console (este proyecto real se llama `miclan-6dd12`, ver `.firebaserc`).
2. Habilitar **Authentication → método Email/contraseña**.
   - La contraseña siempre es un **número de 6 dígitos**: Firebase acepta cualquier string ≥6 caracteres: la restricción "6 dígitos numéricos" es una validación de producto hecha en el cliente (`auth_screen.dart` con `FilteringTextInputFormatter.digitsOnly` + `maxLength: 6`, y `auth_service.dart` valida de nuevo con `int.tryParse` antes de crear la cuenta).
3. Habilitar **Cloud Firestore** (modo producción, con las reglas de la sección 7).
4. Habilitar **Firebase Storage** (fotos/audios del chat).
5. Habilitar **Cloud Messaging**.
6. Instalar la CLI de FlutterFire y correr `flutterfire configure` desde la raíz del proyecto → genera `lib/firebase_options.dart` y `android/app/google-services.json` (hay que generar este último por cada proyecto de Firebase nuevo).
7. `applicationId`/`namespace` de Android: `com.agiletask.miclan` (cambiarlo si se reconstruye bajo otra cuenta/paquete, y regenerar `google-services.json` acorde).
8. Desplegar reglas + índices de Firestore:
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```
9. Desplegar Cloud Functions:
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```
10. En Android, el plugin de Google Services ya está aplicado en `android/app/build.gradle.kts` (`id("com.google.gms.google-services")`) — boilerplate estándar de FlutterFire.
11. Instalar **JDK 17** y apuntar `org.gradle.java.home` (ver sección 3.2) antes de intentar compilar.

---

## 6. Modelo de datos en Firestore

```
users/{uid}
  email: string
  displayName: string
  groupId: string | null
  fcmToken: string | null
  sessionId: string | null        # detecta "sesión en otro dispositivo"
  phone: string | null            # para el enlace directo a WhatsApp
  createdAt: Timestamp

groups/{groupId}
  name: string
  joinCode: string (6 caracteres, mayúsculas)
  ownerId: string (uid del admin — NO hay campo "role" separado, ver sección 2)
  createdAt: Timestamp

  groups/{groupId}/pendingRequests/{uid}
    uid: string
    displayName: string
    requestedAt: Timestamp
    status: 'pending' | 'approved' | 'rejected'

  groups/{groupId}/geofence/main        # doc único, zona segura circular
    lat, lng, radiusMeters, name

  groups/{groupId}/config/quickMessages # mensajes rápidos configurables por el admin
    allButtons: [{title, message}, ×4]      # modo "Todos"
    questionButtons: [{title, message}, ×3] # modo "un miembro", fila de arriba
    answerButtons: [{title, message}, ×3]   # modo "un miembro", fila de abajo
    updatedAt: Timestamp

locations/{uid}                    # ubicación actual (para el mapa en vivo)
  groupId: string
  lat, lng: number
  timestamp: Timestamp (server)
  updatedAt: string (ISO, cliente)

  locations/{uid}/history/{autoId}  # "caja negra": cada punto grabado
    groupId: string
    lat, lng: number
    timestamp: Timestamp (server)
    recordedAt: string (ISO, cliente)

alerts/{alertId}                   # dispara la Cloud Function; feed de chat Y canal de alertas
  groupId: string
  senderId: string                 # o 'system' para avisos automáticos (ej. expulsión)
  receiverId: 'all' | uid
  type: 'SOS' | 'photo' | 'audio' | 'command_message' | 'quick_message' | 'geofence' | 'system'
  payload: string                  # texto del mensaje, o URL de storage para photo/audio
  senderName: string | null
  timestamp: Timestamp
  sosStatus: 'active' | 'cancelled' | null   # solo para type == 'SOS'
  cancelledBy: string | null
  cancelledAt: Timestamp | null
```

**Rotación automática:** `alerts` se poda a 300 documentos por grupo (`FirestoreService._rotateAlerts`, corre después de cada `sendAlert`) y la tabla local SQLite `locations`/`alerts` también se poda a 300 filas por grupo (`DatabaseHelper._rotateLocations`/`_rotateAlerts`). El historial de Firestore (`locations/{uid}/history`) **no tiene rotación** — crece indefinidamente.

---

## 7. Reglas de seguridad de Firestore (`firestore.rules`, texto completo — vigente, sin cambios en esta sesión)

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow create: if request.auth != null && request.auth.uid == uid;

      // Lectura abierta a cualquier usuario autenticado: la necesita
      // getGroupMembersStream para listar a todo el grupo (no solo a uno mismo).
      allow read: if request.auth != null;

      // Actualizacion: el propio usuario (perfil, fcmToken, sessionId), o el
      // admin del grupo actual (para expulsar) o del grupo al que se asigna
      // (para aprobar una solicitud de union).
      allow update: if request.auth != null && (
        request.auth.uid == uid ||
        (resource.data.groupId != null &&
         get(/databases/$(database)/documents/groups/$(resource.data.groupId)).data.ownerId == request.auth.uid) ||
        (request.resource.data.groupId != null &&
         get(/databases/$(database)/documents/groups/$(request.resource.data.groupId)).data.ownerId == request.auth.uid)
      );
      allow delete: if false;
    }

    match /groups/{groupId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.resource.data.ownerId == request.auth.uid;
      allow update, delete: if request.auth != null && resource.data.ownerId == request.auth.uid;

      match /geofence/{docId} {
        allow read, write: if request.auth != null;
      }

      // Configuracion del grupo (ej: mensajes rapidos). Lectura para
      // cualquier miembro del grupo, escritura solo para el admin.
      match /config/{docId} {
        allow read: if request.auth != null &&
                       get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == groupId;
        allow write: if request.auth != null &&
                       get(/databases/$(database)/documents/groups/$(groupId)).data.ownerId == request.auth.uid;
      }

      // Solicitudes de union al grupo (requestJoinGroup / approveRequest / rejectRequest)
      match /pendingRequests/{uid} {
        allow create: if request.auth != null && request.auth.uid == uid;
        allow read: if request.auth != null &&
                       (request.auth.uid == uid ||
                        get(/databases/$(database)/documents/groups/$(groupId)).data.ownerId == request.auth.uid);
        allow update, delete: if request.auth != null &&
                       get(/databases/$(database)/documents/groups/$(groupId)).data.ownerId == request.auth.uid;
      }
    }

    match /locations/{uid} {
      allow write: if request.auth != null && request.auth.uid == uid;
      allow read: if request.auth != null &&
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == resource.data.groupId;

      // Historial de ubicaciones (caja negra / recorrido en mapa)
      match /history/{historyId} {
        allow create: if request.auth != null && request.auth.uid == uid;
        allow read: if request.auth != null &&
                       get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId ==
                       get(/databases/$(database)/documents/locations/$(uid)).data.groupId;
      }
    }

    match /alerts/{alertId} {
      allow create: if request.auth != null &&
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == request.resource.data.groupId &&
                     (request.resource.data.senderId == request.auth.uid ||
                      (request.resource.data.senderId == 'system' &&
                       get(/databases/$(database)/documents/groups/$(request.resource.data.groupId)).data.ownerId == request.auth.uid));
      allow read: if request.auth != null &&
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == resource.data.groupId;
      // Necesario para cancelSOS (actualiza sosStatus/cancelledBy en un alert existente)
      allow update: if request.auth != null &&
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == resource.data.groupId;
    }
  }
}
```

**Puntos que costó ajustar (y por qué quedaron así) — no "corregirlos" mal en el futuro:**
- **`users` lectura abierta a cualquier autenticado**, no solo al propio uid: la necesita `getGroupMembersStream` para armar el mapa, el chat y los chips de miembros con el `displayName` de otros usuarios.
- **`users` actualización con 3 condiciones OR**: propio usuario, admin del grupo **actual** del documento (para expulsar), o admin del grupo **destino** (`request.resource.data.groupId`, para aprobar una solicitud de unión — es un `update` que le asigna un `groupId` nuevo). Faltar cualquiera rompe expulsar o aprobar.
- **`locations/{uid}/history`**: la lectura hace un `get()` extra sobre `locations/{uid}` para comparar `groupId` (en vez de comparar contra `resource.data.groupId` directo), para que la regla sea robusta ante lecturas de **colección completa** (queries), no solo documento puntual.

### 7.1 Índices compuestos (`firestore.indexes.json`, completo)

```json
{
  "indexes": [
    { "collectionGroup": "alerts", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "groupId", "order": "ASCENDING" }, { "fieldPath": "timestamp", "order": "DESCENDING" } ] },
    { "collectionGroup": "alerts", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "groupId", "order": "ASCENDING" }, { "fieldPath": "timestamp", "order": "ASCENDING" } ] },
    { "collectionGroup": "alerts", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "groupId", "order": "ASCENDING" }, { "fieldPath": "type", "order": "ASCENDING" },
      { "fieldPath": "sosStatus", "order": "ASCENDING" }, { "fieldPath": "timestamp", "order": "DESCENDING" } ] },
    { "collectionGroup": "history", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "groupId", "order": "ASCENDING" }, { "fieldPath": "timestamp", "order": "ASCENDING" } ] },
    { "collectionGroup": "history", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "groupId", "order": "ASCENDING" }, { "fieldPath": "timestamp", "order": "DESCENDING" } ] }
  ],
  "fieldOverrides": []
}
```

---

## 8. Pantallas (detalle completo)

### 8.1 `WelcomeScreen` (splash)

**No es una ruta de GoRouter** — se muestra directamente como `home:` de un `MaterialApp` provisorio mientras `_MiClanAppState._initApp()` (en `main.dart`) todavía no terminó de resolver sesión/router (`if (!_initialized || _router == null) return MaterialApp(home: WelcomeScreen())`). Una vez listo, se cambia a `MaterialApp.router` con el `GoRouter` real.

- Logo (`assets/images/app_logo.png`) con efecto "explosión": onda expansiva (círculo con `RadialGradient`) detrás del logo, logo apareciendo con `Curves.elasticOut` desde escala 0.
- "MiClan V.2.0" (30px, bold) + "Monitoreo Grupal Activo" (subtítulo).
- `AppCopyrightFooter` al pie.
- Duración: animación de 2.8s; `main.dart` fuerza una duración mínima total de **3 segundos** (`Future.delayed`) antes de pasar a la ruta real, sin importar cuán rápido resuelva el auth.

### 8.2 `AuthScreen` (login / registro) — ruta `/login`

- Toggle entre modo login y modo registro (`_isLogin`).
- **Login:** email + contraseña (6 dígitos numéricos, teclado numérico, `obscureText`).
- **Registro:** nombre (máx. 10 caracteres), email, contraseña de 6 dígitos + repetir contraseña. Al registrarse: se crea la cuenta y **se hace sign-out inmediato** (`AuthService.signUp` termina con `_auth.signOut()`), mostrando "Cuenta creada. Ahora inicia sesión con tu email y contraseña." — obliga a loguearse explícitamente, no queda logueado automáticamente tras registrarse.
- Errores de Firebase se limpian de corchetes (`e.toString().replaceAll(RegExp(r'\[.*?\]'), '')`) antes de mostrarse.

### 8.3 `OnboardingScreen` (crear grupo / solicitar unión) — ruta `/onboarding`

Se muestra cuando el usuario está logueado pero `user.groupId == null` (lo decide el `redirect` de GoRouter en `main.dart`).

- **Crear Grupo**: pide nombre, `FirestoreService.createGroup` genera un `joinCode` de 6 caracteres, crea el doc `groups` con `ownerId = uid` (esto es lo único que lo vuelve admin) y actualiza `users/{uid}.groupId`.
- **Solicitar unirme**: input de código de 6 caracteres → `requestJoinGroup` crea `groups/{groupId}/pendingRequests/{uid}` con `status: 'pending'` y muestra "Esperando aprobación del administrador...". Esta pantalla escucha `currentUserProvider` en vivo (`ref.listenManual`): apenas el admin aprueba y `user.groupId` deja de ser null, navega sola a `/home` con `context.go('/home')` — no hace falta reabrir la app.

### 8.4 `HomeScreen` (mapa principal — la pantalla más compleja, ruta `/home`)

Implementa `WidgetsBindingObserver` para reaccionar al ciclo de vida de la app (crítico para el handoff de GPS, ver sección 10). Estructura general (todo dentro de un `Stack`):

1. **Mapa** (`flutter_map`), marcador por cada miembro del grupo (posición en tiempo real vía `locations/{uid}` stream).
2. **Banners de advertencia** (apilados): optimización de batería activa, o falta el permiso de ubicación "todo el tiempo". Se revisan automáticamente cada vez que la app vuelve a primer plano (`didChangeAppLifecycleState` → `resumed`), no solo al abrir la pantalla.
3. **Botón S.O.S.**: crea `alerts` con `type: 'SOS'`, `receiverId: 'all'`. Si ya hay un SOS activo propio, permite cancelarlo (`sosStatus: 'cancelled'`).
4. **Chips de miembros** (fila horizontal): un chip por cada **otro** miembro (el propio usuario queda excluido). Tocar centra el mapa y lo selecciona como destinatario.
5. **Combo de destinatario** ("Todos" o un miembro puntual).
6. **Área de mensajes rápidos**, dos modos según destinatario:
   - **Modo "Todos"**: 4 botones configurables (`QuickMessagesConfig.allButtons`).
   - **Modo "un miembro"**: grilla 2×3 — 3 "preguntas" arriba (`questionButtons`) + 3 "respuestas" abajo (`answerButtons`).
   - **Bento lateral fijo** (siempre visible): botón `(...)` (mensaje manual) + botón `WP` (abre WhatsApp con `android_intent_plus`, link `https://wa.me/{telefono}?text=...`, usando el teléfono cargado del miembro seleccionado en Configuración).
   - Los 10 textos configurables se leen de `groupQuickMessagesProvider` (stream, se refresca solo si el admin los cambia con la app abierta).
7. **Botón flotante "Mi ubicación"**.
8. **Modal de recorrido** (`_RouteMapModal`): fit-to-bounds automático, marcadores tocables (zona táctil 32×32) con cartel de fecha/hora dentro del propio bento del mapa, muestreo a ~40 marcadores si hay más puntos (la polilínea sí usa todos), selector de rango de fechas (campos que abren date/time picker nativo + chips 24h/2d/7d/30d).
9. **Menú de administración de miembros** (solo admin): lista de miembros con botón expulsar + lista de solicitudes pendientes con aprobar/rechazar.
10. **Marcador de un miembro → bottom sheet de acciones rápidas** (`_onMarkerTap`): 5 botones fijos, **no configurables** (independientes del bento principal): "Llamame", "¿Llegaste?", "¿Todo bien?", "Volvé", "¿Dónde estás?".
11. Pie de copyright.

### 8.5 `ChatScreen` — ruta `/chat`

Chat grupal sobre la colección `alerts` (comparte backend con las alertas). Soporta texto libre, fotos (`image_picker` → Storage → `type: 'photo'`), audios (mantener presionado el micrófono para grabar, `record` + `audioplayers`, `type: 'audio'`). Burbujas alineadas según si el mensaje es propio; los mensajes de tipo `SOS`/`system`/`geofence` se muestran centrados con estilo diferenciado (no como burbujas normales).

### 8.6 `SettingsScreen` — ruta `/settings`

`ListView` con padding inferior extra (para no tapar el último ítem con la barra de navegación de Android):

1. **Cuenta**: nombre, email (solo lectura), teléfono editable (WhatsApp).
2. **Grupo**: nombre; si es admin, también el código de unión.
3. **Zona Segura (geofence)** — solo admin: crear/eliminar un círculo (centro + radio). *(La detección de cruce existe en código pero no está conectada, ver 12.4.)*
4. **Mensajes Rápidos** — solo admin: editar los 10 botones configurables (4 + 3 + 3).
5. **Caja Negra del Grupo** — solo admin: selector de miembro + tabla de últimos registros + mismo modal de mapa con recorrido que en Home.
6. **Batería**: switch "Modo ahorro" (cambia el intervalo de GPS entre 1 min/50m y 5 min/200m, ver sección 10) + acceso directo a desactivar la optimización de batería del sistema.
7. **Caja Negra Local**: **Exportar backup** (`share_plus`, JSON con ubicaciones + alertas locales) y **Importar backup** (`file_picker`, reemplaza los datos locales — **ambas funciones están implementadas**, a diferencia de lo que decía el informe anterior).
8. **Grupo/Cuenta**:
   - **Salir del grupo**: si es admin, primero confirma que se borrará el grupo entero (ver 12.5) para todos; si no es admin, solo se borra su propio `groupId`.
   - **Eliminar cuenta permanentemente**: confirma, sale del grupo si tenía uno (mismo flujo que arriba), borra el documento `users/{uid}` y llama a `FirebaseAuth.currentUser.delete()`. **Esta función no estaba documentada en el informe anterior.**
9. **Cerrar sesión** (logout completo).
10. Pie de copyright.

---

## 9. Arquitectura de estado (Riverpod) — `app_providers.dart` completo

```dart
authServiceProvider       = Provider((ref) => AuthService());
firestoreServiceProvider  = Provider((ref) => FirestoreService());
locationServiceProvider   = Provider((ref) => LocationService());
storageServiceProvider    = Provider((ref) => StorageService());
geofenceServiceProvider   = Provider((ref) => GeofenceService());
backupServiceProvider     = Provider((ref) => BackupService());

currentUserProvider        : StreamProvider<AppUser?>              // base de authStateChanges() + doc Firestore
currentGroupProvider       : StreamProvider<AppGroup?>             // depende de currentUserProvider.groupId
groupMembersProvider       : StreamProvider<List<AppUser>>         // depende de currentGroupProvider.id
pendingRequestsProvider    : StreamProvider<List<PendingRequest>>  // depende de currentGroupProvider.id
memberLocationProvider     : StreamProvider.family<LatLng?, String>(uid)
groupAlertsProvider        : StreamProvider<List<AppAlert>>        // depende de currentGroupProvider.id
activeSOSProvider          : StreamProvider<AppAlert?>             // depende de currentGroupProvider.id
geofenceZoneProvider       : StreamProvider<GeofenceZone?>         // depende de currentGroupProvider.id
groupQuickMessagesProvider : StreamProvider<QuickMessagesConfig>   // depende de currentGroupProvider.id
```

Todos los providers que dependen de `currentGroupProvider` devuelven `Stream.value(vacío/null)` si todavía no hay grupo, para no romper la UI. `currentUserProvider` es la raíz de toda la cadena — cualquier problema con su stream (ver sección 12) se propaga a todos los demás.

---

## 10. GPS: arquitectura completa (reescrita — estado post 2026-08-10, verificado en dispositivo real)

Este es el componente más complejo y el que más iteraciones tuvo. Hay **dos caminos de grabación independientes**, que comparten configuración y umbrales a través de un tercer archivo, y un "handoff" que decide cuál está activo según si la app está en primer o segundo plano.

### 10.1 `location_config.dart` — configuración y umbrales compartidos

```dart
const double kSameLocationThresholdMeters = 20.0;
const Duration kNormalTrackingInterval = Duration(minutes: 1);
const Duration kBatterySaverTrackingInterval = Duration(minutes: 5);

Future<Duration> getTrackingInterval();           // lee 'battery_saver' de SharedPreferences
Future<LastRecordedPosition?> loadLastRecordedPosition();
Future<void> saveLastRecordedPosition(double lat, double lng);
bool isSameAsLastRecorded(LastRecordedPosition? last, double lat, double lng); // distancia <= 20m
```

**Punto crítico, no revertir:** este archivo usa `SharedPreferencesAsync` (no `SharedPreferences.getInstance()` clásico) para persistir "última posición grabada". `SharedPreferences.getInstance()` cachea todos los valores en memoria la **primera vez que se llama dentro de un isolate**, y ya no los vuelve a leer del disco en ese isolate. Como el tracking de primer plano corre en el isolate principal de la UI y el de segundo plano corre en **otro isolate completamente separado** (propio de `flutter_background_service`), usar el `SharedPreferences` clásico hacía que cada isolate tuviera su propia copia vieja de "última posición grabada" — el fix fue migrar a `SharedPreferencesAsync`, que no cachea y consulta la plataforma en cada get/set.

### 10.2 `location_service.dart` — tracking en PRIMER PLANO

- `startTracking(uid, groupId)`: obtiene la posición actual, la graba si no es igual a la última grabada (ver 10.5 sobre por qué este chequeo es necesario), y arranca:
  - Un **stream de `geolocator`** (`AndroidSettings(distanceFilter: 10, intervalDuration: 20s, foregroundNotificationConfig: {...})`) — cada posición nueva pasa por `_handlePosition`.
  - Un **`Timer` de sincronización forzada**, reprogramado en cada ciclo con el intervalo configurable (`getTrackingInterval()`: 1 min normal / 5 min "Modo ahorro"), que graba un punto si el usuario se movió >20m desde el último grabado, o solo manda un "latido" (`touchLocation`, sin nuevo punto de historial) si no se movió.
- `_handlePosition(uid, groupId, position)`:
  1. Throttle por distancia desde la última posición **cruda** recibida (no la grabada): 50m en modo normal, 200m en modo ahorro (`shouldUpload`).
  2. Si la posición está a ≤20m de la **última efectivamente grabada** (`isSameAsLastRecorded`), no graba nada (ni siquiera si `shouldUpload` era true) — evita duplicados finos.
  3. Si pasó el filtro y `shouldUpload` era true, graba el punto (`_recordPoint`).
- `_recordPoint`: inserta en SQLite local, persiste la nueva "última posición grabada" (`saveLastRecordedPosition`), y sube a Firestore (`locations/{uid}` + `locations/{uid}/history`); si falla la subida (sin señal), el punto queda `synced=0` en SQLite para reintentar después (`_syncPendingLocations`) — nunca se sube dos veces (se marca `synced` solo si la escritura directa se confirma, o queda pendiente para un único reintento posterior).

### 10.3 `background_location_service.dart` — tracking en SEGUNDO PLANO (servicio nativo real)

Usa `flutter_background_service` para levantar un **Servicio de Android real e independiente**, con su propio isolate de Dart y su propio ciclo de vida — sigue vivo con la app cerrada/minimizada/teléfono dormido, algo que el foreground service propio de `geolocator` (usado en primer plano) no garantiza en todos los fabricantes (muchos congelan igual el isolate de la UI con la pantalla apagada).

- `BackgroundLocationService.initialize()` (se llama una vez en `main()`, **antes** de `runApp`): configura (sin arrancar) el servicio — `isForegroundMode: true`, `foregroundServiceTypes: [location]`, notificación fija en la barra (`kGpsTrackingNotificationChannelId`, `Importance.none` — ver sección 11).
- `BackgroundLocationService.start(uid, groupId)` / `.stop()`: arrancan/detienen el servicio nativo. Guardan `uid`/`groupId` en `SharedPreferences` para que el isolate del servicio (que arranca "en frío", sin contexto de la app) sepa para quién grabar.
- Dentro del isolate del servicio (`_onServiceStart`, anotado `@pragma('vm:entry-point')`): re-inicializa Firebase (obligatorio, es un isolate nuevo), y corre un loop (`tick()` cada 1 o 5 min según `getTrackingInterval()`) que obtiene la posición actual (`Geolocator.getCurrentPosition`), la compara contra `loadLastRecordedPosition()` (el mismo dato compartido que usa el primer plano, vía `SharedPreferencesAsync`) y graba o solo manda latido, exactamente con el mismo criterio de 20m que el primer plano. También reintenta puntos pendientes de subir.

### 10.4 El "handoff" — `HomeScreen` decide cuál camino está activo

```dart
didChangeAppLifecycleState(resumed)        → _resumeForegroundTracking():
    BackgroundLocationService.stop();
    locationService.startTracking(uid, groupId);   // vuelve el tracking responsivo por distancia

didChangeAppLifecycleState(paused|detached) → _handoffToBackgroundTracking():
    locationService.stopTracking();
    BackgroundLocationService.start(uid, groupId); // arranca el servicio nativo
```

**Importante:** `AppLifecycleState.paused` no significa solo "el usuario minimizó la app" — también se dispara cuando **la pantalla se apaga sola** (bloqueo automático por timeout), incluso con la app "abierta" desde la perspectiva del usuario. Esto es esperado e intencional: es justamente el caso que necesita el handoff a background.

### 10.5 Bugs de GPS resueltos en la sesión del 2026-08-10 (root-caused con `adb logcat` en dispositivo real — ver sección 12 para la metodología completa)

1. **Bug de caché de `SharedPreferences` por isolate** (ver 10.1) — real, pero no era la causa dominante de los duplicados reportados.
2. **Reentrancia en `startTracking()`** (causa real de "graba >10 veces por minuto sin moverse"): Android pausa/reanuda la Activity cuando aparece y se cierra el diálogo del permiso de ubicación, disparando `didChangeAppLifecycleState(resumed)` varias veces casi seguidas. Cada una llamaba a `startTracking()`, y el guard original (`if (_positionSub != null) return`) no alcanzaba a bloquear llamadas concurrentes que entraban **antes** de que `_positionSub` se asignara (varios `await` más abajo) — cada llamada grababa su propio punto inicial **sin chequear contra el último grabado**. Confirmado en logcat: 5 puntos idénticos grabados en <700ms. **Fix:** `startTracking()` ahora comparte una única `Future` "en vuelo" (`_startFuture`) entre llamadas concurrentes, y el punto inicial obtenido en el arranque también respeta `isSameAsLastRecorded` (antes se grababa sin chequear).

### 10.6 Cómo verificar que el GPS graba bien en segundo plano (guía práctica)

1. Conectar el teléfono por USB con depuración habilitada (`adb devices` debe listarlo).
2. `adb logcat` filtrando por `flutter` mientras se deja el teléfono bloqueado y en movimiento (o simulando con logs temporales, como se hizo en esta sesión).
3. Desde el admin, Configuración → Caja Negra del Grupo → seleccionar ese miembro: deberían aparecer filas nuevas sin que el miembro haya abierto la app.
4. Si el miembro se queda quieto, no deberían aparecer filas nuevas (por `isSameAsLastRecorded`), pero su posición en el mapa sigue "viva" por el latido periódico.
5. Si en algún equipo puntual el GPS se corta igual estando dormido, sospechar primero del **gestor de batería agresivo del fabricante** (Xiaomi/MIUI, Huawei, Samsung en algunos modos) — requiere habilitar manualmente "inicio automático"/"sin restricciones" en los ajustes específicos de esa marca, no es resoluble solo con código Android estándar.

**Lección de esta sesión, para no repetir el patrón "fix por lectura de código → no cambia nada":** ninguna de las hipótesis basadas solo en leer el código coincidía con la causa real. Conseguir `adb logcat` en un dispositivo real y ver la secuencia exacta de eventos fue lo que permitió encontrar la causa real en minutos, después de rondas enteras de fixes "correctos por código" que no cambiaban el síntoma reportado.

---

## 11. Notificaciones push (FCM) y locales — diseño completo

- **Payload "solo data"** (sin campo `notification`): decisión de diseño no negociable, evita duplicados (ver Cloud Function, sección 11.1).
- **Canales de notificación Android** (`notification_service.dart`):

| Canal | Importancia | Sonido/vibración | Uso |
|---|---|---|---|
| `sos_channel` | `max` | sí (`alerta.wav`), enciende pantalla (`fullScreenIntent`) | Pánico |
| `msg_channel` | `high` | sí | Chat, mensajes rápidos, comandos, sistema |
| `geofence_channel` | `high` | — | Entrada/salida de zona segura (no conectado aún, ver 12.4) |
| `gps_tracking_channel` | `none` | no | Ícono fijo del foreground service de background GPS, sin interrumpir (mismo criterio que usa `geolocator_android` para su propia notificación) |

- **Background handler** (`_firebaseMessagingBackgroundHandler` en `main.dart`, `@pragma('vm:entry-point')`): re-inicializa Firebase (isolate separado) y muestra la notificación local leyendo `title`/`body`/`channelId` de `message.data` — nunca de `message.notification` (no existe en este payload).
- **Foreground handler** (dentro de `_initApp`): mismo criterio.
- **ID fijo `9999`** para notificaciones SOS: evita que se acumulen múltiples avisos de pánico en la barra si llegan varios pushes de la misma alerta.
- **Permiso `POST_NOTIFICATIONS`** se pide **una única vez, en `main()`, antes de `runApp()`**, con timeout de 15s — crítico, ver bug 12.2.

### 11.1 Cloud Function `sendAlertNotification` (`functions/index.js`, texto completo)

Trigger `onCreate` sobre `alerts/{alertId}`:
1. Lee la alerta (`groupId`, `senderId`, `receiverId`, `type`, `payload`, `senderName`).
2. Busca todos los `users` con `groupId` igual, excluye al emisor, filtra por `receiverId` si no es `'all'`.
3. Junta `fcmToken`s válidos (string, longitud > 20).
4. Obtiene access token OAuth2 (`admin.credential.applicationDefault().getAccessToken()` — API HTTP v1 de FCM, no el SDK legacy).
5. Arma `title`/`body`/`channelId` según `type` (tabla completa en el código, ver abajo).
6. Envía un mensaje FCM **individual por token** vía `POST https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`, con `android.priority: 'high'`, `ttl: '3600s'`.
7. Si un envío falla con `UNREGISTERED`/`INVALID_ARGUMENT` (token vencido), borra ese `fcmToken` del usuario en Firestore (auto-limpieza).

| `type` | title | body | channelId |
|---|---|---|---|
| `SOS` | `S.O.S - MiClan` | `ALERTA DE PÁNICO ACTIVADA!` | `sos_channel` |
| `photo` | `MiClan - {senderName}` | `Te envié una foto` | `msg_channel` |
| `audio` | `MiClan - {senderName}` | `Te envié un audio` | `msg_channel` |
| `command_message` | `Comando - {senderName}` | `payload` | `msg_channel` |
| `geofence` | `MiClan - Geofence` | `payload` | `geofence_channel` |
| `system` | `MiClan` | `payload` | `msg_channel` |
| *(default, incluye `quick_message`)* | `MiClan - {senderName}` | `payload` | `msg_channel` |

---

## 12. Administración de miembros — flujo completo

1. El admin ve las **solicitudes pendientes** (`groups/{groupId}/pendingRequests` con `status: 'pending'`).
2. **Aprobar** (`approveRequest`): `users/{uid}.groupId = groupId` + marca la solicitud `approved`. Si el miembro tiene la app abierta esperando en Onboarding, se redirige solo a Home (ver 8.3).
3. **Rechazar** (`rejectRequest`): marca `rejected`, no toca `users/{uid}`.
4. **Expulsar** (`removeMember`): borra `groupId` del usuario (`FieldValue.delete()`) y crea un mensaje de sistema en `alerts` avisando al resto.
5. **Abandonar el grupo** (`leaveGroup`): si es el admin, borra el grupo entero (`_deleteGroup`: pendingRequests → geofence → alerts en lotes de 500 → doc `locations/{uid}` de cada miembro → doc `groups/{groupId}`). Si no es admin, solo limpia su propio `groupId`.
   - **Limitación conocida (no resuelta):** `_deleteGroup` **no borra** `groups/{groupId}/config` (mensajes rápidos) ni `locations/{uid}/history` (caja negra) de los miembros — Firestore no borra subcolecciones en cascada y el código no las recorre para esos dos casos. Quedan documentos huérfanos.

---

## 13. Historial completo de bugs encontrados y su solución (cronológico)

Memoria de por qué el código está como está — **no deshacer estos fixes sin entender la causa original**.

### 13.1 Java 25 incompatible con Gradle 8.14 — resuelto
`flutter build apk` fallaba. Instalar Temurin JDK 17 + `org.gradle.java.home` en `gradle.properties` (ver 3.2).

### 13.2 Errores de permisos de Firestore justo después de crear/iniciar sesión — resuelto
Token de ID recién emitido tarda en propagar; escrituras tempranas (sessionId, fcmToken, primera ubicación) llegaban antes. Fix: `getIdToken(true)` + 300ms de espera en `signIn`/`signUp`, y **más importante**, la misma espera movida al único punto de origen real de todos los listeners: `currentUserStream` en `auth_service.dart` (porque `authStateChanges()` emite independientemente del delay interno de `signIn`).

### 13.3 App "colgada" al aceptar el permiso de notificaciones — resuelto
Dos plugins pidiendo permisos runtime casi al mismo tiempo (`firebase_messaging` + `geolocator`) puede hacer que el diálogo del segundo pise el callback nativo del primero. Fix: pedir `POST_NOTIFICATIONS` una sola vez, en `main()`, completamente antes de `runApp()`.

### 13.4 "Flash" de login tras cerrar la app de un swipe — resuelto
La ruta inicial dependía solo de un archivo de sesión local que podía no estar actualizado. Fix: esperar (timeout 6s) la primera resolución real de `currentUserProvider.future` antes de fijar la ruta inicial.

### 13.5 Botón "..." duplicado en modo "Todos" — resuelto
El bento tenía un "(...)" fijo redundante con el del lateral. Se convirtió en un 4to botón configurable más (`allButtons` pasó de 3 a 4 ítems).

### 13.6 Login se repetía / "Reintentar pide login completo" — **causa real encontrada recién en la sesión 2026-08-10, con evidencia de dispositivo real**

Hubo **tres intentos previos** de arreglar síntomas relacionados (memoización del refresh de token, `selfHealingStream` para reintentar streams con error, relectura de sesión local en el momento de comparar) que eran fixes reales pero **no la causa dominante** — el usuario seguía reportando "pide login" después de probarlos.

**Causa real, confirmada con `adb logcat`:** en `main.dart`, el chequeo de "sesión iniciada en otro dispositivo" comparaba `user.sessionId` (de Firestore) contra el `sessionId` del archivo de sesión local **en cuanto llegaba cualquier snapshot nuevo**. El *primer* snapshot que recibe el listener justo después de un login puede traer todavía el `sessionId` **viejo** (el de la sesión anterior en ese mismo teléfono), porque el listener ya está suscripto al doc antes de que el propio `update({'sessionId': ...})` del login termine de propagarse de vuelta desde el servidor. El archivo de sesión local, en cambio, ya tenía el valor nuevo en ese instante (se escribe justo después de ese `update`). El resultado: un falso "sesión en otro dispositivo" que disparaba `signOut()` automático ~600ms después de **cada** login.

Evidencia real en logcat (resumida):
```
21:55:45.938 snapshot sessionId=SYXZY... (VIEJO)   ← primer snapshot tras el login
21:55:45.976 snapshot sessionId=U106F... (nuevo, recién escrito por signIn())
21:55:45.988 snapshot sessionId=U106F... (nuevo, confirma)
21:55:46.545 SIGNOUT por sessionId mismatch! remoto=SYXZY... local=U106F...  ← comparó contra el 1ro, viejo
21:55:46.925 permission-denied en cascada (la sesión se invalidó a mitad de escrituras pendientes)
```

**Fix:** debounce de 1.5s antes de evaluar el mismatch (`_sessionMismatchDebounce` en `main.dart`), usando siempre el valor **más reciente** de `_authListener` en el momento en que el timer finalmente dispara — así un snapshot transitorio/viejo nunca llega a disparar el `signOut()`, pero una sesión realmente abierta en otro dispositivo (que no cambia más) se sigue detectando igual, solo 1.5s más tarde.

**Verificado en dispositivo real** (Motorola moto g05) con reinstalación limpia (`adb uninstall` + `adb install`): 0 eventos de `SIGNOUT` espurio tras el fix.

### 13.7 GPS graba duplicados (>10 registros/min sin moverse) — **causa real encontrada en la misma sesión**

Ver detalle completo en la sección 10.5, punto 2 (reentrancia en `LocationService.startTracking()`). Igual que 13.6, hubo intentos previos (umbral de 20m, migración a `SharedPreferencesAsync`) que eran fixes reales pero no la causa dominante.

**Verificado en dispositivo real:** en ~5-6 minutos de uso en primer plano tras el fix, solo 2-3 grabaciones, todas por movimiento/ruido de GPS real cruzando el umbral de 20m — sin bursts de puntos idénticos.

### 13.8 Metodología para 13.6/13.7 (aplicable a cualquier bug futuro "no cambia nada")

Ambos bugs se resolvieron recién cuando se consiguió acceso a un teléfono real por `adb`. Se instrumentó el código con `debugPrint('MICLAN_DBG ...')` en los puntos exactos donde había incertidumbre (el chequeo de sessionId, el `redirect` del router, cada snapshot de Firestore con `isFromCache`, cada posición GPS recibida con su distancia al último punto grabado, el arranque real del servicio de background), se capturó `adb logcat -v time` en vivo mientras el usuario reproducía el problema en el dispositivo, y recién con esa evidencia se pudo confirmar la causa real — que en ambos casos era una condición de carrera, no lo que sugerían las hipótesis basadas solo en lectura de código. **Los logs de diagnóstico se sacaron del código antes de comitear** (eran temporales) — si se necesita volver a depurar algo similar, agregar logs equivalentes de nuevo es más rápido que seguir iterando a ciegas.

---

## 14. Notas de configuración nativa (Android)

`AndroidManifest.xml` — permisos declarados:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="com.google.android.c2dm.permission.RECEIVE" />
```

- **No declarar un `<service>` propio para FCM**: `firebase_messaging` ya registra el suyo, fusionado automáticamente. Declararlo de nuevo produce conflicto de merge y notificaciones duplicadas.
- **`<service android:name="id.flutter.flutter_background_service.BackgroundService">`** — con `foregroundServiceType="location"`, `stopWithTask="false"` (sin esto, Android mataría el servicio al deslizar la app fuera de "Recientes"). **Este servicio SÍ está activamente en uso** desde el 2026-08-10 (ver sección 10.3) — corregir cualquier documentación vieja que diga lo contrario.
- La actividad principal usa `turnScreenOn="true"` + `showWhenLocked="true"` — para que el S.O.S. encienda la pantalla del receptor aunque esté bloqueado.
- Canal de notificación por defecto vía meta-data (`msg_channel`); los canales reales se crean en runtime desde `notification_service.dart`.
- `compileSdk 36`, Java 17 (ver 3.1/3.2), `namespace`/`applicationId` = `com.agiletask.miclan`.

---

## 15. Assets

```
assets/images/app_logo.png          # logo de la app (splash + login)
assets/images/notification_icon.png # ícono para notificaciones Android
assets/sounds/aviso.wav
assets/sounds/alerta.wav            # sonido de SOS
assets/sounds/ding_dong.wav         # sonido de mensaje
```

---

## 16. Convenciones de código y estilo visual

- Paleta oscura (`AppColors` en `main.dart`): fondo `#273758`, modales `#3A4A66`, tarjetas de vidrio semitransparentes, acentos azul/verde/rojo/ámbar.
- Tipografía: `google_fonts` (Inter).
- Estilo "glassmorphism" liviano en tarjetas/tiles de Configuración.
- Todos los textos están en **español rioplatense con voseo** ("tenés", "entrá", "¿todo bien?"), con tildes correctas.
- Los modales de mapa (`_RouteMapModal` en `home_screen.dart` y `_BlackBoxRouteMapModal` en `settings_screen.dart`) son prácticamente idénticos — duplicados a propósito (distinto acento de color y rango por defecto). Candidato a unificar si se retoma el desarrollo.

---

## 17. Pendientes / mejoras futuras conocidas (no implementadas)

1. **`_deleteGroup` deja huérfanas** las subcolecciones `config` (mensajes rápidos) y `locations/{uid}/history` (caja negra) al borrar un grupo — sección 12, punto 5.
2. **`geofence_service.dart` (`checkGeofenceCrossing`) existe pero está desconectado** — no lo llama nada en el código actual (confirmado por búsqueda exhaustiva). El modelo de datos, la UI de configuración, la Cloud Function y el canal de notificación (`geofence_channel`) ya existen; falta el "pegamento": comparar la posición actual contra `GeofenceZone` en algún punto del tracking (foreground y/o background) y disparar un `sendAlert(type: 'geofence')` cuando cruce.
3. **Menú contextual del marcador** (`_onMarkerTap`, 5 botones fijos) no lee de `QuickMessagesConfig` — independiente del bento configurable a propósito; extensión natural si se pide unificarlo.
4. **Modales de recorrido duplicados** (mapa principal / caja negra) — candidatos a unificar en un widget parametrizable.
5. **`lib/core/firebase_options.dart`** es un archivo duplicado/huérfano sin uso — limpiar.
6. **Firma de release**: el build de `release` usa el keystore de **debug** (`signingConfigs.getByName("debug")`) — no apto para publicar en Google Play sin generar un keystore real primero.
7. **iOS no validado**: carpetas generadas pero sin ajustar `Info.plist` (ubicación en segundo plano, notificaciones, etc.).
8. **`AGENTS.md`** (en la raíz del repo) referencia archivos que no existen en el repo actual (`README.md`, `README_NOTIFICACIONES_DOZE.md`, `Etapa2.md`) y describe `main.dart` como "monolítico" — ya no es así, la lógica está repartida en `services/`/`screens/`/`providers/`. Convendría actualizarlo o apuntarlo a este informe.
9. **Categorías de miembros más allá de admin/miembro** (ver sección 2): no implementado, es una extensión de `AppUser` + reglas de Firestore si se pide.
10. **Toggle de background service observado pero no investigado a fondo:** en las pruebas de esta sesión se observó que `BackgroundLocationService` se arranca/detiene cada 1-2 minutos incluso con la app "en primer plano" según el usuario — probablemente por el apagado automático de pantalla disparando `paused`/`resumed` en ciclos, no por minimizar la app. No generó duplicados (el chequeo contra la última posición grabada sigue siendo consistente entre ambos caminos), pero si se quiere optimizar batería/CPU, vale la pena confirmar la causa exacta con más tiempo de prueba.

---

## 18. Checklist operativo para reconstruir la app desde cero

Si se le da este documento a una IA (u otro desarrollador) sin acceso al código fuente, el orden recomendado es:

1. Crear el proyecto Flutter (`flutter create`), target Android únicamente por ahora.
2. Crear el proyecto de Firebase y seguir la sección 5 completa (Auth, Firestore, Storage, Messaging, `flutterfire configure`).
3. Instalar JDK 17 y configurar `org.gradle.java.home` (sección 3.2) — sin esto no compila.
4. Copiar `firestore.rules` (sección 7) y `firestore.indexes.json` (sección 7.1) tal cual, y desplegarlos.
5. Implementar el modelo de datos (sección 6) como clases Dart (`app_models.dart`) con `fromMap`/`toMap`.
6. Implementar `AuthService` (login/registro con contraseña de 6 dígitos, sesión local, el fix de token fresco de la sección 13.2, y el manejo de `sessionId` para detectar sesión duplicada).
7. Implementar `FirestoreService` (grupos, solicitudes, ubicaciones, alertas, mensajes rápidos, geofence) según sección 6 y 12.
8. Implementar las pantallas en este orden de dependencia: `WelcomeScreen` → `AuthScreen` → `OnboardingScreen` → `HomeScreen` (la más grande, sección 8.4) → `ChatScreen` → `SettingsScreen`.
9. Implementar el GPS en dos pasos, **no juntos**: primero el tracking en primer plano (`location_service.dart`, sección 10.2) y verificarlo funcionando con la app abierta; **recién después** agregar `background_location_service.dart` (sección 10.3) para el segundo plano, con el handoff de `HomeScreen` (sección 10.4). Aplicar directamente los fixes de reentrancia y de umbral compartido (secciones 10.1/10.5) — no hace falta redescubrirlos.
10. Implementar notificaciones (sección 11) — payload solo-data desde el principio, para no tener que migrar después.
11. Desplegar la Cloud Function (sección 11.1).
12. Antes de dar por buena cualquier corrección de bug reportado como "no cambia nada": conseguir un dispositivo real por `adb` y usar `adb logcat` con logs temporales en vez de seguir iterando solo por lectura de código (sección 13.8) — ahorra rondas enteras de hipótesis equivocadas.

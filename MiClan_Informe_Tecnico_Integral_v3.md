# MiClan — Informe Técnico Integral (v3 — actualizado)

**Propósito de este documento:** servir de memoria completa del proyecto para retomar el desarrollo en una conversación nueva, o para que cualquier IA (u otro desarrollador) pueda reconstruir la app desde cero con el mismo criterio de diseño. Incluye stack, arquitectura, esquema de datos, reglas de seguridad, cada pantalla en detalle, cada servicio, y el historial de bugs encontrados y resueltos (para no repetirlos).

Se entrega junto con el código fuente completo (`MiClan_base_corregida_v2.zip`). Este informe reemplaza al informe v2 incorporando los cambios de esta iteración: el fix real del "permission-denied" tras el primer login (la v2 documentaba un intento de fix en 10.1 que no cubría la causa raíz completa) y la eliminación del botón "..." duplicado en el modo "Todos".

---

## 1. Resumen del producto

MiClan es una app Flutter para Android de **protección familiar por grupos**: un grupo de personas (una familia, por ejemplo) comparte su ubicación en tiempo real, puede mandarse alertas de pánico (S.O.S.), mensajes rápidos y chat grupal, y el administrador del grupo puede revisar el historial de movimientos de cada miembro ("caja negra").

Conceptos centrales del dominio:
- Cada usuario pertenece **a un solo grupo** a la vez.
- Cada grupo tiene un **código de unión de 6 caracteres**.
- Quien crea el grupo es automáticamente su **administrador**. No existe un campo de rol separado: la app compara `group.ownerId == currentUser.uid` en cada lugar donde hace falta saber si alguien es admin.
- Cualquier otro usuario que quiera sumarse debe **solicitar unión con el código** y esperar **aprobación manual** del administrador.

---

## 2. Stack tecnológico

- **Flutter** (Dart SDK `>=3.5.0 <4.0.0`), target Android (no se probó ni ajustó para iOS, aunque el proyecto trae las carpetas `ios/`, `macos/`, `linux/`, `windows/`, `web/` generadas por defecto).
- **Gestión de estado:** Riverpod (`flutter_riverpod: ^2.6.1`), con `StreamProvider` para todo lo que viene de Firestore/Auth en tiempo real.
- **Navegación:** `go_router: ^14.6.2`, con `refreshListenable` atado a un `ValueNotifier<AsyncValue<AppUser?>>` que reacciona al estado de auth.
- **Backend:** Firebase —
  - **Firebase Auth** (email + contraseña numérica de 6 dígitos).
  - **Cloud Firestore** (toda la data: usuarios, grupos, ubicaciones, alertas, chat, configuración).
  - **Firebase Cloud Messaging (FCM)** — payload **"solo data"**, sin campo `notification` (ver sección 9).
  - **Firebase Storage** — fotos y audios del chat.
  - **Cloud Functions** (Node.js 20, `firebase-functions` v5, `firebase-admin` v12) — un único trigger `onCreate` sobre `alerts/{alertId}` que arma el push y lo manda vía FCM HTTP v1.
- **Mapa:** OpenStreetMap vía `flutter_map: ^7.0.2` + `latlong2`. Tiles: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`.
- **GPS:** `geolocator: ^13.0.2`, con `AndroidSettings.foregroundNotificationConfig` para tracking en segundo plano.
- **Persistencia local:**
  - `sqflite` — caché local de ubicaciones ("caja negra" local + cola de sincronización offline).
  - Un archivo JSON plano (`user_session.json`, vía `path_provider`) — sesión local liviana, para detectar "sesión iniciada en otro dispositivo" y como respaldo de la ruta inicial.
  - `shared_preferences` — flags simples (ej. `battery_saver`).
- **Notificaciones locales:** `flutter_local_notifications: ^18.0.0`.
- **Multimedia:** `image_picker`, `record`, `audioplayers`.
- **Otros:** `permission_handler`, `android_intent_plus` (usado para abrir Ajustes de batería y para el enlace directo a WhatsApp), `share_plus`, `file_picker`, `intl`, `uuid`, `google_fonts`, `cached_network_image`.
- Dependencias presentes pero **no activamente usadas** en la lógica actual: `flutter_background_service` / `flutter_background_service_android` (el tracking real lo resuelve el foreground service propio de `geolocator`, no este plugin — se dejó declarado en el `AndroidManifest.xml` por si se decide usarlo a futuro, ver sección 12).

### 2.1 `pubspec.yaml` — dependencias exactas

```yaml
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
  "engines": { "node": "20" },
  "dependencies": {
    "axios": "^1.7.9",
    "firebase-admin": "^12.7.0",
    "firebase-functions": "^5.1.1"
  }
}
```

---

## 3. Estructura de carpetas del proyecto

```
lib/
  main.dart                       # bootstrap, tema, GoRouter, splash
  firebase_options.dart           # generado por flutterfire configure
  models/
    app_models.dart               # AppUser, AppGroup, PendingRequest, AppAlert,
                                   # GeofenceZone, QuickMessageItem, QuickMessagesConfig, UserSession
  providers/
    app_providers.dart            # todos los Provider/StreamProvider de Riverpod
  services/
    auth_service.dart             # Firebase Auth + sesión local
    firestore_service.dart        # toda la lógica de Firestore
    location_service.dart         # GPS: tracking, throttling, background
    notification_service.dart     # canales Android + notificaciones locales
    battery_optimization_service.dart
    database_helper.dart          # SQLite (caja negra local + cola offline)
    storage_service.dart          # subida de fotos/audios a Firebase Storage
    backup_service.dart           # exportación de backup local
    geofence_service.dart         # placeholder (ver sección 15, pendientes)
  screens/
    welcome_screen.dart           # splash con animación
    auth_screen.dart              # login / registro
    onboarding_screen.dart        # crear grupo / solicitar unión
    home_screen.dart              # mapa principal (pantalla más grande del proyecto)
    chat_screen.dart              # chat grupal
    settings_screen.dart          # configuración, admin, caja negra
  widgets/
    app_footer.dart               # pie de copyright reutilizable
android/
  app/src/main/AndroidManifest.xml
functions/
  index.js                        # Cloud Function sendAlertNotification
  package.json
firestore.rules
assets/
  images/app_logo.png, notification_icon.png
  sounds/aviso.wav, alerta.wav, ding_dong.wav
test/
  widget_test.dart
```

---

## 4. Configuración de Firebase (paso a paso, para recrear el proyecto)

1. Crear proyecto en Firebase Console.
2. Habilitar **Authentication → método Email/contraseña**.
   - **Importante:** la contraseña en esta app es siempre un **número de 6 dígitos** (se valida en el cliente, no hay una regla especial de Firebase para esto — Firebase acepta cualquier string ≥6 caracteres, la restricción a "6 dígitos numéricos" es una decisión de producto validada en `auth_service.dart` / `auth_screen.dart`).
3. Habilitar **Cloud Firestore** (modo producción, con las reglas de la sección 6).
4. Habilitar **Firebase Storage** (para fotos/audios del chat).
5. Habilitar **Cloud Messaging**.
6. Instalar FlutterFire CLI y correr `flutterfire configure` desde la raíz del proyecto → genera `lib/firebase_options.dart` y `android/app/google-services.json` (este último **no se versiona**, hay que generarlo por proyecto de Firebase).
7. Desplegar Cloud Functions:
   ```
   cd functions
   npm install
   firebase deploy --only functions
   ```
8. Desplegar reglas de Firestore:
   ```
   firebase deploy --only firestore:rules
   ```
9. En Android, agregar el plugin de Google Services en `android/build.gradle` / `android/app/build.gradle` (estándar de FlutterFire, no se detalla aquí porque es boilerplate generado por `flutterfire configure`).

### 4.1 Cloud Function — `sendAlertNotification`

Único trigger del backend. Escucha `onCreate` en la colección `alerts/{alertId}` y arma + envía el push.

**Decisión de diseño clave: el payload FCM es "solo data"**, sin el campo `notification`. Motivo: si se manda el campo `notification`, FCM lo muestra automáticamente en la barra de notificaciones del sistema **además** de cualquier notificación local que la app dispare al recibir el mensaje — eso generaba **notificaciones duplicadas**. Al mandar solo `data`, el sistema operativo no muestra nada por su cuenta; es la app (en foreground, background o completamente cerrada vía el *background handler*) la única responsable de decidir cómo mostrar la notificación.

Lógica completa:
1. Lee el documento de la alerta recién creada (`groupId`, `senderId`, `receiverId`, `type`, `payload`, `senderName`).
2. Busca en `users` todos los que tengan `groupId == alert.groupId`.
3. Filtra: excluye al propio emisor (`senderId`); si `receiverId != 'all'`, solo incluye a ese destinatario puntual.
4. Junta los `fcmToken` válidos (string, longitud > 20).
5. Obtiene un access token OAuth2 vía `admin.credential.applicationDefault().getAccessToken()` (necesario porque se usa la **API HTTP v1 de FCM**, no el SDK legacy).
6. Arma `title`/`body`/`channelId` según `type`:

| `type`             | title                        | body                              | channelId          |
|---------------------|-------------------------------|-------------------------------------|---------------------|
| `SOS`               | `S.O.S - MiClan`             | `ALERTA DE PÁNICO ACTIVADA!`       | `sos_channel`       |
| `photo`             | `MiClan - {senderName}`      | `Te envié una foto`                | `msg_channel`       |
| `audio`             | `MiClan - {senderName}`      | `Te envié un audio`                | `msg_channel`       |
| `command_message`   | `Comando - {senderName}`     | `payload` (texto libre)            | `msg_channel`       |
| `quick_message`     | *(cae en el `default`)*      | `payload`                          | `msg_channel`       |
| `geofence`          | `MiClan - Geofence`          | `payload`                          | `geofence_channel`  |
| `system`            | `MiClan`                     | `payload`                          | `msg_channel`       |
| *(default)*         | `MiClan - {senderName}`      | `payload`                          | `msg_channel`       |

7. Envía un mensaje FCM **individual por token** (`POST` a `https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`), con:
   ```json
   {
     "message": {
       "token": "...",
       "data": {
         "type": "...", "alertId": "...", "groupId": "...",
         "senderId": "...", "receiverId": "...",
         "title": "...", "body": "...", "channelId": "..."
       },
       "android": { "priority": "high", "ttl": "3600s", "directBootOk": true }
     }
   }
   ```
8. Si un envío falla con `UNREGISTERED` o `INVALID_ARGUMENT` (token vencido/inválido), borra ese `fcmToken` del usuario en Firestore (auto-limpieza).

---

## 5. Modelo de datos en Firestore

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
  ownerId: string (uid del admin — NO hay campo "role" separado)
  createdAt: Timestamp

  groups/{groupId}/pendingRequests/{uid}
    uid: string
    displayName: string
    requestedAt: Timestamp
    status: 'pending' | 'approved' | 'rejected'

  groups/{groupId}/geofence/main        # doc único, zona segura circular
    lat, lng, radiusMeters, name

  groups/{groupId}/config/quickMessages # mensajes rápidos configurables por el admin
    allButtons: [{title, message}, ×3]
    questionButtons: [{title, message}, ×3]
    answerButtons: [{title, message}, ×3]
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

alerts/{alertId}                   # dispara la Cloud Function
  groupId: string
  senderId: string
  receiverId: 'all' | uid
  type: 'SOS' | 'photo' | 'audio' | 'command_message' | 'quick_message' | 'geofence' | 'system'
  payload: string                  # texto del mensaje, o URL de storage para photo/audio
  senderName: string | null
  timestamp: Timestamp
  sosStatus: 'active' | 'cancelled' | null   # solo para type == 'SOS'
  cancelledBy: string | null
  cancelledAt: Timestamp | null
```

Esta colección `alerts` cumple doble función: es a la vez el **feed del chat grupal** (mensajes de texto/foto/audio) y el **canal de alertas** (SOS, mensajes rápidos, sistema). Todo pasa por el mismo trigger de Cloud Function.

---

## 6. Reglas de seguridad de Firestore (`firestore.rules`, texto completo y comentado)

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

**Puntos que costó ajustar (y por qué quedaron así) — importante para no "corregirlos" mal en el futuro:**

- **`users` lectura abierta a cualquier autenticado**, no solo al propio uid. Es intencional: la lista de miembros del grupo (`getGroupMembersStream`, que arma el mapa principal, el chat, los chips de miembros) necesita leer los `displayName`/ubicación de otros usuarios. Restringir la lectura al propio uid rompe esa funcionalidad completa.
- **`users` actualización con 3 condiciones OR**: propio usuario, admin del grupo **actual** del documento (`resource.data.groupId`, para poder expulsar), o admin del grupo **destino** (`request.resource.data.groupId`, para poder aprobar una solicitud de unión, que es un `update` que le asigna un `groupId` nuevo al usuario). Si falta cualquiera de las tres, se rompe expulsar o aprobar.
- **`groups/{groupId}/config/quickMessages`**: se agregó en una iteración posterior a la primera versión del informe (ver sección 15). Lectura para cualquier miembro del grupo (necesitan ver los mensajes configurados), escritura solo para el admin.
- **`locations/{uid}/history`**: la lectura hace un `get()` extra sobre `locations/{uid}` para comparar `groupId`, en vez de comparar contra `resource.data.groupId` directamente, porque cada documento del historial también guarda su propio `groupId`, pero la regla original se escribió así para que sea robusta ante el caso de leer la **colección completa** (una query, no un doc puntual) — en reglas de Firestore, cuando se lee una lista, `resource` no está disponible de la misma manera doc por doc en todos los SDKs/reglas legacy, así que se prefirió anclar la validación al documento padre (`locations/{uid}`) que sí es una lectura de documento único y previsible.

---

## 7. Pantallas (detalle completo)

### 7.1 `WelcomeScreen` (splash)

Se muestra mientras `main.dart` resuelve el estado de sesión/permisos al arrancar la app (reemplaza lo que antes era un loader genérico con `CircularProgressIndicator`).

- Logo (`assets/images/app_logo.png`) con efecto de **"explosión"**: una onda expansiva (círculo con `RadialGradient` que crece y se desvanece) detrás del logo, y el logo mismo apareciendo con `Curves.elasticOut` (rebote pronunciado) desde escala 0.
- Debajo: **"MiClan V.2.0"** (grande, bold, 30px).
- Debajo de eso: **"Monitoreo Grupal Activo"** (subtítulo, 14px, blanco semitransparente).
- Pie: `AppCopyrightFooter` ("Clever Sistemas - Lago Puelo - 2026", centrado, chico).
- Duración: animación de 2.8s + `main.dart` fuerza una duración mínima total de **3 segundos** (`Future.delayed`) antes de dejar pasar a la ruta real, independientemente de cuán rápido resuelva el auth — así el efecto siempre se aprecia completo, incluso con sesión ya cacheada.

### 7.2 `AuthScreen` (login / registro)

- Toggle entre modo login y modo registro (`_isLogin` bool).
- **Login:** email + contraseña (6 dígitos numéricos).
- **Registro:** nombre (máx. 10 caracteres), email, contraseña de 6 dígitos numéricos (validado con `int.tryParse` + longitud exacta 6). Al registrarse, la cuenta se crea y **se hace sign-out inmediato**, mostrando "Cuenta creada. Ahora iniciá sesión con tu email y contraseña." — el flujo obliga a loguearse explícitamente después de registrarse, no queda logueado automáticamente.
- Texto inferior: `¿No tenés cuenta? Registrate` / `¿Ya tenés cuenta? Entrá` (toggle).
- Pie de copyright agregado al final de la pantalla.
- **Fix crítico de `AuthService.signUp`/`signIn`** (ver sección 10.1): después de crear o iniciar sesión, se fuerza `getIdToken(true)` + una espera de 300ms antes de cualquier escritura a Firestore, para evitar carreras de propagación del token que causaban errores de permisos en instalaciones nuevas del teléfono.

### 7.3 `OnboardingScreen` (crear grupo / solicitar unión)

Se muestra cuando el usuario está logueado pero `user.groupId == null`.

- Dos caminos, separados por un divisor "— o —":
  - **Crear Grupo**: pide nombre del grupo (ej: "Familia Perez"), genera un `joinCode` de 6 caracteres, crea el doc en `groups` con `ownerId = uid` (esto es lo único que lo vuelve "admin"), y actualiza `users/{uid}.groupId`.
  - **Solicitar unirme**: input de "Código de 6 caracteres", crea un doc en `groups/{groupId}/pendingRequests/{uid}` con `status: 'pending'`, y muestra pantalla de espera: "Esperando aprobación del administrador... Te notificaremos cuando seas aceptado." (esta pantalla queda escuchando el estado en tiempo real — apenas el admin aprueba, `user.groupId` deja de ser null y el `redirect` de GoRouter empuja automáticamente a `/home`, sin que el usuario tenga que hacer nada).

### 7.4 `HomeScreen` (mapa principal — la pantalla más compleja)

Estructura general (todo dentro de un `Stack`):

1. **Mapa** (`flutter_map`) ocupando la mayor parte de la pantalla, con un marcador por cada miembro del grupo (posición en tiempo real vía `locations/{uid}` stream), coloreado/etiquetado con su nombre.
2. **Banners de advertencia** (apilados, cada uno de 56px, se van corriendo hacia abajo según cuántos estén activos):
   - Optimización de batería activa → toca para pedir exclusión.
   - Falta el permiso de ubicación "todo el tiempo" (background) → toca para habilitarlo.
   - Ambos banners se revisan automáticamente **cada vez que la app vuelve a primer plano** (`WidgetsBindingObserver.didChangeAppLifecycleState`), no solo al abrir la pantalla — así, si el usuario va a Ajustes del sistema y vuelve, el banner desaparece solo.
3. **Botón S.O.S.** grande, debajo de los banners. Al tocarlo, crea un doc en `alerts` con `type: 'SOS'`, `receiverId: 'all'`, prioridad alta; la Cloud Function le pega la vibración/pantalla-encendida a todo el grupo (ver sección 9). Si ya hay un SOS activo del propio usuario, el botón permite cancelarlo (`sosStatus: 'cancelled'`).
4. **Chips de miembros** (fila horizontal scrolleable): un chip por cada **otro** miembro del grupo (el usuario propio queda **excluido**, tanto acá como en el combo de destinatario — no tiene sentido enviarse mensajes a uno mismo). Tocar un chip centra el mapa en ese miembro y lo selecciona como destinatario.
5. **Combo de destinatario** ("Todos" o un miembro puntual).
6. **Área de mensajes rápidos** (bento inferior), con **dos modos según el destinatario**:
   - **Modo "Todos"**: 4 botones — 3 mensajes preestablecidos (`QuickMessagesConfig.allButtons`) + 1 botón `(...)` para mensaje manual.
   - **Modo "un miembro"**: 6 botones en grilla 2×3 — 3 "preguntas" arriba (`questionButtons`) + 3 "respuestas" abajo (`answerButtons`).
   - **Bento lateral fijo** (siempre visible, a la derecha, independiente del modo): botón `(...)` arriba (mensaje manual) y botón `WP` abajo (abre WhatsApp con un mensaje prellenado al teléfono cargado del miembro seleccionado, vía `android_intent_plus` con un link `https://wa.me/{telefono}?text=...`; si no hay miembro seleccionado o no tiene teléfono cargado, muestra un aviso).
   - Los textos de los 9 botones configurables (3+3+3) se leen de `groups/{groupId}/config/quickMessages` vía `groupQuickMessagesProvider` (StreamProvider, se refresca solo si el admin cambia la configuración estando la app abierta).
   - Todos los botones tienen el **texto en blanco** con buen contraste sobre el fondo semitransparente de color (ajuste hecho tras feedback de legibilidad).
7. **Botón flotante "Mi ubicación"** (`Icons.my_location`), centra el mapa en la posición propia.
8. **Modal de recorrido** (`_RouteMapModal`), se abre al tocar el ícono de ruta de un miembro:
   - Mapa que hace **fit-to-bounds automático** (usa `MapController.fitCamera(CameraFit.bounds(...))`) para mostrar el recorrido completo, en vez de un zoom fijo.
   - Cada punto grabado tiene un **marcador tocable** (zona táctil de 32×32, punto visible de 10×10 — para que sea fácil "embocarle" con el dedo) que, al tocarlo, muestra un **cartel con fecha/hora exacta dentro del propio bento del mapa** (no un `SnackBar`, que quedaba tapado detrás del modal).
   - Si hay más de 40 puntos en el rango elegido, se muestrean (máx. ~40 marcadores) para no saturar el mapa — la polilínea del recorrido sí usa todos los puntos, solo el muestreo aplica a los marcadores tocables.
   - **Selector de rango de fechas**: dos campos tocables "Desde"/"Hasta" que abren el selector nativo de fecha+hora de Android (`showDatePicker` + `showTimePicker`), más 4 chips de acceso rápido (24h / 2 días / 7 días / 30 días). *(Nota: la primera versión de este selector usaba dos `Slider`, mostraron ser poco precisos para elegir fecha/hora en pantallas chicas y se reemplazaron por este esquema.)*
   - La ventana está desplazada ~20mm hacia arriba (margen inferior extra) respecto del borde de la pantalla, para que no quede pegada al borde.
9. **Menú de administración de miembros** (solo visible/accesible para el admin): lista de miembros con botón expulsar, y lista de solicitudes pendientes con aprobar/rechazar.
10. **Pie de copyright**, en el hueco libre entre el bento inferior y el borde de la pantalla (chico, 9px).

**Marcador de un miembro → bottom sheet de acciones rápidas** (`_onMarkerTap`): 5 botones fijos (no configurables, distinto del bento principal): "Llamame", "¿Llegaste?", "¿Todo bien?" (arriba) y "Volvé", "¿Dónde estás?" (abajo). *(Nota para el futuro: si se quiere que también sean configurables, hoy no leen de `QuickMessagesConfig`; quedó así deliberadamente para no mezclar el menú contextual del marcador con el bento principal, pero es una extensión natural si se pide.)*

### 7.5 `ChatScreen`

Chat grupal simple sobre la colección `alerts` (comparte backend con las alertas — ver sección 5). Soporta:
- Mensajes de texto libres.
- Fotos (`image_picker` → sube a Firebase Storage vía `storage_service.dart` → guarda la URL como `payload`, `type: 'photo'`).
- Audios (`record` para grabar, `audioplayers` para reproducir; mismo flujo de subida a Storage, `type: 'audio'`).
- Burbujas alineadas según si el mensaje es propio o ajeno; muestra nombre del emisor.

### 7.6 `SettingsScreen`

Estructura en un `ListView` (con padding inferior extra para que el último ítem no quede tapado por los botones de navegación de Android — bug corregido, ver sección 10.3):

1. **Cuenta**: nombre, email (solo lectura), **teléfono editable** (para el enlace de WhatsApp — campo agregado en esta iteración, con su propio diálogo de edición).
2. **Zona Segura (geofence)**: definir un círculo (centro + radio) como zona segura del grupo; guardado en `groups/{groupId}/geofence/main`.
3. **Backup local**: exporta un backup de los datos locales (SQLite) vía `backup_service.dart` (usa `share_plus`/`file_picker` para compartir/guardar el archivo).
4. **Mensajes Rápidos** (solo admin): bento para cargar título+mensaje de cada uno de los 9 botones configurables (3 "Todos" + 3 preguntas + 3 respuestas). Al guardar, escribe en `groups/{groupId}/config/quickMessages`. Los miembros lo leen automáticamente vía stream mientras tengan la app abierta.
5. **Caja Negra del Grupo** (solo admin): selector de miembro + tabla "Fecha / Hora / Coordenada" (últimos registros) + botón para abrir el mismo modal de mapa con recorrido que en la pantalla principal (mismo componente reutilizado, con fit-to-bounds, marcadores tocables con fecha/hora, y selector de rango — ver sección 7.4, punto 8).
6. **Administración de miembros**: aprobar/rechazar solicitudes pendientes, expulsar miembros actuales.
7. **Cerrar sesión** (logout completo) — al final de la lista.
8. Pie de copyright, después del botón de cerrar sesión.

---

## 8. GPS: captura, throttling y almacenamiento (`location_service.dart`)

Este es el componente que más iteraciones de corrección tuvo. Comportamiento final:

- **Throttling por distancia**: no sube cada posición cruda del GPS, solo cuando el usuario se movió más de:
  - **50 metros** en modo normal.
  - **200 metros** en modo ahorro de batería (flag `battery_saver` en `SharedPreferences`, configurable desde Configuración).
- **Sincronización forzada cada 30 segundos** (`Timer.periodic`), independiente del throttling por distancia, para que el resto del grupo sepa que el usuario sigue activo aunque no se haya movido lo suficiente como para disparar una subida por distancia.
- **Si la ubicación es exactamente la misma** que la última grabada (distancia ≤ 3 metros, `_kSameLocationThresholdMeters`), **no se crea un punto nuevo en el historial** ("caja negra"). En su lugar, se manda un **"latido"** (`FirestoreService.touchLocation`) que solo actualiza el `timestamp`/`updatedAt` del documento de ubicación actual (sin escribir en la subcolección `history`), para que el mapa en vivo siga mostrando al usuario como "activo" sin llenar la caja negra de puntos duplicados con el usuario quieto.
- **Tracking en segundo plano (teléfono dormido)**:
  - Se usa el **foreground service nativo de `geolocator`** (`AndroidSettings.foregroundNotificationConfig`, con `enableWakeLock: true` y `setOngoing: true`), que muestra una notificación persistente ("GPS Activo") mientras trackea.
  - Además del permiso de ubicación "mientras se usa la app", la app **pide explícitamente el permiso "todo el tiempo"** (`LocationPermission.always`), imprescindible para que Android no corte el GPS al apagar la pantalla. En Android 11+ el sistema no ofrece ese permiso en el diálogo runtime normal; hay que ir a Ajustes de la app. La UI lo resuelve con un banner en `HomeScreen` que dirige a Ajustes, y **revisa el estado del permiso automáticamente cada vez que la app vuelve a primer plano** (fix reciente, antes solo se revisaba una vez al abrir la pantalla y el banner quedaba "pegado" hasta recargar la app entera).
- **Doble almacenamiento**: cada punto grabado se guarda tanto en Firestore (`locations/{uid}/history`, la "caja negra" navegable por el admin) como en SQLite local (`database_helper.dart`, respaldo local + cola de sincronización para cuando no hay red).
- **Cola offline**: si falla la subida a Firestore (sin red), el punto queda marcado como "no sincronizado" en SQLite; un timer periódico reintenta subir los pendientes (`_syncPendingLocations`).

### 8.1 Cómo verificar que el GPS graba bien en segundo plano (guía práctica)

1. Dejar el teléfono de un miembro **bloqueado** y en movimiento.
2. Desde el admin, abrir Configuración → Caja Negra del Grupo → seleccionar ese miembro.
3. Deberían aparecer filas nuevas en la tabla sin que el miembro haya abierto la app.

> Nota: Falta confirmar específicamente que el GPS se actualiza y graba en la caja negra mientras el dispositivo está en segundo plano o en modo pantalla apagada. Esta verificación es pendiente de prueba en dispositivo real.
4. Si el miembro se queda quieto, no deberían aparecer filas nuevas (por el fix de "misma ubicación no graba"), pero su posición en el mapa principal sigue vigente por el latido cada 30s.
5. Si en algún equipo puntual el GPS se corta igual estando dormido, casi siempre es el **gestor de batería agresivo del fabricante** (Xiaomi/MIUI, Huawei, Samsung en algunos modos) matando la app pese al permiso de Android estándar — eso requiere configuración específica de esa marca, no es algo resoluble solo con código Flutter/Android estándar.

---

## 9. Notificaciones push (FCM) — diseño completo

- **Payload "solo data"** (ver sección 4.1) — decisión de diseño no negociable, evita duplicados.
- **Canales de notificación Android** (`notification_service.dart`), cada uno con su importancia/sonido:
  - `sos_channel` — máxima prioridad, sonido de alerta (`alerta.wav`), vibración, y **enciende la pantalla del receptor** (uso de `USE_FULL_SCREEN_INTENT` + `turnScreenOn`/`showWhenLocked` en la Activity de Android).
  - `msg_channel` — mensajes normales (chat, mensajes rápidos, comandos), sonido `ding_dong.wav` o similar.
  - `geofence_channel` — avisos de entrada/salida de la zona segura.
- **Background handler** (`_firebaseMessagingBackgroundHandler` en `main.dart`, anotado `@pragma('vm:entry-point')`): se ejecuta cuando llega un push con la app cerrada o en background. Inicializa Firebase de nuevo (obligatorio en un isolate separado) y muestra la notificación local leyendo `title`/`body`/`channelId` desde `message.data` (nunca desde `message.notification`, que no existe en este payload).
- **Foreground handler** (dentro de `_initApp` en `main.dart`): mismo criterio, lee de `message.data`.
- **ID fijo para SOS** (`id: 9999` cuando `channelId == 'sos_channel'`): evita que se acumulen múltiples notificaciones de pánico en la barra si llegan varios pushes de la misma alerta.
- **Permiso de notificaciones (Android 13+, `POST_NOTIFICATIONS`)**: se pide **una única vez, en `main()`, antes de `runApp()`**, de forma secuencial y con timeout de 15s. Este orden es crítico — ver el bug documentado en la sección 10.2.

---

## 10. Historial de bugs encontrados y su solución (cronológico)

Esta sección es memoria de por qué el código está como está — **no deshacer estos fixes sin entender la causa original**.

### 10.1 Errores de permisos de Firestore justo después de crear/iniciar sesión

**Síntoma:** en una instalación nueva del teléfono, después de loguearse y aceptar el permiso de GPS, aparecía un error de "permission-denied" de Firestore.

**Causa:** en una instalación fresca, sin caché ni persistencia previa de Firestore, el token de ID recién emitido por `signInWithEmailAndPassword`/`createUserWithEmailAndPassword` puede tardar unos milisegundos en propagarse del lado del servidor. Si la app dispara escrituras a Firestore (guardar `sessionId`, guardar `fcmToken`, escribir la primera ubicación apenas se concede el permiso de GPS) antes de que esa propagación termine, las reglas de seguridad rechazan la escritura.

**Fix:** en `AuthService`, tanto en `signUp()` como en `signIn()`, se fuerza `await cred.user!.getIdToken(true)` + `await Future.delayed(Duration(milliseconds: 300))` antes de cualquier lectura/escritura a Firestore. (La versión original del código ya tenía este fix en `signUp()`; **faltaba replicarlo en `signIn()`**, que es el flujo que efectivamente dispara el bug para un miembro no-admin que ya existía y solo inicia sesión en un teléfono nuevo.)

### 10.2 App "colgada" al aceptar el permiso de notificaciones

**Síntoma:** después de instalar la app, se mostraba el diálogo de permiso de notificaciones; al aceptarlo, la app quedaba congelada en el loader.

**Causa:** es un problema conocido de Android/Flutter — si dos plugins distintos piden un permiso runtime casi al mismo tiempo (en este caso, `firebase_messaging` pidiendo `POST_NOTIFICATIONS` mientras `HomeScreen`, recién montada, pedía `ACCESS_FINE_LOCATION`), el diálogo del segundo permiso puede pisar el callback nativo del primero, dejando ese primer `Future` esperando una respuesta que nunca llega.

**Fix:** el permiso de notificaciones se pide **una sola vez, en `main()`, completamente antes de `runApp()`** (con timeout de seguridad de 15s), garantizando que cuando el usuario llega a `HomeScreen` no haya ningún otro diálogo de permiso en vuelo. `_saveFcmToken()` en `main.dart` ya no vuelve a pedir el permiso, solo obtiene/guarda el token.

### 10.3 "Flash" de la pantalla de login tras cerrar la app de un swipe

**Síntoma:** a veces, al reabrir la app después de matarla con un swipe, mostraba la pantalla de login por un instante (o pedía loguearse de nuevo) antes de entrar a Home.

**Causa:** la ruta inicial de `GoRouter` se calculaba solo a partir de un archivo de sesión local (JSON), que podía no estar actualizado/leído a tiempo tras un cierre abrupto.

**Fix:** `main.dart` ahora espera (con timeout de 6s) la **primera resolución real** del stream de Firebase Auth (`currentUserProvider.future`) antes de fijar la ruta inicial y construir el `GoRouter`. Si el timeout se cumple sin resolver, recién ahí cae al archivo de sesión local como respaldo (comportamiento anterior).

### 10.4 "Siempre pide login" para miembros no-admin (no solo la primera vez)

**Síntoma:** en vez de mantenerse logueado entre reinicios de la app (comportamiento esperado con la persistencia estándar de Firebase Auth), un miembro no-admin tenía que loguearse cada vez.

**Causa raíz identificada:** el mecanismo de "sesión iniciada en otro dispositivo" (compara `user.sessionId` de Firestore contra un `sessionId` guardado en un archivo local) usaba una variable de sesión **capturada una sola vez al arrancar `_initApp()`**. Si el login efectivamente sucedía *durante* esa misma corrida de la app (típico en una instalación nueva), esa variable quedaba desactualizada (`null` o vieja) y, en el siguiente arranque, la comparación contra el `sessionId` real de Firestore podía disparar un falso positivo de "sesión en otro dispositivo", forzando un `signOut()` automático.

**Fix:** el callback que hace esta comparación ahora **relee el archivo de sesión local en el momento mismo de comparar** (`await authServiceProvider.getLocalSession()` dentro del listener), no usa la variable capturada al inicio de `_initApp()`.

**Relación con 10.1:** ambos bugs comparten la misma raíz temporal (condiciones de carrera justo después de un login en una instalación nueva), por eso el fix de 10.1 (token fresco antes de escribir) también reduce la probabilidad de disparar esta cadena de eventos.

### 10.5 Banner de "permiso de ubicación todo el tiempo" no desaparecía sin recargar

**Síntoma:** después de conceder el permiso de ubicación en segundo plano desde Ajustes del sistema, el banner de aviso seguía apareciendo en `HomeScreen` hasta cerrar y reabrir la app.

**Causa:** el estado del permiso solo se revisaba una vez, al montar la pantalla (o justo antes de abrir Ajustes) — nunca al volver de Ajustes.

**Fix:** `HomeScreen` implementa `WidgetsBindingObserver` y revisa el permiso de ubicación en segundo plano (y el de optimización de batería) cada vez que `didChangeAppLifecycleState` reporta `AppLifecycleState.resumed`.

### 10.6.1 "Permission-denied" tras el primer login — causa raíz real (el fix de 10.1 no alcanzaba)

**Síntoma:** persistía en la práctica el mismo síntoma de 10.1 (instalación nueva del teléfono, login → permiso de GPS → error de Firestore), a pesar del fix de `AuthService.signIn()`/`signUp()` ya aplicado.

**Causa real:** el fix de 10.1 solo protege las escrituras que hace `signIn()`/`signUp()` **dentro de su propio cuerpo** (guardar `sessionId`). Pero `currentUserStream` (la base de `currentUserProvider`, y de ahí de *todos* los demás providers: `currentGroupProvider`, `groupMembersProvider`, `groupQuickMessagesProvider`, `activeSOSProvider`, además de `_saveFcmToken` en `main.dart` y el primer `updateLocation` en cuanto `HomeScreen` consigue el permiso de GPS) se arma directo sobre `_auth.authStateChanges()`, que emite el usuario nuevo de forma **independiente y casi al mismo tiempo** que el login termina — es decir, antes de que el delay interno de `signIn()` llegue a completarse. Todos esos listeners se suscribían a Firestore antes de que el token terminara de propagar, y quedaban con `permission-denied`.

Agravante: un `StreamProvider` de Riverpod que recibe un error en su stream **no se reintenta solo** — queda pegado en `AsyncValue.error` hasta que se recrea el provider. Por eso el síntoma exacto era "cerrar la app y volver a cargarla, pide login de nuevo y ahí anda bien": recién ahí se creaban listeners nuevos, ya con el token propagado.

**Fix:** se movió la espera de token fresco (mismo mecanismo ya usado en `signIn`/`signUp`: `getIdToken(true)` + delay) al único punto de origen real de todos esos listeners, dentro de `currentUserStream` (`auth_service.dart`), antes de suscribirse al doc de Firestore. Así ningún provider llega a tocar Firestore hasta que el token ya propagó, sin importar qué código dispare la escritura/lectura después.

**Red de seguridad agregada:** por si en una red muy lenta igual se supera el margen, `HomeScreen._errorScaffold` ahora tiene un botón "Reintentar" que invalida los providers en error (`currentUserProvider`, `currentGroupProvider`, `groupMembersProvider`) y los vuelve a suscribir sin necesitar cerrar la app.

**No quitar el fix de 10.1** (el de `signIn`/`signUp`): sigue siendo válido y redundante-inofensivo para ese caso puntual; el nuevo fix en `currentUserStream` es el que cierra la carrera de fondo para todo lo demás.

### 10.6.2 Botón "..." duplicado en el modo "Todos" del bento de mensajes rápidos

**Síntoma / pedido:** en el modo "Todos" del área de mensajes rápidos de `HomeScreen`, el 4to botón de la grilla era un "(...)" fijo de mensaje manual — igual, en función y ubicación relativa, al "(...)" del bento lateral fijo (siempre visible, arriba de "WP"). Redundante.

**Fix:** se sacó el "(...)" fijo del modo "Todos" y ese 4to lugar pasó a ser un botón rápido configurable más (igual que los otros 3), leído de `QuickMessagesConfig.allButtons[3]`. Cambios:
- `QuickMessagesConfig.allButtons` pasó de 3 a 4 ítems (`app_models.dart`); `fromMap`/`toMap` no necesitaron cambios porque ya iteran genéricamente sobre `defaultConfig.allButtons.length`.
- `HomeScreen._buildAllModeGrid`: el 4to slot ahora usa `_presetBtn(cfg.allButtons[3], Colors.red, user)` en vez de `_customMsgBtn(user)` (widget eliminado, sin más usos).
- `SettingsScreen` → diálogo "Mensajes Rápidos": `_itemFields('all', 3)` → `_itemFields('all', 4)` (el resto del diálogo ya era genérico en base a la cantidad de ítems, no hizo falta tocar más).
- El "(...)" de mensaje manual sigue existiendo, **solo en el bento lateral fijo** (`_showCustomMessageDialog`, sin cambios).

**Documentos existentes en Firestore:** si un grupo ya tenía `groups/{groupId}/config/quickMessages` guardado con solo 3 `allButtons`, `QuickMessagesConfig.fromMap` rellena el 4to con el default (`'Emergencia' / 'Necesito ayuda, comunicate conmigo'`) hasta que el admin lo edite y guarde desde Configuración — no hace falta migración manual.

### 10.6 Otros ajustes menores de UX corregidos

- **Ortografía**: pasada completa de tildes faltantes en toda la app (sesión, contraseña, ubicación, batería, número, pánico, código, últimos/días, etc.), incluida la Cloud Function (`ALERTA DE PÁNICO ACTIVADA!`, `Te envié una foto/audio`).
- **Contraste de texto** en los botones de mensajes rápidos: texto blanco con más peso, fondo con más opacidad, tras reporte de que se leía mal.
- **Padding inferior de "Cerrar sesión"** en Configuración: se agregó `MediaQuery.of(context).padding.bottom` + margen extra al final del `ListView`, porque el ítem quedaba tapado por los botones de navegación de Android en algunos equipos.
- **Área táctil de los puntos del recorrido**: se agrandó de 14×14 a una zona tocable de 32×32 (manteniendo el punto visual en 10×10), porque era muy difícil "embocarle" con el dedo.
- **Cartel de fecha/hora del punto tocado**: se movía de un `SnackBar` (quedaba tapado detrás del modal del mapa) a un cartel fijo dentro del propio bento del mapa.
- **Selector de rango de fechas en la ventana de recorrido**: de dos `Slider` (poco precisos en pantallas chicas) a dos campos que abren el selector nativo de fecha+hora de Android, más chips de rango rápido (24h/2d/7d/30d).

---

## 11. Administración de miembros — flujo completo

1. El admin (quien creó el grupo, `ownerId == uid`) ve en Configuración (o desde el mapa principal) la lista de **solicitudes pendientes** (`groups/{groupId}/pendingRequests` con `status: 'pending'`).
2. **Aprobar** (`FirestoreService.approveRequest`): actualiza `users/{uid}.groupId = groupId` y marca la solicitud como `status: 'approved'`. El miembro, si tiene la app abierta esperando en `OnboardingScreen`, es redirigido automáticamente a Home en cuanto el stream de su propio usuario refleja el nuevo `groupId` (no necesita reabrir la app).
3. **Rechazar** (`FirestoreService.rejectRequest`): marca la solicitud como `status: 'rejected'`, no toca `users/{uid}`.
4. **Expulsar** (`FirestoreService.removeMember`): borra `users/{uid}.groupId` (vía `FieldValue.delete()`) y crea un mensaje de sistema en `alerts` (`type: 'system'`, `senderId: 'system'`) avisando al resto del grupo quién fue expulsado y por quién.
5. **Abandonar el grupo** (`FirestoreService.leaveGroup`): si quien se va es el admin (`isOwner == true`), se borra el grupo entero vía `_deleteGroup`, que hace, en orden: borra todos los `pendingRequests`, borra `geofence/main`, borra en lotes de 500 todos los `alerts` de ese `groupId`, borra el doc `locations/{uid}` (posición actual) de cada miembro, y finalmente borra el doc `groups/{groupId}`. Si no es el admin, solo se limpia su propio `groupId` en `users/{uid}`.

   **Limitación conocida (no implementada todavía):** `_deleteGroup` **no borra** la subcolección `groups/{groupId}/config` (mensajes rápidos configurados) ni las subcolecciones `locations/{uid}/history` (caja negra) de los miembros — Firestore no borra subcolecciones en cascada automáticamente, y el código actual no las recorre para esos dos casos. Quedan documentos huérfanos en la base tras eliminar un grupo. Es un pendiente real a resolver, no solo una nota teórica — si se vuelve a tocar `_deleteGroup`, agregar el borrado explícito de esas dos subcolecciones (mismo patrón de borrado en lotes que ya se usa para `alerts`).

---

## 12. Notas de configuración nativa (Android)

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

Notas importantes dejadas como comentarios en el propio manifest (no perderlas si se regenera el archivo):
- **No declarar un `<service>` propio para FCM**: el plugin `firebase_messaging` ya registra su propio `FirebaseMessagingService` en su manifest interno, que se fusiona automáticamente al compilar. Declararlo de nuevo produce conflicto de merge y notificaciones duplicadas.
- El `<service>` de `flutter_background_service` está declarado (`foregroundServiceType="location"`) **por si a futuro se decide usar ese plugin**, pero el tracking real actual lo maneja el foreground service propio de `geolocator` (ver sección 8) — hoy esa dependencia está en el `pubspec.yaml` pero no se usa activamente en la lógica de `location_service.dart`.
- La actividad principal usa `turnScreenOn="true"` y `showWhenLocked="true"` — necesario para que la alerta S.O.S. **encienda la pantalla del receptor** aunque el teléfono esté bloqueado.
- Canal de notificación por defecto declarado vía meta-data (`msg_channel`), aunque los canales reales se crean en tiempo de ejecución desde `notification_service.dart`.

---

## 13. Assets

```
assets/images/app_logo.png          # logo de la app (usado en splash)
assets/images/notification_icon.png # ícono para notificaciones Android
assets/sounds/aviso.wav
assets/sounds/alerta.wav            # sonido de SOS
assets/sounds/ding_dong.wav         # sonido de mensaje
```

---

## 14. Convenciones de código y estilo visual

- Paleta oscura (`AppColors` en `main.dart`): fondo `#273758`, modales `#3A4A66`, tarjetas de vidrio semitransparentes (`cardGlass`, `borderGlass`), acentos azul/verde/rojo/ámbar.
- Tipografía: `google_fonts` (Inter).
- Estilo "glassmorphism" liviano en tarjetas/tiles de Configuración (`_glassTile`, `_editableGlassTile`).
- Todos los textos de la interfaz están en **español rioplatense con voseo** ("tenés", "entrá", "¿todo bien?"), con tildes correctas (repasado explícitamente, ver sección 10.6).
- Los modales de mapa (`_RouteMapModal`, `_BlackBoxRouteMapModal`) son prácticamente idénticos entre `home_screen.dart` y `settings_screen.dart` — están duplicados a propósito (uno usa acento azul, el otro ámbar, y cambia el rango por defecto: 24h vs 7 días) en vez de extraerlos a un widget compartido. Si se retoma el desarrollo, **unificarlos en un solo widget parametrizable** es una refactorización pendiente razonable.

---

## 15. Pendientes / posibles mejoras futuras (no implementadas)

- **Sin confirmar en dispositivo real (avisado por el usuario, 2026-08-09):** falta confirmar si el GPS efectivamente se actualiza y graba en la caja negra mientras el teléfono está dormido o en segundo plano. El mecanismo ya está descripto en la sección 8 (foreground service de `geolocator` + permiso "todo el tiempo") y la guía de verificación está en 8.1 — falta la prueba real en equipo. Si al retomar se confirma que falla en algún equipo puntual, revisar primero si es el gestor de batería agresivo del fabricante (ver 8.1, punto 5) antes de tocar código.
- **`_deleteGroup` deja huérfanas** las subcolecciones `config` (mensajes rápidos) y `locations/{uid}/history` (caja negra) al borrar un grupo — ver detalle en la sección 11, punto 5. Es el pendiente más concreto y fácil de priorizar si se retoma el desarrollo.
- `geofence_service.dart` es hoy un **placeholder mínimo** (17 líneas) — la detección de entrada/salida de la zona segura y el disparo de notificaciones tipo `geofence` no está conectada de punta a punta; el modelo de datos y el canal de notificación (`geofence_channel`) ya existen, falta la lógica que compare la posición actual contra `GeofenceZone` y dispare la alerta.
- El menú contextual del marcador (`_onMarkerTap`, 5 botones fijos) no lee de `QuickMessagesConfig` — quedó independiente del bento configurable a propósito, pero es una extensión natural si se pide unificarlo.
- Los dos modales de recorrido (mapa principal / caja negra) están duplicados — candidatos a unificar.
- `flutter_background_service`/`flutter_background_service_android` están en `pubspec.yaml` y declarados en el manifest pero sin uso real en la lógica — decidir si se elimina la dependencia o se aprovecha.
- No se validó el build en iOS (el proyecto tiene las carpetas generadas pero no se ajustaron permisos de `Info.plist` para ubicación en segundo plano, notificaciones, etc.).
- Backup local (`backup_service.dart`) exporta datos locales pero no se implementó una función de **restauración** de ese backup.

---

## 16. Checklist para retomar el desarrollo en una conversación nueva

Al abrir la conversación nueva, conviene entregar:
1. Este informe (`MiClan_Informe_Tecnico_Integral_v2.md`).
2. El zip del código fuente actualizado (`MiClan_base_corregida.zip`).
3. Mencionar explícitamente si hay algo pendiente de probar en dispositivo real (ej. "estoy probando el fix de background location, avisame si sigue fallando en tal equipo").

Con eso, cualquier IA (incluida una instancia nueva de este mismo asistente) tiene: el estado exacto del código, el razonamiento detrás de cada decisión de diseño no obvia, y la lista de bugs ya resueltos para no reintroducirlos.

# INFORME COMPLETO - PROYECTO MICLAN
## Para continuar en nuevo chat

---

## 📋 CONTEXTO DEL PROYECTO

**MiClan** es un sistema de protección familiar jerárquica desarrollado en Flutter para Android. La app permite:
- Crear grupos familiares con un rol "Central" (supervisor) y "Miembros"
- Rastreo GPS en tiempo real con persistencia offline (Caja Negra SQLite)
- Comunicación bidireccional con mensajes rápidos y alertas S.O.S
- Notificaciones push (FCM) que despiertan el dispositivo
- Mapas tácticos con OpenStreetMap (sin costos de API)

---

## 🏗️ ARQUITECTURA IMPLEMENTADA

### Decisiones Arquitectónicas Validadas:
1. **Grupos con código de 6 dígitos** (análogo a clave de producto Windows)
2. **Interruptor de rol** (Central ↔ Miembro sin cerrar sesión)
3. **Mapas OpenStreetMap** (gratis, sin API key)
4. **Mensajería híbrida FCM + Firestore** (notificaciones instantáneas + histórico)
5. **Persistencia offline con SQLite** (Caja Negra)
6. **Foreground Service nativo en Kotlin** (cumple Android 14/15/16)
7. **Sincronización cada 1 min o cambio >50m** (balance batería/precisión)

### Estructura NoSQL en Firestore:
```
users/{uid}/
  - email: string
  - role: "central" | "miembro"
  - currentRole: "central" | "miembro"
  - groupId: string | null
  - fcmToken: string
  - createdAt: timestamp

groups/{groupId}/
  - name: string
  - joinCode: string (6 caracteres)
  - ownerId: uid
  - createdAt: timestamp

locations/{uid}/
  - groupId: string
  - lat: number
  - lng: number
  - timestamp: timestamp
  - updatedAt: string (ISO 8601)

alerts/{alertId}/
  - groupId: string
  - senderId: uid
  - receiverId: uid | "all"
  - type: "SOS" | "quick_message" | "command_message"
  - payload: string
  - timestamp: timestamp
  - notified: boolean
```

---

## 📁 ESTRUCTURA DE ARCHIVOS ACTUAL

```
D:\scr\miclan\
├── lib/
│   ├── main.dart (2500+ líneas, archivo único con toda la lógica)
│   └── firebase_options.dart (auto-generado por flutterfire)
├── android/
│   └── app/
│       ├── build.gradle.kts
│       ├── proguard-rules.pro
│       └── src/main/
│           ├── AndroidManifest.xml
│           └── kotlin/com/agiletask/miclan/
│               ├── MainActivity.kt
│               ├── LocationForegroundService.kt
│               └── MiClanFirebaseMessagingService.kt
├── functions/
│   ├── package.json
│   └── index.js (Cloud Function para FCM)
├── firestore.rules
├── firestore.indexes.json
├── firebase.json
└── pubspec.yaml
```

---

## 🔧 DEPENDENCIAS ACTUALES (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^2.6.1
  go_router: ^14.6.2
  firebase_core: ^3.8.1
  firebase_auth: ^5.3.4
  cloud_firestore: ^5.6.0
  firebase_messaging: ^15.1.6
  google_fonts: ^6.2.1
  intl: ^0.19.0
  uuid: ^4.5.1
  flutter_map: ^7.0.2
  latlong2: ^0.9.1
  geolocator: ^13.0.2
  permission_handler: ^11.3.1
  sqflite: ^2.3.3
  flutter_background_service: ^5.1.0
  flutter_background_service_android: ^6.2.2
  android_intent_plus: ^5.2.1
```

---

## 🔐 REGLAS DE FIRESTORE ACTUALES

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    match /users/{uid} {
      allow create: if request.auth != null && request.auth.uid == uid;
      allow read, update: if request.auth != null && request.auth.uid == uid;
      allow delete: if false;
    }

    match /groups/{groupId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.resource.data.ownerId == request.auth.uid;
      allow update, delete: if request.auth != null && resource.data.ownerId == request.auth.uid;
    }

    match /locations/{uid} {
      allow write: if request.auth != null && request.auth.uid == uid;
      allow read: if request.auth != null && 
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == resource.data.groupId;
    }

    match /alerts/{alertId} {
      allow create: if request.auth != null && 
                     request.resource.data.senderId == request.auth.uid &&
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == request.resource.data.groupId &&
                     (request.resource.data.receiverId == 'all' || 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == 
                      get(/databases/$(database)/documents/users/$(request.resource.data.receiverId)).data.groupId);
      allow read: if request.auth != null && 
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.groupId == resource.data.groupId;
    }
  }
}
```

---

## ⚙️ CLOUD FUNCTION ACTUAL (functions/index.js)

```javascript
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.onAlertCreated = functions.firestore
  .document("alerts/{alertId}")
  .onCreate(async (snap, context) => {
    const alertData = snap.data();
    const groupId = alertData.groupId;
    const senderId = alertData.senderId;
    const receiverId = alertData.receiverId;
    const type = alertData.type;
    
    try {
      const membersSnapshot = await admin.firestore()
        .collection("users")
        .where("groupId", "==", groupId)
        .get();

      const tokens = [];
      for (const doc of membersSnapshot.docs) {
        const userData = doc.data();
        if (doc.id !== senderId && userData.fcmToken) {
          if (receiverId === 'all' || receiverId === doc.id) {
            tokens.push(userData.fcmToken);
          }
        }
      }

      if (tokens.length === 0) {
        console.log("No hay tokens FCM para enviar");
        return null;
      }

      let title, body;
      switch (type) {
        case 'SOS':
          title = "🚨 ALERTA S.O.S";
          body = "¡Un miembro ha activado el botón de pánico!";
          break;
        case 'quick_message':
          title = "💬 Mensaje Rápido";
          body = alertData.payload || "Tienes un nuevo mensaje";
          break;
        case 'command_message':
          title = "📨 Mensaje de la Central";
          body = alertData.payload || "La Central te envía un mensaje";
          break;
        default:
          title = "Notificación MiClan";
          body = "Tienes una nueva notificación";
      }

      const message = {
        tokens: tokens,
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: type,
          alertId: context.params.alertId,
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channel_id: "miclan_critical_channel",
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`FCM enviado a ${response.successCount} dispositivos`);
      
      await snap.ref.update({ notified: true, notifiedAt: admin.firestore.FieldValue.serverTimestamp() });

      return null;
    } catch (error) {
      console.error("Error al enviar FCM:", error);
      return null;
    }
  });
```

---

## ✅ FUNCIONALIDADES IMPLEMENTADAS

### Autenticación y Grupos:
- ✅ Login/Registro con Firebase Auth
- ✅ Reparación automática de usuarios fantasma
- ✅ Creación de grupos con código de 6 dígitos
- ✅ Unión a grupos existentes con código
- ✅ Persistencia del grupo (no pide código al re-login)
- ✅ Cambio de grupo desde Configuración
- ✅ Interruptor de rol (Central ↔ Miembro)

### UI/UX:
- ✅ Pantalla de Onboarding (crear/unirse a grupo)
- ✅ Pantalla de Configuración (ver código, cambiar grupo)
- ✅ Nombre del grupo en AppBar
- ✅ Código de grupo visible para Central
- ✅ Botón "¿Dónde estoy?" (mapa con ubicación actual)
- ✅ Botón "¿Dónde está Central?" (mapa con ubicación de Central)
- ✅ Botonera de mensajes rápidos (Miembro): Llegué, Estoy bien, Estoy volviendo, Llámame
- ✅ Botones de mensajes por miembro (Central): Llámame, ¿Llegaste?, ¿Todo bien?, Volvé, ¿Dónde estás?
- ✅ Marker de Central en mapa (estrella amarilla)
- ✅ Marker de miembros en mapa con nombre (email sin @)

### Rastreo y Ubicación:
- ✅ Foreground Service GPS en Kotlin
- ✅ WakeLock para mantener CPU despierta
- ✅ Caja Negra SQLite (persistencia offline)
- ✅ Sincronización automática cada 15 min
- ✅ Subida de ubicación cada 1 min o cambio >50m
- ✅ Mapa táctico OpenStreetMap
- ✅ Mapa centrado en ubicación de Central
- ✅ Visualización de todos los miembros del grupo

### Comunicación:
- ✅ Botón S.O.S (Miembro → Central)
- ✅ Mensajes rápidos predefinidos
- ✅ Alertas en tiempo real (Central)
- ✅ Notificaciones push FCM
- ✅ Comunicación bidireccional (Central ↔ Miembro)
- ✅ Mensajes dirigidos a miembro específico

### Cumplimiento Android:
- ✅ Android 14/15/16 (foregroundServiceType="location")
- ✅ Mitigación OEM (botón para desactivar optimización de batería)
- ✅ @pragma('vm:entry-point') en funciones críticas
- ✅ Sin listeners permanentes en segundo plano

---

## 🐛 PROBLEMAS RESUELTOS DURANTE EL DESARROLLO

1. **Errores de compilación Gradle**:
   - Kotlin DSL vs Groovy (build.gradle.kts)
   - Dependencias duplicadas (workmanager, play-services)
   - Java 17 requirement (JDK de Android Studio)

2. **Errores de Dart/Flutter**:
   - Colisión de nombres (Context vs BuildContext)
   - MethodCall.argument() no existe (usar call.arguments como Map)
   - await sobre void (FlutterBackgroundService.invoke)
   - Duplicación de clases (archivo main.dart con código duplicado)

3. **Errores de Firebase**:
   - Usuarios fantasma (Auth existe, Firestore no)
   - Reglas de permisos (receiverId: 'all' no permitido)
   - FCM tokens no registrados
   - Cloud Functions no desplegadas

4. **Errores de UI/UX**:
   - Mapa centrado en Bs.As. en lugar de ubicación actual
   - Miembros no aparecen en lista
   - Marcadores sin nombre
   - Botón de batería no funciona (AndroidIntent sin try/catch)

---

## 🎯 ESTADO ACTUAL Y PRÓXIMOS PASOS

### Lo que está funcionando:
- ✅ Compilación exitosa (flutter build apk --release)
- ✅ Login/Registro y gestión de grupos
- ✅ Mapa con ubicación de Central y miembros
- ✅ Comunicación bidireccional con notificaciones
- ✅ Persistencia offline con Caja Negra

### Pendiente de implementar:
1. **Captura de fotos** (Central → Miembro)
2. **Notas de audio** (bidireccional)
3. **Historial de mensajes** (persistente en Firestore)
4. **Chat en tiempo real** (StreamBuilder con mensajes)
5. **Geofencing** (alertas al entrar/salir de zonas)
6. **Modo ahorro de batería** (reducir frecuencia de GPS)
7. **Exportar/importar datos** (backup de Caja Negra)

---

## 🚀 COMANDOS ÚTILES

```powershell
# Compilar APK release
cd D:\scr\miclan
flutter clean
flutter pub get
flutter build apk --release

# Desplegar reglas y funciones
firebase deploy --only "firestore:rules,functions"

# Ver logs de Cloud Functions
firebase functions:log

# Ejecutar en modo debug (para ver prints)
flutter run

# Limpiar caché de Gradle
cd android
./gradlew clean
cd ..

# Purgar caché de pub (si hay problemas de dependencias)
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\workmanager*" -ErrorAction SilentlyContinue
flutter pub get
```

---

## 📝 NOTAS IMPORTANTES PARA CONTINUAR

1. **El archivo main.dart es monolítico** (2500+ líneas). Para futuras fases, considerar dividir en múltiples archivos:
   - `auth_service.dart`
   - `group_service.dart`
   - `location_service.dart`
   - `database_helper.dart`
   - `screens/` (carpeta con pantallas separadas)

2. **Los mocks de slaveId/deviceId fueron reemplazados** por el sistema de grupos con groupId.

3. **La app usa un solo archivo main.dart** por simplicidad, pero esto dificulta el mantenimiento. En futuras iteraciones, refactorizar.

4. **El Cloud Function está desplegado** y escucha cambios en la colección `alerts` para enviar FCM.

5. **Las reglas de Firestore permiten receiverId = 'all'** para broadcast a todo el grupo.

6. **El Foreground Service nativo en Kotlin** está configurado con WakeLock y notificación persistente.

7. **La mitigación OEM** (bypass de optimización de batería) se implementa con AndroidIntent.

---

## 🔗 RECURSOS EXTERNOS

- **Firebase Console**: https://console.firebase.google.com/project/miclan-6dd12
- **Documentación Flutter**: https://docs.flutter.dev
- **Documentación Firebase**: https://firebase.google.com/docs
- **OpenStreetMap Tiles**: https://tile.openstreetmap.org
- **flutter_background_service**: https://pub.dev/packages/flutter_background_service
- **flutter_map**: https://pub.dev/packages/flutter_map

---

## 💬 INSTRUCCIONES PARA EL NUEVO CHAT

Cuando inicies el nuevo chat, pega este informe completo y agrega:

> "Continuamos el desarrollo de MiClan. Aquí está el informe completo del estado actual. Necesito que me pases el archivo main.dart completo con las últimas correcciones (marker de miembros con nombre, botón '¿Dónde está Central?', botones de mensajes por miembro). Después continuamos con [captura de fotos / notas de audio / historial de mensajes / etc.]"

---

**Fin del informe**
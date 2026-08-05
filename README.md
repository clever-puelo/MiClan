# MiClan - Fix Pack

Este paquete corrige los 4 problemas reportados:

1. **Logo en login** - Agrega assets en pubspec.yaml + logo generado
2. **Notificaciones push no llegan** - Cloud Function para enviar FCM + fix de guardado de token
3. **Telefono no despierta ante SOS** - Permisos WAKE_LOCK, USE_FULL_SCREEN_INTENT y atributos en AndroidManifest.xml
4. **Mensajes no llegan a otro miembro** - Mismo fix que punto 2 (Cloud Function)

---

## Instalacion

### Paso 1: Copiar archivos Flutter

Copia estos archivos a tu proyecto, reemplazando los existentes:

```
pubspec.yaml          -> raiz del proyecto/
lib/main.dart         -> lib/main.dart
android/app/src/main/AndroidManifest.xml  -> android/app/src/main/AndroidManifest.xml
assets/images/        -> assets/images/ (crear carpeta si no existe)
```

### Paso 2: Instalar dependencias

```bash
flutter clean
flutter pub get
```

### Paso 3: Deployar Cloud Function

La carpeta `functions/` va en la raiz de tu proyecto Firebase (no dentro de Flutter).

```bash
# Si no tenes Firebase CLI instalado:
npm install -g firebase-tools

# Login y seleccionar proyecto
firebase login
firebase use miclan-6dd12   # tu Project ID

# Ir a la carpeta functions y deployar
cd functions
npm install
firebase deploy --only functions
```

### Paso 4: Verificar Firebase

Asegurate de que en tu consola de Firebase:
- El Project ID sea `miclan-6dd12`
- El plan sea Blaze (pago por uso) para que las Cloud Functions funcionen
- Tengas el indice compuesto en `alerts` (groupId Ascending, timestamp Descending)

### Paso 5: Probar

1. **Logo**: Abri la app, deberia verse el logo "MC" en la pantalla de login.
2. **Push**: Logueate con 2 dispositivos distintos en el mismo grupo. Envia un mensaje rapido desde uno. El otro deberia recibir notificacion.
3. **SOS**: Apaga la pantalla del dispositivo receptor. Activa SOS desde el emisor. El receptor deberia encenderse y vibrar.

---

## Que cambio en cada archivo

### pubspec.yaml
- Agregada seccion `assets:` con `assets/images/`

### lib/main.dart
- `_saveFcmToken()` ahora guarda token cuando el usuario aparece en el stream
- `_firebaseBackgroundHandler` usa ID fijo 9999 para SOS (evita acumulacion)
- Agregados `debugPrint` para diagnosticar problemas de FCM

### AndroidManifest.xml
- Nuevos permisos: `WAKE_LOCK`, `USE_FULL_SCREEN_INTENT`, `VIBRATE`, `SYSTEM_ALERT_WINDOW`, `RECEIVE_BOOT_COMPLETED`
- Activity con `showOnLockScreen="true"`, `turnScreenOn="true"`, `showWhenLocked="true"`
- Service foreground con `foregroundServiceType="location"`

### functions/index.js
- Cloud Function `sendAlertNotification` escucha creacion de documentos en `alerts/`
- Obtiene tokens FCM de todos los miembros del grupo
- Envio multicast con prioridad HIGH
- Limpieza automatica de tokens invalidos
- SOS usa `fullScreenIntent: true` en Android

---

## Troubleshooting

### "No compila despues de copiar"
Ejecuta `flutter clean && flutter pub get`

### "La Cloud Function no se deploya"
Verifica que tu plan de Firebase sea Blaze (no Spark). Las Cloud Functions requieren Blaze.

### "Sigue sin llegar la notificacion"
1. Verifica en Firebase Console > Cloud Messaging que el token FCM del usuario este guardado en Firestore (`users/{uid}/fcmToken`)
2. Revisa los logs de la Cloud Function en Firebase Console > Functions > Logs
3. Asegurate que ambos dispositivos tengan internet y no esten en modo avion

### "El telefono no vibra con SOS"
1. Verifica que el permiso `VIBRATE` este en el manifest
2. En Android 12+, las notificaciones con `fullScreenIntent` requieren que el usuario haya aceptado permiso especial. Ve a Configuracion > Apps > MiClan > Notificaciones > Permitir pantalla completa.

================================================================================
                    MiClan - FIX NOTIFICACIONES EN DOZE MODE
                         Fecha: 2026-08-06
================================================================================

PROBLEMA
--------
Cuando el telefono duerme profundamente (Doze mode / App Standby), las
notificaciones FCM no llegan. Al despertar el telefono, llegan todas juntas.

CAUSA
-----
1. Cloud Function enviaba mensajes con priority: 'normal' (solo SOS usaba 'high').
   Android retrasa mensajes 'normal' en Doze hasta el proximo maintenance window.
2. El foreground service de GPS no basta: Android moderno + fabricantes (Xiaomi,
   Samsung, Oppo, Huawei) matan procesos en background si la app no esta excluida
   de optimizaciones de bateria.
3. Sin REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, el sistema puede suspender la
   conexion FCM y el wake lock del foreground service.

SOLUCION APLICADA (3 frentes)
-------------------------------

FRENTE 1 - CLOUD FUNCTION (functions/index.js)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
- TODOS los mensajes ahora usan android.priority: 'high' (antes solo SOS).
- Se agrego TTL de 3600s para evitar expiracion en cola.
- Se agrego directBootOk: true para entrega en boot directo.
- Se mantiene la limpieza automatica de tokens invalidos.

DEPLOY:
  cd functions
  npm install
  firebase deploy --only functions

FRENTE 2 - FOREGROUND SERVICE + BATTERY OPTIMIZATION (Flutter)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
- Nuevo servicio: lib/services/battery_optimization_service.dart
  Usa permission_handler para verificar/solicitar ignorar optimizaciones.
- HomeScreen ahora muestra un banner ambar si las optimizaciones estan activas.
  Al tocar, abre el dialogo nativo de Android para excluir MiClan.

FRENTE 3 - AndroidManifest.xml (VERIFICAR / AGREGAR)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Asegurate de que estos permisos y servicios esten presentes:

<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>  <-- CRITICO
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>

<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="location"
    android:exported="true"
    android:permission="android.permission.FOREGROUND_SERVICE_LOCATION" />

<service
    android:name="com.google.firebase.messaging.FirebaseMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>

<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="msg_channel" />

CONFIGURACION MANUAL DEL USUARIO (obligatoria en algunos fabricantes)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Aun con todo lo anterior, algunos fabricantes (Xiaomi MIUI, Samsung OneUI,
Oppo ColorOS, Vivo Funtouch, Huawei EMUI) aplican restricciones ADICIONALES
que matan apps en background. El usuario debe configurar manualmente:

1. Ajustes > Bateria > Optimizacion de bateria > MiClan > NO OPTIMIZAR
   (o "No restrictions" / "Sin restricciones")
2. Ajustes > Aplicaciones > MiClan > Permisos > Ubicacion > PERMITIR TODO EL TIEMPO
3. Ajustes > Aplicaciones > MiClan > Inicio automatico > ACTIVAR
   (solo en Xiaomi, Oppo, Vivo, Huawei)
4. Ajustes > Bateria > Ahorro de bateria > Apps sin restricciones > Agregar MiClan
   (solo Samsung)

El banner ambar en HomeScreen guia al usuario para el paso 1.

ARCHIVOS MODIFICADOS / NUEVOS
-------------------------------
lib/
  main.dart                                    (sin cambios respecto al fix anterior)
  services/
    notification_service.dart                  (sin cambios respecto al fix anterior)
    battery_optimization_service.dart            <-- NUEVO
  screens/
    home_screen.dart                             (agregado banner de bateria)
    chat_screen.dart                             (sin cambios respecto al fix anterior)
functions/
  index.js                                      <-- NUEVO (Cloud Function actualizada)

INSTRUCCIONES DE INSTALACION
-----------------------------
1. Reemplazar los archivos en tu proyecto Flutter.
2. Verificar/agregar los permisos en AndroidManifest.xml (ver arriba).
3. Hacer flutter clean && flutter pub get.
4. Re-compilar y re-instalar en el dispositivo.
5. Deploy de la Cloud Function:
     cd functions
     npm install
     firebase deploy --only functions
6. Abrir MiClan, tocar el banner ambar y aceptar "Ignorar optimizaciones de bateria".
7. En Xiaomi/Samsung/Oppo/etc., configurar manualmente los pasos adicionales.

TEST DE VERIFICACION
--------------------
1. Enviar un mensaje de chat con la app abierta -> debe llegar inmediato.
2. Cerrar la app (swipe away), enviar mensaje -> debe llegar como push nativo.
3. Dejar el telefono dormido 15-30 minutos, enviar mensaje -> debe llegar.
   Si no llega inmediato pero si al despertar, el problema persiste:
   - Verificar que el banner ambar NO este visible (optimizacion desactivada).
   - Verificar configuracion manual del fabricante.
   - Verificar que la Cloud Function deployada tenga priority: 'high'.

================================================================================

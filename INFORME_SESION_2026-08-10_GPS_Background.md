> **ACTUALIZACIÓN — misma noche, sesión siguiente: AMBOS BUGS RESUELTOS Y CONFIRMADOS EN DISPOSITIVO REAL.**
> Se consiguió acceso a `adb` + teléfono físico (Motorola moto g05). Se instrumentó el código con logs temporales (`debugPrint('MICLAN_DBG ...')`) en los puntos exactos que este informe señalaba como "sin evidencia real" (sección 0) y se capturó `adb logcat` en vivo mientras el usuario reproducía ambos síntomas. Causas raíz reales (ninguna de las hipótesis originales de la sección 4 era correcta):
> - **"Pide login otra vez"**: no era el botón Reintentar ni el refresh de token. Era una condición de carrera en el chequeo de "sesión iniciada en otro dispositivo" de `main.dart`: el primer snapshot de Firestore que recibe el listener justo después de loguearse puede traer todavía el `sessionId` VIEJO (el de la sesión anterior en ese mismo teléfono), porque el listener se suscribe antes de que el propio `update({'sessionId': ...})` de `signIn()` termine de propagarse de vuelta. El archivo de sesión local ya tenía el valor nuevo en ese instante → mismatch falso → `signOut()` automático ~600ms después de cada login. Confirmado en logcat: 3 snapshots seguidos (el 1ro con sessionId viejo) y el `signOut()` disparado contra ese primero. Fix: debounce de 1.5s antes de evaluar el mismatch, usando siempre el valor más reciente en ese momento (ver `_sessionMismatchDebounce` en `main.dart`).
> - **GPS duplicado**: no era ruido de GPS ni el bug de `SharedPreferences` cacheada (ese fix de la ronda anterior era real pero no la causa dominante). Causa real: reentrancia en `LocationService.startTracking()`. Android pausa/reanuda la Activity cuando aparece y se cierra el diálogo del permiso de ubicación, disparando `didChangeAppLifecycleState(resumed)` varias veces casi seguidas; cada una llamaba a `startTracking()`, y el guard existente (`_positionSub != null`) no alcanzaba a bloquear llamadas concurrentes que entraban antes de que `_positionSub` se asignara. Cada llamada grababa su propio punto inicial sin chequear contra el último grabado. Confirmado en logcat: 5 puntos idénticos grabados en <700ms. Fix: una única llamada "en vuelo" compartida (`_startFuture`) entre llamadas concurrentes, y el punto inicial ahora también respeta `isSameAsLastRecorded`.
>
> Verificado con dos ciclos de reinstalación limpia (`adb uninstall` + `adb install`) + logcat real: 0 eventos de `SIGNOUT` espurio y sin bursts de puntos duplicados en ~5-6 min de uso en primer plano. Los logs `MICLAN_DBG` fueron temporales y ya se removieron del código antes de comitear.
>
> Lección para la próxima vez que "un fix por lectura de código no cambia nada reportado": conseguir logcat real ni bien sea posible ahorra rondas enteras de hipótesis — ninguna de las 5 hipótesis de la sección 4 de este informe era la causa real.

# Informe de sesión — 2026-08-10 — GPS en segundo plano / login en Reintentar

Este documento es el punto de partida para continuar en una sesión nueva. Resume qué se pidió, qué se hizo, qué se verificó, y — lo más importante — **qué sigue sin resolverse y por qué sospecho que el problema real todavía no fue identificado.**

---

## 0. Lectura obligatoria antes de seguir debuggeando

**El usuario reportó "no cambia nada" después de varias rondas de fixes que, por código, son correctos y estaban bien verificados (`flutter analyze` limpio, builds exitosos, causas raíz confirmadas leyendo el código fuente de los plugins).**

Se había detectado que `build\app\outputs\flutter-apk\app-release.apk` no coincidía con `MiClan2.apk` (el nombre que el usuario usa para instalar), y se llegó a sospechar que se estaba probando un build viejo. **El usuario confirmó que esto NO es la causa**: renombra manualmente `app-release.apk` → `MiClan2.apk` y lo copia por FTP desde el explorador de Windows a cada prueba, controlando el timestamp del `.apk` para confirmar que es el último build. Es decir, **cada ronda de fixes SÍ se probó correctamente, y aun así los síntomas no cambiaron.** Esto descarta la hipótesis de "build viejo" — los bugs 3.3 y 3.4 de este informe siguen sin resolverse en la práctica pese a estar bien identificados por código, así que hay que asumir que **falta algo más** (ver sección 4, hipótesis reordenadas).

El usuario también planteó como hipótesis que la conversación se volvió muy larga y eso "entorpece el proceso" — por eso pidió cortar acá y seguir en una sesión nueva. Vale aclarar para la próxima sesión: una conversación larga no cambia la corrección del código ya escrito, pero sí puede haber jugado en contra a la hora de razonar con cuidado sobre cada hipótesis nueva. Lo concreto para no repetir el patrón "fix por lectura de código → no cambia nada" es conseguir **evidencia real del dispositivo** (ver recomendación abajo) en vez de seguir iterando a ciegas.

**Recomendación más importante para la próxima sesión:** conseguir acceso a `adb logcat` (no había ningún dispositivo Android conectado a esta máquina, ni `adb` instalado — se verificó con `flutter devices` y `where adb`). Toda esta sesión se debuggeó "a ciegas", solo por lectura de código y razonamiento sobre el comportamiento de los plugins, sin ver nunca un log real del dispositivo — y dos rondas de fixes "correctos por código" no cambiaron nada reportado, lo que sugiere fuertemente que la causa real todavía no fue identificada. Con logcat en mano (filtrando por `flutter`, `GeolocatorLocationService`, `BackgroundService`, `FirebaseFirestore`) se puede confirmar en minutos si:
- El foreground service de background realmente arranca (buscar el log de Android "Foreground service started" / la notificación).
- Los errores de Firestore son realmente `permission-denied` u otra cosa (`UNAVAILABLE`, `DEADLINE_EXCEEDED`, etc. — cada uno tiene causa y fix distintos).
- Cuántos `insertLocation` / `updateLocation` se disparan por minuto y desde qué código exacto (esto es fácil de instrumentar con un simple `print`/log por punto grabado, indicando si vino del isolate de foreground o del de background).

Si conseguir logcat no es posible, el siguiente mejor paso es **aislar manualmente** los dos caminos de grabación (ver sección 4, hipótesis 1): probar el problema de duplicados con la app SIEMPRE abierta en primer plano (nunca minimizada), para saber si el bug está en `location_service.dart` o en `background_location_service.dart`.

---

## 1. Pedido original de esta sesión (contexto)

La sesión arrancó continuando trabajo previo (había un problema de Java/Gradle para poder generar el APK, ya resuelto: se instaló Eclipse Temurin JDK 17 y se apunto el proyecto a el vía `android/gradle.properties` → `org.gradle.java.home`, porque Gradle 8.14 no soporta el JBR 25 de Android Studio).

A partir de ahí, los pedidos fueron, en orden:

1. **"Cuando la app está en segundo plano, o el tel. dormido, no graba en el recorrido/caja negra. Debe grabar cada 1/5 min según lo que se configure, salvo que se repita la ubicación (con cierto margen)."**
2. **"poner como límite mínimo para reconocer movimiento de GPS 20mts"** + **"que Android solo ponga el ícono en la barra, pero no mande mensaje"** (notificación del foreground service).
3. **"Cambiemos 'MiClan está rastreando tu ubicación' por 'MiClan activa GPS'."** + **"al instalar por primera vez, luego de la autorización de GPS, da error [...] que no solicite nuevamente el login, que solo reintente la conexión con un aviso menos aparatoso"**.
4. (Reporte de que lo anterior "está mal") **"Cuando se oprime Reintentar pide el login completo nuevamente [...] El GPS está grabando varias veces el mismo lugar. Debe grabar si está a más de 20 mt de la última grabación."**
5. (Reporte de que sigue igual) **"sigue igual. No cambio. Pide login después de reintentar y graba más de 10 registros por minuto sin que cambie la ubicación."**
6. **"no cambia nada. Vamos a cortar acá."** → pidió este informe.
7. Aclaración final: el usuario confirma que sí prueba el build correcto cada vez (renombra `app-release.apk` → `MiClan2.apk`, copia por FTP, controla el timestamp). Descarta la hipótesis de "build viejo". Pide arrancar sesión nueva porque sospecha que la conversación larga entorpece el proceso.

Es decir: **hay dos síntomas que el usuario reportó SIN cambios en dos rondas de fixes consecutivas, probando siempre el build correcto**, a pesar de que cada ronda encontró y corrigió un bug real y verificable en el código. La causa real todavía no está identificada — ver sección 4.

---

## 2. Arquitectura actual del tracking (como quedó el código)

### Archivos nuevos
- **`lib/services/background_location_service.dart`**: usa el paquete `flutter_background_service` (ya estaba en `pubspec.yaml` pero nunca se usaba) para levantar un Servicio de Android real, con su propio isolate de Dart, independiente del isolate de la UI. Se configura en `main()` (`BackgroundLocationService.initialize()`), y se arranca/detiene desde `HomeScreen` según el ciclo de vida de la app.
- **`lib/services/location_config.dart`**: config compartida entre el tracking de primer plano y el de background:
  - `kSameLocationThresholdMeters = 20.0` (antes 3.0) — margen para considerar "misma ubicación".
  - `getTrackingInterval()` — 1 min normal / 5 min "Modo ahorro" (lee `battery_saver` de SharedPreferences).
  - `loadLastRecordedPosition()` / `saveLastRecordedPosition()` / `isSameAsLastRecorded()` — la última posición efectivamente grabada, persistida (ver bug corregido en sección 3.3).
  - **Usa `SharedPreferencesAsync`, NO `SharedPreferences.getInstance()`** (ver 3.3 — es importante no revertir esto).
- **`lib/services/stream_retry.dart`**: helper `selfHealingStream<T>()` que envuelve un stream de Firestore para que se reintente solo (2s, hasta 6 veces) si tira un error transitorio, sin exponerlo como `AsyncValue.error` en la UI.

### Archivos modificados relevantes
- **`lib/services/location_service.dart`** (tracking en primer plano): el Timer periódico ahora usa el intervalo configurable (antes 30s fijos). `_recordPoint()` centraliza el insert local + update Firestore + persistencia de "última posición grabada", evitando el bug de duplicado en Firestore que había (se grababa el punto directo y además quedaba "pendiente" en SQLite, así que se subía dos veces).
- **`lib/services/auth_service.dart`**: `currentUserStream` ahora:
  - Envuelve la suscripción a Firestore en `selfHealingStream`.
  - **Memoiza `_ensureFreshToken` por uid** (`_tokenEnsuredForUid`): el refresh forzado de token (hasta 5s + 300ms) solo se ejecuta una vez por sesión de login, no en cada reintento.
- **`lib/services/firestore_service.dart`**: `getGroupStream` y `getGroupMembersStream` envueltos en `selfHealingStream`.
- **`lib/screens/home_screen.dart`**:
  - `_errorScaffold` ya no muestra el error técnico crudo (`"Error grupo: $e"`) sino un mensaje genérico ("Problemas de comunicación, reintentá."), y el botón "Reintentar" invalida SOLO el provider que falló (no los tres).
  - `didChangeAppLifecycleState` hace el "handoff": en `paused`/`detached` para el tracking de primer plano y arranca `BackgroundLocationService`; en `resumed` lo detiene y retoma el tracking normal.
- **`lib/services/notification_service.dart`**: canal `gps_tracking_channel` con `Importance.none` (mismo criterio que usa el propio plugin `geolocator_android` para su notificación de foreground service — ver `BackgroundNotification.java` del paquete, que usa `NotificationManager.IMPORTANCE_NONE`): el ícono queda fijo en la barra sin sonido/vibración/heads-up.
- **`android/app/src/main/AndroidManifest.xml`**: el `<service>` de `flutter_background_service` con `android:stopWithTask="false"` explícito (para que no lo mate al deslizar la app de "Recientes").
- **`android/gradle.properties`**: `org.gradle.java.home` apuntando a Temurin 17 (fix de Java, sesión anterior).

---

## 3. Bugs encontrados y corregidos (con evidencia)

### 3.1. Java 25 incompatible con Gradle 8.14 (resuelto, confirmado)
`flutter build apk` fallaba con `FAILURE: ... What went wrong: 25.0.2`. Se instaló Eclipse Temurin JDK 17 vía winget y se configuró `org.gradle.java.home` en `android/gradle.properties`. **Build funciona, confirmado repetidamente.**

### 3.2. No grababa nada en segundo plano (arquitectura, resuelto en su parte estructural)
El tracking vivía enteramente en el isolate de la UI (stream de `geolocator` + `Timer` de Dart). Aunque `geolocator` arma su propia notificación de foreground service, en la práctica Android congela ese isolate con la pantalla apagada o la app minimizada en la mayoría de fabricantes. Se implementó `BackgroundLocationService` (servicio nativo real e independiente, con `flutter_background_service`, que ya estaba declarado en el manifest pero nunca usado). **Este es un cambio arquitectural grande; no se pudo verificar en dispositivo real que efectivamente sigue grabando con el teléfono dormido — solo se verificó que compila y que el build tiene éxito.** Dado que el usuario sigue reportando problemas de grabación, esto necesita verificación real en el próximo ciclo (idealmente con logcat, ver sección 0).

### 3.3. Bug real confirmado: `SharedPreferences.getInstance()` cachea por isolate (resuelto en código, sigue reportado como no resuelto)
Se leyó el código fuente del paquete `shared_preferences` (`shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart`, línea 28: `static Completer<SharedPreferences>? _completer;`). Es un campo **estático**, que en Dart vive por-isolate: la primera vez que se llama `SharedPreferences.getInstance()` en un isolate, se cachea el `Map` de valores en memoria y **nunca se vuelve a leer del disco** en ese isolate. Como el tracking de primer plano y `BackgroundLocationService` corren en isolates distintos, la "última posición grabada" persistida (el fix de la ronda anterior) en la práctica no se veía reflejada entre ambos: cada isolate tenía su propia copia vieja. Se migró todo `location_config.dart` a `SharedPreferencesAsync` (no cachea, consulta la plataforma en cada get/set).

**Este bug es real y estaba bien identificado (era una causa legítima de inconsistencia entre isolates), pero el usuario CONFIRMÓ haber probado este fix con el build correcto y "sigue grabando >10/min" igual.** Conclusión: el fix era necesario pero **no era la única causa** (o no era la causa dominante) de la grabación duplicada. Hipótesis mas fuerte ahora: puede que `BackgroundLocationService` ni siquiera esté llegando a ejecutar el código donde se usa esta comparación (ver hipótesis 1 en sección 4), o que el ruido real del GPS sea mayor al margen configurado (hipótesis 3).

### 3.4. Refresh de token repetido en cada "Reintentar" (resuelto en código, sigue reportado como no resuelto)
`_ensureFreshToken()` (llamada a `getIdToken(true)`, hasta 5s + 300ms fijo) se ejecutaba de nuevo cada vez que se invalidaba `currentUserProvider` — ya sea por el botón "Reintentar" o por cualquier otra causa. Se agregó memoización por `uid` (`_tokenEnsuredForUid`) para que solo se ejecute una vez por sesión de login. **El usuario confirmó haber probado este fix con el build correcto y sigue reportando "pide login".** Esto sugiere que la causa real puede no ser el refresh de token en sí, sino algo que fuerza una navegación real a `/login` — ver hipótesis 4 en sección 4 (el chequeo de "sesión iniciada en otro dispositivo" en `main.dart`).

### 3.5. Escritura duplicada en historial de Firestore (resuelto, no reportado como problema después, pero tampoco confirmado explícitamente)
`_handlePosition` grababa el punto directo en Firestore Y lo dejaba "pendiente" (`synced=0`) en SQLite, así que `_syncPendingLocations` lo volvía a subir. Se corrigió para marcar `synced` solo cuando la escritura directa se confirma.

---

## 4. Hipótesis NO descartadas (para investigar en la próxima sesión)

Descartado: "build viejo" (el usuario confirmó que prueba el build correcto cada vez, controlando el timestamp). Dado que dos rondas de fixes "correctos por código", probados con el build correcto, no cambiaron nada reportado, hay que considerar seriamente:

1. **[Prioridad 1] Aislar primer plano vs. segundo plano.** No está confirmado que `BackgroundLocationService` llegue a ejecutarse en el dispositivo del usuario (permiso denegado silenciosamente, excepción no capturada en `initialize()`/`start()`, restricción del fabricante bloqueando el foreground service). Si nunca arranca, el patrón de ">10 registros/min sin moverse" vendría enteramente del tracking de **primer plano** (`location_service.dart`), y todo el trabajo hecho sobre `background_location_service.dart` sería irrelevante para este síntoma puntual. **Pedirle al usuario que reproduzca el problema con la app SIEMPRE abierta en primer plano** (pantalla prendida, sin minimizar) para confirmar si el duplicado pasa igual — si pasa igual en primer plano, el bug está en `location_service.dart` (posiblemente en la logica de `_handlePosition`/`shouldUpload`, que compara contra `_lastPosition` en memoria y no contra la posición persistida salvo para el chequeo final de "misma ubicación" — revisar esa función con más cuidado, o directamente loguear cada llamada a `_recordPoint` con su origen).
2. **El teléfono de prueba tiene un administrador de batería agresivo** (Xiaomi/Huawei/Oppo/Samsung) que ignora `stopWithTask="false"` y la exclusión de optimización de batería, matando o reiniciando el servicio de formas no estándar y en loop. Esto no se resuelve por código; requiere que el usuario habilite manualmente "inicio automático" / "sin restricciones" para MiClan en los ajustes específicos del fabricante. Si el servicio se reinicia en loop, cada reinicio podría estar generando un punto nuevo pese al fix de `SharedPreferencesAsync` (por ejemplo si el reinicio es tan rápido que la escritura anterior de `saveLastRecordedPosition` todavía no se confirmó).
3. **El ruido real del GPS en el entorno de prueba supera los 20m.** Si el usuario prueba en interiores, el GPS/red puede saltar 50-100+ metros entre lecturas por multipath — en ese caso ningún umbral de distancia razonable "arregla" el problema completamente; habría que sumar un filtro por precisión (`Position.accuracy`) además de la distancia, o subir el umbral bastante más, o directamente ignorar lecturas con `accuracy` mayor a cierto valor.
4. **El "pide login" puede ser una navegación real a `/login`, no solo lentitud.** Revisar el chequeo de "sesión iniciada en otro dispositivo" en `main.dart` (`_MiClanAppState._initApp`, el `ref.listenManual(currentUserProvider, ...)`): compara `user.sessionId` (de Firestore) contra la sesión local, y si no coincide fuerza `signOut()` → eso SÍ navega de verdad a `/login`. Si el doc de Firestore llega con un `sessionId` viejo por venir de la caché local de Firestore (offline persistence, activada por defecto) antes de que llegue la versión del servidor, esto podría estar disparando un falso positivo. Vale revisar si conviene ignorar snapshots que vengan de caché (`doc.metadata.isFromCache`) para este chequeo puntual, o directamente loguear cuándo se dispara ese `signOut()` y con qué valores.
5. Confirmar si el usuario instaló el APK **encima** del anterior (update) o hizo un **uninstall/reinstall limpio** — no debería importar dado que `SharedPreferencesAsync` y el legacy usan el mismo backend de storage, pero es una variable menos a descartar si las otras no explican el problema.

---

## 5. Qué está verificado y qué NO

**Verificado (con herramientas, en esta sesión):**
- Todos los builds (`flutter build apk --release`) terminaron en `BUILD SUCCESSFUL` / `Built ... app-release.apk`.
- `flutter analyze` sin errores (`^error` vacío) en cada ronda.
- El bug de caché de `SharedPreferences` por isolate está confirmado leyendo el código fuente del plugin (alta confianza en que ERA un bug real, aunque no se confirmó que sea LA causa completa de lo que reporta el usuario).
- El canal de notificación `Importance.none` replica exactamente lo que hace `geolocator_android` en su propio código (`BackgroundNotification.java`), confirmado leyendo su fuente.

**NO verificado (ningún dispositivo Android conectado a esta máquina, todo el debugging fue por lectura de código):**
- Que `BackgroundLocationService` efectivamente arranca como foreground service en el dispositivo real del usuario.
- Que el fix de `SharedPreferencesAsync` efectivamente resuelve el cruce de datos entre isolates en la práctica (aunque la causa está bien identificada por código, el usuario reporta que el síntoma sigue igual después de probarlo).
- Logs reales de Firestore (qué tipo de error da exactamente: `permission-denied`, `unavailable`, otro) o de Android (si el foreground service arranca, si lo mata el sistema, etc.).
- Si el "pide login" es literalmente una navegación a `/login`, o solo una demora que se siente parecida.

**Descartado explícitamente por el usuario:** que se estuviera probando un build viejo — confirmó su flujo de instalación (rename + FTP + chequeo de timestamp) y que es el mismo en las tres rondas.

---

## 6. Recomendación concreta para arrancar la próxima sesión

1. **Prioridad 1 — aislar el bug de duplicados:** pedirle al usuario que reproduzca "graba muchas veces sin moverse" con la app SIEMPRE en primer plano (pantalla prendida, nunca minimizada). Si pasa igual, el bug está 100% en `location_service.dart` y hay que revisar `_handlePosition`/`shouldUpload` con más cuidado (instrumentar con logs temporales si hace falta). Si NO pasa en primer plano y solo pasa backgrounded, el foco pasa a `background_location_service.dart` y a si el servicio se está reiniciando en loop (hipótesis 2 de la sección 4).
2. Si es posible, conseguir `adb` + el teléfono conectado (USB debugging) para poder correr `adb logcat` en vivo mientras el usuario reproduce el problema, en vez de seguir debuggeando a ciegas por lectura de código. Esto es lo que más ayudaría a cortar con el patrón "fix por código → no cambia nada".
3. Para el "pide login": agregar un log temporal (o `debugPrint`) en el `signOut()` del chequeo de sesión en `main.dart` (`_MiClanAppState._initApp`) para confirmar si se dispara, y con qué `sessionId`s. Si se confirma que es eso, filtrar por `doc.metadata.isFromCache` antes de comparar (hipótesis 4, sección 4).
4. Si el problema de duplicados persiste incluso aislado a primer plano y sin loop de reinicios, considerar sumar un filtro por `Position.accuracy` (ignorar lecturas de baja precisión) ademas del umbral de distancia — sobre todo si las pruebas se hacen en interiores.

---

## 7. Estado de git

Todos los cambios de esta sesión están en el working tree, **sin commitear** (no se pidió commitear). `git status` al momento de escribir este informe:

```
 M .gitignore
 M android/app/src/main/AndroidManifest.xml
 M android/gradle.properties
 M lib/main.dart
 M lib/screens/home_screen.dart
 M lib/services/auth_service.dart
 M lib/services/battery_optimization_service.dart   (de sesión anterior, no tocado ahora)
 M lib/services/database_helper.dart
 M lib/services/firestore_service.dart
 M lib/services/location_service.dart
 M lib/services/notification_service.dart
?? lib/services/background_location_service.dart
?? lib/services/location_config.dart
?? lib/services/stream_retry.dart
?? .claude/settings.local.json   (gitignored, permisos locales)
```

(Lista no exhaustiva — hay otros archivos modificados de sesiones previas no relacionados con este tema, como `lib/screens/welcome_screen.dart`, `assets/images/app_logo.png`, etc.)

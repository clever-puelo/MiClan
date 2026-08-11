import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'battery_optimization_service.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'location_config.dart';

// ============================================================================
// LOCATION SERVICE - GPS + Tracking + Sync (primer plano)
// ============================================================================
// FIX 2026-08-06:
// - Evita multiples streams simultaneos (guarda la suscripción y la cancela
//   antes de crear una nueva).
// - Timer periódico fuerza sync a Firestore aunque no haya movimiento
//   significativo. Esto evita que la posición se "congele" en el mapa
//   cuando el usuario esta quieto.
// - Mejor manejo de errores para no romper el stream.
//
// FIX 2026-08-08:
// - Si la ubicación reportada es identica (o casi identica) a la ultima que
//   se grabo, ya no se crea un nuevo punto de historial ni se reescribe
//   Firestore de mas: solo se actualiza un "latido" (touchLocation) para
//   marcar que el usuario sigue activo, evitando llenar la caja negra de
//   puntos duplicados con el usuario quieto.
// - Se solicita explicitamente el permiso de ubicación "todo el tiempo"
//   (background) ademas del permiso "mientras se usa la app": sin esto,
//   Android detiene el GPS en segundo plano en cuanto la pantalla se apaga
//   o el telefono se duerme, sin importar que exista un foreground service.
//
// FIX 2026-08-10:
// - El Timer periódico usaba un intervalo fijo de 30s, sin relación con lo
//   que el usuario configura en Ajustes > Batería ("Modo ahorro": cada 1
//   min normal / cada 5 min ahorro). Ahora respeta ese intervalo (ver
//   location_config.dart), releyendolo en cada ciclo por si el usuario lo
//   cambia con el tracking ya andando.
// - El Timer periódico solo escribia en Firestore, sin guardar el punto en
//   la caja negra local (SQLite). Ahora usa el mismo helper `_recordPoint`
//   que el stream de geolocator, asi ambos caminos quedan consistentes.
// - Se corrigio una escritura duplicada en el historial de Firestore: se
//   grababa el punto directo (updateLocation) y ademas quedaba "pendiente"
//   (synced=0) en SQLite, asi que `_syncPendingLocations` lo volvia a subir
//   una segunda vez. Ahora solo se marca `synced` en SQLite si la escritura
//   directa a Firestore fallo (sin señal), para que quede pendiente y se
//   reintente una unica vez.
// - Para que la grabación no se detenga con la app en segundo plano o el
//   telefono dormido, el "handoff" real a un servicio nativo de Android
//   independiente del isolate de la UI ahora lo maneja HomeScreen usando
//   BackgroundLocationService (ver background_location_service.dart) al
//   pasar a background/resume.
//
// - "graba varias veces el mismo lugar": la ultima posición grabada ya no
//   se guarda en una variable en memoria de esta clase (`_lastRecordedPosition`
//   Position?), sino en SharedPreferences (ver location_config.dart). Al
//   vivir en un isolate propio, BackgroundLocationService no compartia esa
//   variable y, cada vez que HomeScreen hacia el handoff a segundo plano,
//   arrancaba sin saber que ya se habia grabado un punto ahi mismo segundos
//   antes, grabando el mismo lugar de nuevo. Con el valor persistido, ambos
//   caminos (primer y segundo plano) comparan contra el mismo dato.
// ============================================================================

class LocationService {
  final FirestoreService _firestore = FirestoreService();
  final DatabaseHelper _db = DatabaseHelper();
  Position? _lastPosition;
  StreamSubscription<Position>? _positionSub;
  Timer? _syncTimer;
  String? _currentUid;
  String? _currentGroupId;
  Future<void>? _startFuture;

  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    // FIX: ademas del permiso "mientras se usa la app", pedimos el permiso
    // de ubicación en segundo plano para que el GPS se siga grabando con el
    // telefono dormido / la app minimizada. En Android 11+ el sistema solo
    // ofrece "Permitir todo el tiempo" si se vuelve a pedir el permiso una
    // vez que ya se tiene el de primer plano (si el SO no lo ofrece asi,
    // hay que habilitarlo manualmente en Ajustes > Ubicación).
    if (permission == LocationPermission.whileInUse) {
      await Geolocator.requestPermission();
    }
    return true;
  }

  /// true si ya se cuenta con el permiso de ubicación "todo el tiempo"
  /// (background), necesario para grabar con el telefono dormido.
  Future<bool> hasBackgroundPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  // FIX 2026-08-10 (tercera vuelta) - causa real confirmada por logcat en
  // dispositivo real: Android pausa/reanuda la Activity cuando se muestra
  // (y se cierra) el dialogo del sistema para el permiso de ubicación, asi
  // que `didChangeAppLifecycleState(resumed)` en HomeScreen se dispara
  // varias veces casi seguidas justo al loguearse/otorgar el permiso. Cada
  // una llama a `startTracking()`, y como el guard de "ya esta corriendo"
  // solo mira `_positionSub` (que recien se asigna varios `await` mas
  // abajo), llamadas concurrentes pasaban el guard igual y cada una grababa
  // su propio punto inicial sin chequear contra el ultimo grabado -- se
  // vio en logcat como 5 puntos identicos grabados en menos de un segundo.
  // Ahora una unica llamada "en vuelo" se comparte entre todas las
  // llamadas concurrentes (devuelven el mismo Future en vez de arrancar
  // cada una la suya).
  Future<void> startTracking(String uid, String groupId) {
    if (_startFuture != null) return _startFuture!;
    if (_positionSub != null && _currentUid == uid && _currentGroupId == groupId) {
      return Future.value();
    }
    final future = _startTrackingInternal(uid, groupId);
    _startFuture = future;
    future.whenComplete(() => _startFuture = null);
    return future;
  }

  Future<void> _startTrackingInternal(String uid, String groupId) async {
    if (!await checkPermissions()) return;

    // Cancelar anterior si existe
    await stopTracking();
    _currentUid = uid;
    _currentGroupId = groupId;

    // Reporta el estado apenas arranca (no espera al primer ciclo del
    // timer de sync), para que el panel de monitoreo del admin refleje
    // "App activa" de inmediato.
    unawaited(_reportStatus(uid, groupId, 'foreground'));

    try {
      final currentPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      // FIX: antes se grababa este punto inicial SIN chequear si coincidia
      // con el ultimo ya grabado, asi que cada (re)arranque de tracking
      // (resume desde background, o el bug de reentrancia de arriba)
      // agregaba un duplicado del mismo lugar.
      final lastRecorded = await loadLastRecordedPosition();
      if (!isSameAsLastRecorded(lastRecorded, currentPos.latitude, currentPos.longitude)) {
        await _recordPoint(uid, groupId, currentPos);
      }
      _lastPosition = currentPos;
    } catch (e) {
      // Si falla la posición inicial, continuamos igual con el stream
    }

    // FIX: notificationText/Title en foreground service. `enableWakeLock`
    // + `setOngoing` + el permiso de background son lo que permite que
    // Android siga entregando posiciones con la pantalla apagada.
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: const Duration(seconds: 20),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationText: 'MiClan activa GPS',
        notificationTitle: 'GPS Activo',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (position) async {
        await _handlePosition(uid, groupId, position);
      },
      onError: (e) {
        // No romper el stream; el foreground service se reinicia solo
      },
    );

    _scheduleSyncTimer();
  }

  /// Timer que se reprograma solo en cada ciclo (en vez de `periodic` con
  /// intervalo fijo) para poder respetar el intervalo configurado (1 o 5
  /// min) incluso si el usuario lo cambia con el tracking ya en marcha.
  void _scheduleSyncTimer() {
    _syncTimer?.cancel();
    getTrackingInterval().then((interval) {
      if (_currentUid == null) return; // se detuvo mientras esperabamos
      _syncTimer = Timer(interval, _runSyncCycle);
    });
  }

  Future<void> _runSyncCycle() async {
    final uid = _currentUid;
    final groupId = _currentGroupId;
    if (uid == null || groupId == null) return;

    // Reporta estado en cada ciclo (1 o 5 min): mantiene `updatedAt` fresco
    // en deviceStatus aunque el usuario este quieto, para que el panel de
    // monitoreo del admin no lo muestre como "desconectado" sin estarlo.
    unawaited(_reportStatus(uid, groupId, 'foreground'));

    if (_lastPosition != null) {
      final lastRecorded = await loadLastRecordedPosition();
      if (isSameAsLastRecorded(lastRecorded, _lastPosition!.latitude, _lastPosition!.longitude)) {
        await _firestore.touchLocation(uid, groupId);
      } else {
        await _recordPoint(uid, groupId, _lastPosition!);
      }
      await _syncPendingLocations(uid, groupId);
    }

    final interval = await getTrackingInterval();
    _syncTimer?.cancel();
    if (_currentUid != uid || _currentGroupId != groupId) return; // se detuvo/cambio mientras esperabamos
    _syncTimer = Timer(interval, _runSyncCycle);
  }

  /// Graba un punto en la caja negra local y en el historial de Firestore,
  /// y actualiza la ultima posición grabada persistida (ver
  /// location_config.dart) para que tanto el stream de foreground como el
  /// servicio de background comparen contra el mismo valor.
  ///
  /// Si la escritura a Firestore falla (sin señal), el punto queda
  /// pendiente en SQLite (`synced = 0`) para que `_syncPendingLocations` lo
  /// reintente mas tarde: por eso solo se marca sincronizado cuando la
  /// escritura directa realmente se confirma, evitando subirlo dos veces.
  Future<void> _recordPoint(String uid, String groupId, Position position) async {
    final id = await _db.insertLocation(groupId, position.latitude, position.longitude);
    await saveLastRecordedPosition(position.latitude, position.longitude);
    try {
      await _firestore.updateLocation(uid, groupId, position.latitude, position.longitude);
      await _db.markLocationSynced(id);
    } catch (_) {
      // Sin señal: queda pendiente en SQLite, se reintenta luego.
    }
  }

  Future<void> _handlePosition(String uid, String groupId, Position position) async {
    try {
      // FIX 2026-08-11: antes leia 'battery_saver' con SharedPreferences
      // clasico (SharedPreferences.getInstance()), un storage distinto al
      // que usa isBatterySaverEnabled() (SharedPreferencesAsync, ver
      // location_config.dart) -- desde que Configuracion escribe el switch
      // por ese mismo canal, leerlo aca con el clasico quedaria siempre
      // desactualizado (el mismo bug, al reves). Unificado a un solo canal.
      final batterySaver = await isBatterySaverEnabled();
      final minDistance = batterySaver ? 200.0 : 50.0;

      bool shouldUpload = false;
      if (_lastPosition == null) {
        shouldUpload = true;
      } else {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude, _lastPosition!.longitude,
          position.latitude, position.longitude,
        );
        shouldUpload = distance > minDistance;
      }
      _lastPosition = position;

      // FIX: si la ubicación es identica (dentro del margen configurado,
      // ver kSameLocationThresholdMeters) a la ultima que grabamos, no se
      // graba de nuevo (ni en Firestore ni en la caja negra local) aunque
      // el throttling de distancia hubiese permitido subirla.
      final lastRecorded = await loadLastRecordedPosition();
      if (isSameAsLastRecorded(lastRecorded, position.latitude, position.longitude)) {
        return;
      }

      if (shouldUpload) {
        await _recordPoint(uid, groupId, position);
        await _syncPendingLocations(uid, groupId);
      }
    } catch (e) {
      // Silencioso: no romper el stream
    }
  }

  Future<void> _syncPendingLocations(String uid, String groupId) async {
    final pending = await _db.getUnsyncedLocations();
    for (final loc in pending) {
      try {
        await _firestore.updateLocation(uid, groupId, loc['lat'], loc['lng']);
        await _db.markLocationSynced(loc['id']);
      } catch (_) {}
    }
  }

  /// Reporta el estado de conexion de este dispositivo a Firestore
  /// (`deviceStatus/{uid}`) para el panel de monitoreo del admin
  /// (Configuracion > Estado de Miembros). No debe romper el tracking si
  /// falla (sin señal, permiso denegado, etc.), por eso va en su propio
  /// try/catch y se llama con `unawaited()` desde los puntos de arriba.
  Future<void> _reportStatus(String uid, String groupId, String appState) async {
    try {
      final interval = await getTrackingInterval();
      final bgGranted = await hasBackgroundPermission();
      final batteryOk = await BatteryOptimizationService.isIgnoring();
      await _firestore.updateDeviceStatus(
        uid,
        groupId,
        appState: appState,
        batterySaver: interval == kBatterySaverTrackingInterval,
        backgroundLocationGranted: bgGranted,
        batteryOptimizationIgnored: batteryOk,
        trackingIntervalMinutes: interval.inMinutes,
      );
    } catch (_) {
      // No romper el tracking si falla el reporte de estado.
    }
  }

  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _currentUid = null;
    _currentGroupId = null;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }
}

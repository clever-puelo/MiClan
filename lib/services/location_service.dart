import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'firestore_service.dart';

// ============================================================================
// LOCATION SERVICE - GPS + Tracking + Sync
// ============================================================================
// FIX 2026-08-06:
// - Evita multiples streams simultaneos (guarda la suscripcion y la cancela
//   antes de crear una nueva).
// - Timer periodico (cada 30s) fuerza sync a Firestore aunque no haya
//   movimiento significativo. Esto evita que la posicion se "congele" en
//   el mapa cuando el usuario esta quieto.
// - Mejor manejo de errores para no romper el stream.
// ============================================================================

class LocationService {
  final FirestoreService _firestore = FirestoreService();
  final DatabaseHelper _db = DatabaseHelper();
  Position? _lastPosition;
  StreamSubscription<Position>? _positionSub;
  Timer? _syncTimer;
  String? _currentUid;
  String? _currentGroupId;

  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<void> startTracking(String uid, String groupId) async {
    if (!await checkPermissions()) return;

    // Evitar multiples streams
    if (_positionSub != null && _currentUid == uid && _currentGroupId == groupId) {
      return;
    }

    // Cancelar anterior si existe
    await stopTracking();
    _currentUid = uid;
    _currentGroupId = groupId;

    try {
      final currentPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _db.insertLocation(groupId, currentPos.latitude, currentPos.longitude);
      await _firestore.updateLocation(uid, groupId, currentPos.latitude, currentPos.longitude);
      _lastPosition = currentPos;
    } catch (e) {
      // Si falla la posicion inicial, continuamos igual con el stream
    }

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationText: 'MiClan esta rastreando tu ubicacion',
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

    // Timer periodico: fuerza sync cada 30 segundos aunque no haya movimiento
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_lastPosition != null && _currentUid != null && _currentGroupId != null) {
        await _firestore.updateLocation(
          _currentUid!, _currentGroupId!,
          _lastPosition!.latitude, _lastPosition!.longitude,
        );
        await _syncPendingLocations(_currentUid!, _currentGroupId!);
      }
    });
  }

  Future<void> _handlePosition(String uid, String groupId, Position position) async {
    try {
      await _db.insertLocation(groupId, position.latitude, position.longitude);

      final prefs = await SharedPreferences.getInstance();
      final batterySaver = prefs.getBool('battery_saver') ?? false;
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

      if (shouldUpload) {
        await _firestore.updateLocation(uid, groupId, position.latitude, position.longitude);
        _lastPosition = position;
        await _syncPendingLocations(uid, groupId);
      } else {
        // Aunque no subamos, actualizamos _lastPosition para que el timer
        // periodico suba la posicion mas reciente
        _lastPosition = position;
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
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }
}

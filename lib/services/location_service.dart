import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'firestore_service.dart';

class LocationService {
  final FirestoreService _firestore = FirestoreService();
  final DatabaseHelper _db = DatabaseHelper();
  Position? _lastPosition;

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
    const locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    Geolocator.getPositionStream(locationSettings: locationSettings).listen((position) async {
      await _db.insertLocation(position.latitude, position.longitude);
      final prefs = await SharedPreferences.getInstance();
      final batterySaver = prefs.getBool('battery_saver') ?? false;
      final minDistance = batterySaver ? 200.0 : 50.0;
      bool shouldUpload = false;
      if (_lastPosition == null) {
        shouldUpload = true;
      } else {
        final distance = Geolocator.distanceBetween(_lastPosition!.latitude, _lastPosition!.longitude, position.latitude, position.longitude);
        shouldUpload = distance > minDistance;
      }
      if (shouldUpload) {
        await _firestore.updateLocation(uid, groupId, position.latitude, position.longitude);
        _lastPosition = position;
        await _syncPendingLocations(uid, groupId);
      }
    });
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

  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (_) { return null; }
  }
}
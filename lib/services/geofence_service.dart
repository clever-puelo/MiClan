import 'package:geolocator/geolocator.dart';
import '../models/app_models.dart';

class GeofenceService {
  bool? _wasInside;

  String? checkGeofenceCrossing(GeofenceZone zone, double currentLat, double currentLng, String memberName) {
    final distance = Geolocator.distanceBetween(zone.lat, zone.lng, currentLat, currentLng);
    final isInside = distance <= zone.radiusMeters;
    if (_wasInside == null) { _wasInside = isInside; return null; }
    if (_wasInside == true && !isInside) { _wasInside = false; return '⚠️ \$memberName salió de \${zone.name}'; }
    if (_wasInside == false && isInside) { _wasInside = true; return '✅ \$memberName entró a \${zone.name}'; }
    return null;
  }

  void reset() { _wasInside = null; }
}
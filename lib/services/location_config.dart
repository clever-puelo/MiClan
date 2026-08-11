import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// LOCATION CONFIG - Config compartida de grabación ("caja negra")
// ============================================================================
// FIX 2026-08-10: antes el intervalo real de grabación estaba "hardcodeado"
// en 30s (location_service.dart) sin relación con lo que decía el switch
// "Modo ahorro" en Ajustes ("GPS cada 1 min / 50m" / "cada 5 min / 200m").
// Se centraliza aca para que tanto el tracking en primer plano
// (location_service.dart) como el servicio nativo en segundo plano
// (background_location_service.dart) graben exactamente con el intervalo
// que el usuario configuro, sin importar si la app esta abierta,
// minimizada o el telefono dormido.
//
// FIX 2026-08-10 (segunda vuelta) - IMPORTANTE:
// Todo este archivo usa `SharedPreferencesAsync` (no el `SharedPreferences`
// clasico / `.getInstance()`). Motivo: `SharedPreferences.getInstance()`
// cachea TODOS los valores en un Map en memoria la PRIMERA vez que se llama
// dentro de un isolate, y ya no los vuelve a leer del disco -- las llamadas
// siguientes a `getInstance()` en ESE MISMO isolate devuelven la instancia
// cacheada de siempre. Como el tracking en primer plano corre en el isolate
// principal de la UI y BackgroundLocationService corre en OTRO isolate
// (separado, propio de flutter_background_service), cada uno terminaba con
// su propia copia vieja de "ultima posición grabada": el fix anterior
// (persistir esa posición en SharedPreferences) en la practica no cruzaba
// la informacion entre ambos, y por eso seguia grabando el mismo lugar
// muchas veces. `SharedPreferencesAsync` no cachea nada: cada get/set habla
// directo con la plataforma, asi que ambos isolates siempre ven el valor
// real y actualizado.
// ============================================================================

final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

/// Id del canal de notificación Android usado por el foreground service de
/// BackgroundLocationService. Debe existir ANTES de arrancar el servicio
/// (se crea en NotificationService._createChannels), por eso vive aca como
/// constante compartida entre ambos archivos.
const String kGpsTrackingNotificationChannelId = 'gps_tracking_channel';

/// Distancia (en metros) por debajo de la cual dos posiciones se consideran
/// "la misma ubicación" y por lo tanto no generan un nuevo punto en la caja
/// negra (solo se refresca el "latido" para marcar al usuario como activo).
///
/// FIX 2026-08-10: subido de 3m a 20m a pedido del usuario: el GPS de un
/// telefono quieto "flota" varios metros por ruido de la señal, y con 3m
/// eso se registraba como movimiento real. Con 20m, cualquier diferencia
/// menor a esa se considera ruido y se ignora (no cuenta como movimiento).
const double kSameLocationThresholdMeters = 20.0;

const Duration kNormalTrackingInterval = Duration(minutes: 1);
const Duration kBatterySaverTrackingInterval = Duration(minutes: 5);

const String _kPrefBatterySaver = 'battery_saver';

// FIX 2026-08-11: se detecto que "Modo ahorro" quedaba SIN NINGUN efecto en
// el intervalo real de grabacion. Causa: `SharedPreferencesAsync` en
// Android usa por defecto el backend "DataStore" (Jetpack DataStore
// Preferences) -- un almacenamiento DISTINTO al archivo clasico que usa
// `SharedPreferences.getInstance()` (el legacy `SharedPreferencesPlugin`).
// `settings_screen.dart` escribia el switch con `SharedPreferences.
// getInstance()` (archivo clasico), pero `getTrackingInterval()` de este
// archivo leia con `SharedPreferencesAsync` (DataStore) -- dos storages
// completamente separados que nunca se cruzaban. El toggle se veia
// correcto en la propia pantalla de Configuracion (que leia y escribia
// siempre del mismo storage clasico, autoconsistente), pero el intervalo
// real usado por el timer de sync (primer plano) y por el tick loop del
// servicio de background quedaba SIEMPRE en 1 minuto, sin importar lo que
// el usuario configurara.
//
// Fix: centralizar el flag "battery_saver" aca, con getters/setters
// publicos que SIEMPRE usan la misma instancia de `SharedPreferencesAsync`
// (`_prefs`, ya usada para el resto de este archivo). `settings_screen.dart`
// y `location_service.dart` deben llamar a estas funciones, NUNCA leer o
// escribir 'battery_saver' directo con `SharedPreferences`/
// `SharedPreferencesAsync` por su cuenta -- asi no puede volver a divergir.
Future<bool> isBatterySaverEnabled() async {
  return await _prefs.getBool(_kPrefBatterySaver) ?? false;
}

Future<void> setBatterySaverEnabled(bool enabled) async {
  await _prefs.setBool(_kPrefBatterySaver, enabled);
}

/// Intervalo de grabación configurado por el usuario (Ajustes > Batería >
/// "Modo ahorro"): 1 minuto normalmente, 5 minutos en modo ahorro.
Future<Duration> getTrackingInterval() async {
  final batterySaver = await isBatterySaverEnabled();
  return batterySaver ? kBatterySaverTrackingInterval : kNormalTrackingInterval;
}

// ============================================================================
// "graba varias veces el mismo lugar": la ultima posición efectivamente
// grabada se persiste (no vive en una variable en memoria de un isolate
// puntual) para que el tracking en primer plano y el servicio de segundo
// plano comparen siempre contra el mismo dato, sin importar quien grabo el
// ultimo punto ni cuantas veces se reinicio el servicio de background.
// ============================================================================

const String _kPrefLastRecordedLat = 'last_recorded_lat';
const String _kPrefLastRecordedLng = 'last_recorded_lng';

class LastRecordedPosition {
  final double lat;
  final double lng;
  const LastRecordedPosition(this.lat, this.lng);
}

Future<LastRecordedPosition?> loadLastRecordedPosition() async {
  final lat = await _prefs.getDouble(_kPrefLastRecordedLat);
  final lng = await _prefs.getDouble(_kPrefLastRecordedLng);
  if (lat == null || lng == null) return null;
  return LastRecordedPosition(lat, lng);
}

Future<void> saveLastRecordedPosition(double lat, double lng) async {
  await _prefs.setDouble(_kPrefLastRecordedLat, lat);
  await _prefs.setDouble(_kPrefLastRecordedLng, lng);
}

/// true si (lat, lng) esta a menos de [kSameLocationThresholdMeters] de la
/// ultima posición efectivamente grabada (o no hay ninguna todavia => false,
/// para que el primer punto siempre se grabe).
bool isSameAsLastRecorded(LastRecordedPosition? last, double lat, double lng) {
  if (last == null) return false;
  final distance = Geolocator.distanceBetween(lat, lng, last.lat, last.lng);
  return distance <= kSameLocationThresholdMeters;
}

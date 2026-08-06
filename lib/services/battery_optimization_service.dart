import 'package:permission_handler/permission_handler.dart';

// ============================================================================
// BATTERY OPTIMIZATION SERVICE
// Verifica si Android esta ignorando las optimizaciones de bateria para
// MiClan. Si no, el usuario debe aceptar el dialogo nativo.
// Sin esto, Doze mode retrasa o elimina notificaciones FCM y mata el
// foreground service de GPS cuando el telefono duerme profundamente.
// ============================================================================

class BatteryOptimizationService {
  /// Retorna true si la app YA esta excluida de optimizaciones de bateria.
  static Future<bool> isIgnoring() async {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  /// Muestra el dialogo nativo de Android para ignorar optimizaciones.
  /// Retorna true si el usuario acepto.
  static Future<bool> request() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }
}

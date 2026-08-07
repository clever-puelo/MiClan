import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================================
// NOTIFICATION SERVICE - Notificaciones Locales
// ============================================================================
// FIX 2026-08-07: Eliminados startListeningAlerts/stopListeningAlerts.
// Las notificaciones ahora solo llegan via FCM (data-only payload).
// El background handler y el foreground handler son los unicos que
// llaman a showLocalNotification. No hay listener de Firestore.
// ============================================================================

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Manejar tap en notificacion
      },
    );

    await _createChannels();
    _initialized = true;
  }

  static Future<void> _createChannels() async {
    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'sos_channel',
        'S.O.S Emergencia',
        description: 'Alertas de panico del grupo',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'msg_channel',
        'Mensajes MiClan',
        description: 'Mensajes y alertas del grupo',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'geofence_channel',
        'Geofence',
        description: 'Notificaciones de zona segura',
        importance: Importance.high,
      ),
    );
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
    required String channelId,
    String? payload,
    int id = 0,
  }) async {
    final isSos = channelId == 'sos_channel';
    final androidDetails = AndroidNotificationDetails(
      channelId,
      isSos ? 'S.O.S Emergencia' : 'Mensajes MiClan',
      channelDescription: isSos ? 'Alertas de panico del grupo' : 'Mensajes del grupo',
      importance: isSos ? Importance.max : Importance.high,
      priority: isSos ? Priority.max : Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: isSos ? Int64List.fromList([0, 500, 200, 500, 200, 500]) : null,
      icon: '@mipmap/ic_launcher',
      category: isSos ? AndroidNotificationCategory.alarm : null,
      fullScreenIntent: isSos,
      autoCancel: !isSos,
      visibility: NotificationVisibility.public,
    );
    final details = NotificationDetails(android: androidDetails);
    await _local.show(id, title, body, details, payload: payload);
  }
}

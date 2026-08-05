import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio de notificaciones LOCALES.
/// El envio push real lo hace la Cloud Function de Firebase.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Navegacion al tocar notificacion: se maneja desde main.dart
        // via FirebaseMessaging.onMessageOpenedApp para mantener consistencia
      },
    );

    // NOTA: Int64List.fromList NO es const, asi que usamos final en vez de const
    final sosChannel = AndroidNotificationChannel(
      'sos_channel',
      'S.O.S Emergencia',
      description: 'Alertas de panico del grupo',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
    );

    const msgChannel = AndroidNotificationChannel(
      'msg_channel',
      'Mensajes MiClan',
      description: 'Mensajes del grupo',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(sosChannel);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(msgChannel);

    _initialized = true;
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
      channelDescription: isSos
          ? 'Alertas de panico del grupo'
          : 'Mensajes del grupo',
      importance: isSos ? Importance.max : Importance.high,
      priority: isSos ? Priority.max : Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: isSos
          ? Int64List.fromList([0, 500, 200, 500, 200, 500])
          : null,
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

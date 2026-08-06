import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static StreamSubscription<QuerySnapshot>? _alertsSub;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _local.initialize(initSettings);

    final sosChannel = AndroidNotificationChannel(
      'sos_channel', 'S.O.S Emergencia',
      description: 'Alertas de panico del grupo',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
    );
    const msgChannel = AndroidNotificationChannel(
      'msg_channel', 'Mensajes MiClan',
      description: 'Mensajes del grupo',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(sosChannel);
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
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

  static void startListeningAlerts(String groupId, String myUid) {
    _alertsSub?.cancel();
    _alertsSub = FirebaseFirestore.instance
        .collection('alerts')
        .where('groupId', isEqualTo: groupId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          if (data['senderId'] == myUid) continue;
          final receiverId = data['receiverId'] as String? ?? 'all';
          if (receiverId != 'all' && receiverId != myUid) continue;

          final type = data['type'] as String? ?? 'system';
          final senderName = data['senderName'] as String? ?? 'MiClan';
          final payload = data['payload'] as String? ?? '';

          String title, body, channel;
          switch (type) {
            case 'SOS':
              title = 'S.O.S - MiClan';
              body = 'ALERTA DE PANICO por $senderName';
              channel = 'sos_channel';
              break;
            case 'photo':
              title = 'MiClan - $senderName';
              body = 'Te envio una foto';
              channel = 'msg_channel';
              break;
            case 'audio':
              title = 'MiClan - $senderName';
              body = 'Te envio un audio';
              channel = 'msg_channel';
              break;
            default:
              title = 'MiClan - $senderName';
              body = payload;
              channel = 'msg_channel';
          }
          showLocalNotification(title: title, body: body, channelId: channel, id: DateTime.now().millisecond);
        }
      }
    });
  }

  static void stopListeningAlerts() {
    _alertsSub?.cancel();
    _alertsSub = null;
  }
}

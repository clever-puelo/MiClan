import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String? groupId;
  final String? fcmToken;
  final String? sessionId;
  final String? phone;
  final DateTime? createdAt;

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.groupId,
    this.fcmToken,
    this.sessionId,
    this.phone,
    this.createdAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) => AppUser(
        uid: uid,
        email: map['email'] ?? '',
        displayName: map['displayName'] ?? 'Usuario',
        groupId: map['groupId'],
        fcmToken: map['fcmToken'],
        sessionId: map['sessionId'],
        phone: map['phone'],
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'groupId': groupId,
        'fcmToken': fcmToken,
        'sessionId': sessionId,
        'phone': phone,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      };

  bool isAdminOf(String? groupOwnerId) => uid == groupOwnerId;
}

class AppGroup {
  final String id;
  final String name;
  final String joinCode;
  final String ownerId;
  final DateTime? createdAt;

  AppGroup({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.ownerId,
    this.createdAt,
  });

  factory AppGroup.fromMap(Map<String, dynamic> map, String id) => AppGroup(
        id: id,
        name: map['name'] ?? '',
        joinCode: map['joinCode'] ?? '',
        ownerId: map['ownerId'] ?? '',
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'joinCode': joinCode,
        'ownerId': ownerId,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      };
}

class PendingRequest {
  final String id;
  final String uid;
  final String displayName;
  final DateTime requestedAt;
  final String status;

  PendingRequest({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.requestedAt,
    required this.status,
  });

  factory PendingRequest.fromMap(Map<String, dynamic> map, String id) => PendingRequest(
        id: id,
        uid: map['uid'] ?? '',
        displayName: map['displayName'] ?? '',
        requestedAt: (map['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        status: map['status'] ?? 'pending',
      );

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'status': status,
      };
}

class AppAlert {
  final String id;
  final String groupId;
  final String senderId;
  final String receiverId;
  final String type;
  final String payload;
  final DateTime timestamp;
  final String? senderName;
  final String? sosStatus;
  final String? cancelledBy;
  final DateTime? cancelledAt;

  AppAlert({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.payload,
    required this.timestamp,
    this.senderName,
    this.sosStatus,
    this.cancelledBy,
    this.cancelledAt,
  });

  factory AppAlert.fromMap(Map<String, dynamic> map, String id) => AppAlert(
        id: id,
        groupId: map['groupId'] ?? '',
        senderId: map['senderId'] ?? '',
        receiverId: map['receiverId'] ?? 'all',
        type: map['type'] ?? '',
        payload: map['payload'] ?? '',
        timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        senderName: map['senderName'],
        sosStatus: map['sosStatus'],
        cancelledBy: map['cancelledBy'],
        cancelledAt: (map['cancelledAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'senderId': senderId,
        'receiverId': receiverId,
        'type': type,
        'payload': payload,
        'timestamp': Timestamp.fromDate(timestamp),
        'senderName': senderName,
        'sosStatus': sosStatus,
        'cancelledBy': cancelledBy,
        'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
      };

  bool get isMedia => type == 'photo' || type == 'audio';
  bool get isSOS => type == 'SOS';
  bool get isSOSActive => isSOS && sosStatus == 'active';
}

class GeofenceZone {
  final double lat;
  final double lng;
  final double radiusMeters;
  final String name;

  GeofenceZone({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.name,
  });

  factory GeofenceZone.fromMap(Map<String, dynamic> map) => GeofenceZone(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        radiusMeters: (map['radiusMeters'] as num).toDouble(),
        name: map['name'] ?? 'Zona',
      );

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'radiusMeters': radiusMeters,
        'name': name,
      };
}

/// Un boton de mensaje rapido configurable: tiene un titulo corto (lo que
/// se ve en el boton) y el mensaje real que se envia al grupo/miembro.
class QuickMessageItem {
  final String title;
  final String message;

  const QuickMessageItem({required this.title, required this.message});

  factory QuickMessageItem.fromMap(Map<String, dynamic>? map, QuickMessageItem fallback) {
    if (map == null) return fallback;
    final title = (map['title'] as String?)?.trim();
    final message = (map['message'] as String?)?.trim();
    return QuickMessageItem(
      title: (title == null || title.isEmpty) ? fallback.title : title,
      message: (message == null || message.isEmpty) ? fallback.message : message,
    );
  }

  Map<String, dynamic> toMap() => {'title': title, 'message': message};
}

/// Configuracion de los botones de mensaje fijo de un grupo. Se guarda en
/// Firestore en `groups/{groupId}/config/quickMessages` y la cargan los
/// miembros cuando la app esta en primer plano (ver groupQuickMessagesProvider).
class QuickMessagesConfig {
  // Modo "Todos": 4 botones preestablecidos y configurables.
  // FIX 2026-08-09: antes eran 3 + un 4to boton fijo "(...)" de mensaje
  // manual, que duplicaba al "(...)" del bento lateral (siempre visible,
  // arriba del boton "WP"). Se saco ese duplicado y el 4to lugar ahora es
  // un boton rapido configurable mas (ver Configuracion > Mensajes Rapidos).
  final List<QuickMessageItem> allButtons;
  // Modo "miembro seleccionado": 3 preguntas (arriba) + 3 respuestas (abajo).
  final List<QuickMessageItem> questionButtons;
  final List<QuickMessageItem> answerButtons;

  const QuickMessagesConfig({
    required this.allButtons,
    required this.questionButtons,
    required this.answerButtons,
  });

  static const defaultConfig = QuickMessagesConfig(
    allButtons: [
      QuickMessageItem(title: 'Llegue', message: 'Llegue bien'),
      QuickMessageItem(title: 'Todo bien', message: 'Todo bien por aca'),
      QuickMessageItem(title: 'Volviendo', message: 'Estoy volviendo'),
      QuickMessageItem(title: 'Emergencia', message: 'Necesito ayuda, comunicate conmigo'),
    ],
    questionButtons: [
      QuickMessageItem(title: 'Llamame', message: 'Llamame por favor'),
      QuickMessageItem(title: 'Llegaste?', message: 'Ya llegaste?'),
      QuickMessageItem(title: 'Todo bien?', message: 'Esta todo bien?'),
    ],
    answerButtons: [
      QuickMessageItem(title: 'Volve', message: 'Volve pronto'),
      QuickMessageItem(title: 'Donde estas?', message: 'Donde estas?'),
      QuickMessageItem(title: 'Ya salgo', message: 'Ya salgo para alla'),
    ],
  );

  factory QuickMessagesConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaultConfig;
    List<QuickMessageItem> parseList(String key, List<QuickMessageItem> fallbackList) {
      final raw = map[key];
      if (raw is! List) return fallbackList;
      return List.generate(fallbackList.length, (i) {
        final item = i < raw.length ? raw[i] as Map<String, dynamic>? : null;
        return QuickMessageItem.fromMap(item, fallbackList[i]);
      });
    }

    return QuickMessagesConfig(
      allButtons: parseList('allButtons', defaultConfig.allButtons),
      questionButtons: parseList('questionButtons', defaultConfig.questionButtons),
      answerButtons: parseList('answerButtons', defaultConfig.answerButtons),
    );
  }

  Map<String, dynamic> toMap() => {
        'allButtons': allButtons.map((e) => e.toMap()).toList(),
        'questionButtons': questionButtons.map((e) => e.toMap()).toList(),
        'answerButtons': answerButtons.map((e) => e.toMap()).toList(),
      };
}

/// Estado de conexion/tracking de un dispositivo, reportado por la propia
/// app (primer plano o el servicio de background) cada vez que graba un
/// punto o simplemente "late". Permite al admin ver en Configuracion >
/// Estado de Miembros si un miembro sigue activo, en que modo, y con que
/// configuracion -- y diagnosticar remotamente por que dejo de reportar
/// (permiso de ubicacion en 2do plano no otorgado, optimizacion de bateria
/// activa, etc.) sin necesitar acceso fisico a su telefono.
class DeviceStatus {
  final String uid;
  final String groupId;
  final String appState; // 'foreground' | 'background'
  final bool batterySaver;
  final bool backgroundLocationGranted;
  final bool batteryOptimizationIgnored;
  final int trackingIntervalMinutes;
  final DateTime? updatedAt;

  DeviceStatus({
    required this.uid,
    required this.groupId,
    required this.appState,
    required this.batterySaver,
    required this.backgroundLocationGranted,
    required this.batteryOptimizationIgnored,
    required this.trackingIntervalMinutes,
    this.updatedAt,
  });

  factory DeviceStatus.fromMap(Map<String, dynamic> map, String uid) => DeviceStatus(
        uid: uid,
        groupId: map['groupId'] ?? '',
        appState: map['appState'] ?? 'foreground',
        batterySaver: map['batterySaver'] ?? false,
        backgroundLocationGranted: map['backgroundLocationGranted'] ?? false,
        batteryOptimizationIgnored: map['batteryOptimizationIgnored'] ?? false,
        trackingIntervalMinutes: map['trackingIntervalMinutes'] ?? 1,
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );
}

class UserSession {
  final String uid;
  final String email;
  final String displayName;
  final String? groupId;
  final String? sessionId;
  final DateTime lastLogin;

  UserSession({
    required this.uid,
    required this.email,
    required this.displayName,
    this.groupId,
    this.sessionId,
    required this.lastLogin,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        uid: json['uid'] ?? '',
        email: json['email'] ?? '',
        displayName: json['displayName'] ?? '',
        groupId: json['groupId'],
        sessionId: json['sessionId'],
        lastLogin: DateTime.parse(json['lastLogin'] ?? DateTime.now().toIso8601String()),
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'groupId': groupId,
        'sessionId': sessionId,
        'lastLogin': lastLogin.toIso8601String(),
      };
}

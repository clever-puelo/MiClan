import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String role;
  final String currentRole;
  final String? groupId;
  final String? fcmToken;

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.currentRole,
    this.groupId,
    this.fcmToken,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) => AppUser(
        uid: uid,
        email: map['email'] ?? '',
        displayName: map['displayName'] ?? map['email']?.split('@')[0] ?? 'Usuario',
        role: map['role'] ?? 'miembro',
        currentRole: map['currentRole'] ?? 'miembro',
        groupId: map['groupId'],
        fcmToken: map['fcmToken'],
      );

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'role': role,
        'currentRole': currentRole,
        'groupId': groupId,
        'fcmToken': fcmToken,
      };
}

class AppGroup {
  final String id;
  final String name;
  final String joinCode;
  final String ownerId;

  AppGroup({required this.id, required this.name, required this.joinCode, required this.ownerId});

  factory AppGroup.fromMap(Map<String, dynamic> map, String id) => AppGroup(
        id: id,
        name: map['name'] ?? '',
        joinCode: map['joinCode'] ?? '',
        ownerId: map['ownerId'] ?? '',
      );
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

  AppAlert({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.payload,
    required this.timestamp,
    this.senderName,
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
      );

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'senderId': senderId,
        'receiverId': receiverId,
        'type': type,
        'payload': payload,
        'timestamp': Timestamp.fromDate(timestamp),
        'notified': false,
      };

  bool get isMedia => type == 'photo' || type == 'audio';
}

class GeofenceZone {
  final double lat;
  final double lng;
  final double radiusMeters;
  final String name;

  GeofenceZone({required this.lat, required this.lng, required this.radiusMeters, required this.name});

  factory GeofenceZone.fromMap(Map<String, dynamic> map) => GeofenceZone(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        radiusMeters: (map['radiusMeters'] as num).toDouble(),
        name: map['name'] ?? 'Zona',
      );

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng, 'radiusMeters': radiusMeters, 'name': name};
}

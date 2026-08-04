import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String? groupId;
  final String? fcmToken;
  final String? sessionId;
  final DateTime? createdAt;

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.groupId,
    this.fcmToken,
    this.sessionId,
    this.createdAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) => AppUser(
        uid: uid,
        email: map['email'] ?? '',
        displayName: map['displayName'] ?? 'Usuario',
        groupId: map['groupId'],
        fcmToken: map['fcmToken'],
        sessionId: map['sessionId'],
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'groupId': groupId,
        'fcmToken': fcmToken,
        'sessionId': sessionId,
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

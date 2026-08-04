import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/app_models.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  Future<String> createGroup(String name, String ownerId) async {
    final code = _generateCode();
    final ref = await _db.collection('groups').add({
      'name': name,
      'joinCode': code,
      'ownerId': ownerId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('users').doc(ownerId).update({
      'groupId': ref.id,
      'role': 'central',
      'currentRole': 'central',
    });
    return ref.id;
  }

  Future<AppGroup?> joinGroup(String code, String uid) async {
    final snap = await _db
        .collection('groups')
        .where('joinCode', isEqualTo: code)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final group = AppGroup.fromMap(snap.docs.first.data(), snap.docs.first.id);

    // FIX: Resetear rol al unirse a un grupo nuevo
    await _db.collection('users').doc(uid).update({
      'groupId': group.id,
      'currentRole': 'miembro',
    });
    return group;
  }

  Stream<AppGroup?> getGroupStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists ? AppGroup.fromMap(doc.data()!, doc.id) : null);
  }

  Stream<List<AppUser>> getGroupMembersStream(String groupId) {
    return _db
        .collection('users')
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => AppUser.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<void> leaveGroup(String uid) async {
    await _db.collection('users').doc(uid).update({
      'groupId': FieldValue.delete(),
      'currentRole': 'miembro',
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(
      6,
      (_) => chars[DateTime.now().microsecond % chars.length],
    ).join();
  }

  Future<void> updateLocation(
    String uid,
    String groupId,
    double lat,
    double lng,
  ) async {
    await _db.collection('locations').doc(uid).set({
      'groupId': groupId,
      'lat': lat,
      'lng': lng,
      'timestamp': FieldValue.serverTimestamp(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Stream<LatLng?> getLocationStream(String uid) {
    return _db.collection('locations').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      return LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      );
    });
  }

  Future<void> sendAlert(
    AppUser sender,
    String receiverId,
    String type,
    String payload,
  ) async {
    if (sender.groupId == null) return;
    await _db.collection('alerts').add({
      'groupId': sender.groupId,
      'senderId': sender.uid,
      'receiverId': receiverId,
      'type': type,
      'payload': payload,
      'senderName': sender.displayName,
      'timestamp': FieldValue.serverTimestamp(),
      'notified': false,
    });
  }

  Stream<List<AppAlert>> getGroupAlertsStream(String groupId) {
    return _db
        .collection('alerts')
        .where('groupId', isEqualTo: groupId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => AppAlert.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<void> updateUserRole(String uid, String newRole) async {
    await _db.collection('users').doc(uid).update({'currentRole': newRole});
  }

  Future<void> saveGeofence(String groupId, GeofenceZone zone) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('geofence')
        .doc('main')
        .set(zone.toMap());
  }

  Stream<GeofenceZone?> getGeofenceStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('geofence')
        .doc('main')
        .snapshots()
        .map(
          (doc) => doc.exists ? GeofenceZone.fromMap(doc.data()!) : null,
        );
  }

  Future<void> deleteGeofence(String groupId) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('geofence')
        .doc('main')
        .delete();
  }
}

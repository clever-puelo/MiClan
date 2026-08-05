import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/app_models.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  Future<AppGroup> createGroup(String name, String ownerId) async {
    final code = _generateCode();
    final ref = await _db.collection('groups').add({
      'name': name.trim(),
      'joinCode': code,
      'ownerId': ownerId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('users').doc(ownerId).update({'groupId': ref.id});
    return AppGroup(id: ref.id, name: name.trim(), joinCode: code, ownerId: ownerId);
  }

  Future<bool> requestJoinGroup(String code, String uid, String displayName) async {
    final snap = await _db
        .collection('groups')
        .where('joinCode', isEqualTo: code.toUpperCase())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return false;

    final groupId = snap.docs.first.id;
    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.data()?['groupId'] == groupId) return false;

    await _db
        .collection('groups')
        .doc(groupId)
        .collection('pendingRequests')
        .doc(uid)
        .set({
      'uid': uid,
      'displayName': displayName,
      'requestedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
    return true;
  }

  Future<void> approveRequest(String groupId, String requestUid) async {
    await _db.collection('users').doc(requestUid).update({'groupId': groupId});
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('pendingRequests')
        .doc(requestUid)
        .update({'status': 'approved'});
  }

  Future<void> rejectRequest(String groupId, String requestUid) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('pendingRequests')
        .doc(requestUid)
        .update({'status': 'rejected'});
  }

  Future<void> removeMember(String groupId, String memberUid, String adminName) async {
    await _db.collection('users').doc(memberUid).update({
      'groupId': FieldValue.delete(),
    });
    await _db.collection('alerts').add({
      'groupId': groupId,
      'senderId': 'system',
      'receiverId': 'all',
      'type': 'system',
      'payload': 'Miembro expulsado por $adminName',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> leaveGroup(String uid, String? groupId, bool isOwner) async {
    if (groupId == null) return;
    if (isOwner) await _deleteGroup(groupId);
    await _db.collection('users').doc(uid).update({
      'groupId': FieldValue.delete(),
    });
  }

  Future<void> _deleteGroup(String groupId) async {
    final pending = await _db
        .collection('groups')
        .doc(groupId)
        .collection('pendingRequests')
        .get();
    for (final d in pending.docs) await d.reference.delete();

    await _db
        .collection('groups')
        .doc(groupId)
        .collection('geofence')
        .doc('main')
        .delete();

    QuerySnapshot? alertsSnap;
    do {
      alertsSnap = await _db
          .collection('alerts')
          .where('groupId', isEqualTo: groupId)
          .limit(500)
          .get();
      final batch = _db.batch();
      for (final d in alertsSnap.docs) batch.delete(d.reference);
      await batch.commit();
    } while (alertsSnap.docs.isNotEmpty);

    final members = await _db
        .collection('users')
        .where('groupId', isEqualTo: groupId)
        .get();
    for (final m in members.docs) {
      await _db.collection('locations').doc(m.id).delete();
    }

    await _db.collection('groups').doc(groupId).delete();
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
        .map((snap) => snap.docs.map((d) => AppUser.fromMap(d.data(), d.id)).toList());
  }

  Stream<List<PendingRequest>> getPendingRequestsStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('pendingRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((d) => PendingRequest.fromMap(d.data(), d.id)).toList());
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

  /// Guarda la alerta en Firestore. La Cloud Function se encarga del envio push.
  Future<String> sendAlert(
    AppUser sender,
    String receiverId,
    String type,
    String payload, {
    String? senderName,
  }) async {
    if (sender.groupId == null) return '';

    final doc = await _db.collection('alerts').add({
      'groupId': sender.groupId,
      'senderId': sender.uid,
      'receiverId': receiverId,
      'type': type,
      'payload': payload,
      'senderName': senderName ?? sender.displayName,
      'timestamp': FieldValue.serverTimestamp(),
      'sosStatus': type == 'SOS' ? 'active' : null,
    });

    await _rotateAlerts(sender.groupId!);
    return doc.id;
  }

  Future<void> cancelSOS(String groupId, String alertId, String cancelledByUid) async {
    await _db.collection('alerts').doc(alertId).update({
      'sosStatus': 'cancelled',
      'cancelledBy': cancelledByUid,
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _rotateAlerts(String groupId) async {
    final snap = await _db
        .collection('alerts')
        .where('groupId', isEqualTo: groupId)
        .orderBy('timestamp', descending: false)
        .get();
    if (snap.docs.length > 300) {
      final toDelete = snap.docs.length - 300;
      final batch = _db.batch();
      for (int i = 0; i < toDelete && i < snap.docs.length; i++) {
        batch.delete(snap.docs[i].reference);
      }
      await batch.commit();
    }
  }

  Stream<List<AppAlert>> getGroupAlertsStream(String groupId) {
    return _db
        .collection('alerts')
        .where('groupId', isEqualTo: groupId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppAlert.fromMap(d.data(), d.id)).toList());
  }

  Stream<AppAlert?> getActiveSOSStream(String groupId) {
    return _db
        .collection('alerts')
        .where('groupId', isEqualTo: groupId)
        .where('type', isEqualTo: 'SOS')
        .where('sosStatus', isEqualTo: 'active')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty
            ? AppAlert.fromMap(snap.docs.first.data(), snap.docs.first.id)
            : null);
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
        .map((doc) => doc.exists ? GeofenceZone.fromMap(doc.data()!) : null);
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

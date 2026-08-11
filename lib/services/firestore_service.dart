import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/app_models.dart';
import 'stream_retry.dart';

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

  // FIX 2026-08-10: envueltos en selfHealingStream. Son los dos streams
  // que, junto con currentUserStream, alimentan la pantalla principal; si
  // pegan un "permission-denied" transitorio (arranque en frio justo
  // despues de otorgar el permiso de GPS, con el token todavia
  // propagando), se reintentan solos cada 2s en vez de dejar la pantalla
  // pegada en el error esperando que el usuario presione "Reintentar".
  Stream<AppGroup?> getGroupStream(String groupId) {
    return selfHealingStream(() => _db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists ? AppGroup.fromMap(doc.data()!, doc.id) : null));
  }

  Stream<List<AppUser>> getGroupMembersStream(String groupId) {
    return selfHealingStream(() => _db
        .collection('users')
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppUser.fromMap(d.data(), d.id)).toList()));
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

  /// Sube la posicion actual (para el mapa en tiempo real) y, salvo que se
  /// indique lo contrario, agrega un punto al historial ("caja negra").
  ///
  /// FIX: `recordHistory` permite que quien llama (LocationService) decida
  /// no grabar un nuevo punto de historial cuando la ubicacion es identica
  /// a la ultima registrada, evitando llenar la caja negra de puntos
  /// duplicados mientras el usuario esta quieto.
  Future<void> updateLocation(
    String uid,
    String groupId,
    double lat,
    double lng, {
    bool recordHistory = true,
  }) async {
    final now = DateTime.now();
    final data = {
      'groupId': groupId,
      'lat': lat,
      'lng': lng,
      'timestamp': FieldValue.serverTimestamp(),
      'updatedAt': now.toIso8601String(),
    };

    // Ubicación actual (para el mapa en tiempo real)
    await _db.collection('locations').doc(uid).set(data, SetOptions(merge: true));

    if (recordHistory) {
      // Guardar en historial para la caja negra del admin
      await _db.collection('locations').doc(uid).collection('history').add({
        'groupId': groupId,
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
        'recordedAt': now.toIso8601String(),
      });
    }
  }

  /// "Latido" liviano: solo refresca el timestamp de la ubicacion actual
  /// (para que el resto del grupo sepa que el usuario sigue conectado / en
  /// el mismo lugar) sin crear un nuevo punto en el historial. Se usa en la
  /// sincronizacion forzada cada 30s cuando la posicion no cambio.
  Future<void> touchLocation(String uid, String groupId) async {
    await _db.collection('locations').doc(uid).set({
      'groupId': groupId,
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

  /// NUEVO: Obtener historial de ubicaciones de un miembro desde una fecha.
  Stream<List<Map<String, dynamic>>> getLocationHistoryStream(String uid, DateTime since) {
    return _db
        .collection('locations')
        .doc(uid)
        .collection('history')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
          final data = d.data();
          data['docId'] = d.id;
          return data;
        }).toList());
  }

  /// NUEVO: historial de un miembro acotado a un rango [desde, hasta], para
  /// los sliders de muestreo de la ventana de recorrido.
  Stream<List<Map<String, dynamic>>> getLocationHistoryRangeStream(
    String uid,
    DateTime desde,
    DateTime hasta, {
    bool descending = false,
  }) {
    return _db
        .collection('locations')
        .doc(uid)
        .collection('history')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(hasta))
        .orderBy('timestamp', descending: descending)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
          final data = d.data();
          data['docId'] = d.id;
          return data;
        }).toList());
  }

  // ==========================================================================
  // MENSAJES RAPIDOS CONFIGURABLES (admin)
  // ==========================================================================

  Future<void> saveQuickMessages(String groupId, QuickMessagesConfig config) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('config')
        .doc('quickMessages')
        .set({...config.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  Stream<QuickMessagesConfig> getQuickMessagesStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('config')
        .doc('quickMessages')
        .snapshots()
        .map((doc) => QuickMessagesConfig.fromMap(doc.data()));
  }

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
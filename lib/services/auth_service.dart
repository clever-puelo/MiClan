import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_models.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<File> get _sessionFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user_session.json');
  }

  Future<UserSession?> getLocalSession() async {
    try {
      final file = await _sessionFile;
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return UserSession.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocalSession(UserSession session) async {
    final file = await _sessionFile;
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  Future<void> clearLocalSession() async {
    try {
      final file = await _sessionFile;
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  String _generateSessionId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(16, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  Stream<AppUser?> get currentUserStream {
    return _auth.authStateChanges().asyncExpand((fbUser) {
      if (fbUser == null) return Stream.value(null);
      return _db.collection('users').doc(fbUser.uid).snapshots().map((doc) {
        if (!doc.exists || doc.data() == null) return null;
        return AppUser.fromMap(doc.data()!, fbUser.uid);
      });
    });
  }

  Future<AppUser> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );
    final doc = await _db.collection('users').doc(cred.user!.uid).get();
    if (!doc.exists || doc.data() == null) {
      throw Exception('Usuario no encontrado en base de datos');
    }
    final user = AppUser.fromMap(doc.data()!, cred.user!.uid);

    // Generar sessionId unico para este dispositivo
    final sessionId = _generateSessionId();
    await _db.collection('users').doc(user.uid).update({'sessionId': sessionId});

    await saveLocalSession(UserSession(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      groupId: user.groupId,
      sessionId: sessionId,
      lastLogin: DateTime.now(),
    ));
    return user;
  }

  Future<AppUser> signUp({
    required String email,
    required String displayName,
    required String password,
  }) async {
    if (displayName.trim().length > 10) {
      throw Exception('El nombre debe tener maximo 10 caracteres');
    }
    if (password.trim().length != 6 || int.tryParse(password.trim()) == null) {
      throw Exception('La contrasena debe ser un numero de 6 digitos');
    }
    final cleanEmail = email.trim().toLowerCase();
    final cred = await _auth.createUserWithEmailAndPassword(
      email: cleanEmail,
      password: password.trim(),
    );
    final user = AppUser(
      uid: cred.user!.uid,
      email: cleanEmail,
      displayName: displayName.trim(),
    );
    await _db.collection('users').doc(cred.user!.uid).set(user.toMap());
    await _auth.signOut();
    return user;
  }

  Future<void> signOut() async {
    await clearLocalSession();
    await _auth.signOut();
  }

  Future<void> deleteAccount(String uid) async {
    await _db.collection('users').doc(uid).delete();
    await clearLocalSession();
    await _auth.currentUser?.delete();
  }

  Future<void> updateFcmToken(String uid, String token) async {
    await _db.collection('users').doc(uid).update({'fcmToken': token});
  }

  Future<void> updateGroupId(String uid, String? groupId) async {
    await _db.collection('users').doc(uid).update({'groupId': groupId});
    final session = await getLocalSession();
    if (session != null) {
      await saveLocalSession(UserSession(
        uid: session.uid,
        email: session.email,
        displayName: session.displayName,
        groupId: groupId,
        sessionId: session.sessionId,
        lastLogin: DateTime.now(),
      ));
    }
  }
}

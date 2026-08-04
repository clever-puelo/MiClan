import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_models.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String _emailFromName(String name) {
    final clean = name.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return '\${clean}@miclan.local';
  }

  Stream<AppUser?> get currentUserStream {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(null);
      return _db.collection('users').doc(user.uid).snapshots().map((doc) {
        if (!doc.exists || doc.data() == null) {
          final newUser = AppUser(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName ?? 'Usuario',
            role: 'miembro',
            currentRole: 'miembro',
          );
          _db.collection('users').doc(user.uid).set(newUser.toMap());
          return newUser;
        }
        return AppUser.fromMap(doc.data()!, user.uid);
      });
    });
  }

  Future<AppUser> signIn(String name, String pin) async {
    final email = _emailFromName(name);
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: pin);
    final doc = await _db.collection('users').doc(cred.user!.uid).get();
    if (!doc.exists || doc.data() == null) {
      final user = AppUser(
        uid: cred.user!.uid,
        email: email,
        displayName: name.trim(),
        role: 'miembro',
        currentRole: 'miembro',
      );
      await _db.collection('users').doc(cred.user!.uid).set(user.toMap());
      return user;
    }
    return AppUser.fromMap(doc.data()!, cred.user!.uid);
  }

  Future<AppUser> signUp(String name, String pin) async {
    final email = _emailFromName(name);
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: pin);
    final user = AppUser(
      uid: cred.user!.uid,
      email: email,
      displayName: name.trim(),
      role: 'miembro',
      currentRole: 'miembro',
    );
    await _db.collection('users').doc(cred.user!.uid).set(user.toMap());
    return user;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> updateFcmToken(String uid, String token) async {
    await _db.collection('users').doc(uid).update({'fcmToken': token});
  }
}

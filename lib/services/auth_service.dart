import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_models.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Stream<AppUser> get currentUserStream {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) throw Exception('No autenticado');
      final doc = await _db.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        final newUser = AppUser(uid: user.uid, email: user.email ?? '', role: 'miembro', currentRole: 'miembro');
        await _db.collection('users').doc(user.uid).set(newUser.toMap());
        return newUser;
      }
      return AppUser.fromMap(doc.data()!, user.uid);
    });
  }

  Future<AppUser> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    final doc = await _db.collection('users').doc(cred.user!.uid).get();
    return AppUser.fromMap(doc.data()!, cred.user!.uid);
  }

  Future<AppUser> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final user = AppUser(uid: cred.user!.uid, email: email, role: 'miembro', currentRole: 'miembro');
    await _db.collection('users').doc(cred.user!.uid).set(user.toMap());
    return user;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> updateFcmToken(String uid, String token) async {
    await _db.collection('users').doc(uid).update({'fcmToken': token});
  }
}
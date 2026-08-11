import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_models.dart';
import 'stream_retry.dart';

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

  // FIX 2026-08-09 (causa raiz real del "permission-denied" tras el primer
  // login, no cubierta por el fix anterior en signIn()/signUp()):
  //
  // El fix de la seccion 10.1 del informe (getIdToken(true) + delay de
  // 300ms) protege unicamente las escrituras que hace signIn()/signUp() en
  // su propio cuerpo (guardar sessionId). Pero `authStateChanges()` emite
  // el nuevo usuario de forma independiente y practicamente al mismo
  // tiempo que Firebase termina el login -- ANTES de que ese delay interno
  // de signIn() llegue a completarse. Como currentUserStream (esta funcion)
  // se arma directo sobre authStateChanges(), y de ella cuelgan TODOS los
  // demas listeners de la app (currentUserProvider -> currentGroupProvider
  // -> groupMembersProvider, groupQuickMessagesProvider, activeSOSProvider,
  // ademas de _saveFcmToken en main.dart y el primer write de ubicacion en
  // cuanto HomeScreen consigue el permiso de GPS), esos listeners se
  // suscribian a Firestore ANTES de que el token nuevo terminara de
  // propagarse del lado del servidor, y podian quedar con
  // "permission-denied".
  //
  // Ademas, un StreamProvider de Riverpod que recibe un error en su stream
  // NO se reintenta solo: queda pegado en AsyncValue.error hasta que se
  // recrea el provider (cerrar y reabrir la app, o loguearse de nuevo) --
  // por eso el sintoma exacto reportado ("cerrar la app y volver a
  // cargarla, pide login de nuevo y ahi anda bien").
  //
  // Fix real: esperar a que el token este fresco (mismo mecanismo que ya
  // se usaba en signIn/signUp) ANTES de suscribirse al doc de Firestore
  // aca, en el unico punto de origen de todos esos listeners. Asi ningun
  // Provider llega a tocar Firestore hasta que el token ya propago.
  // FIX 2026-08-10: la suscripción al doc de Firestore va envuelta en
  // selfHealingStream. Si igual llega a pegarle a un "permission-denied"
  // transitorio (el token recien refrescado por _ensureFreshToken todavia
  // no termino de propagar del lado del servidor), se reintenta sola cada
  // 2s en vez de dejar a currentUserProvider pegado en error esperando que
  // el usuario presione "Reintentar".
  //
  // FIX 2026-08-10 (segunda vuelta): "sigue pidiendo login despues de
  // Reintentar". Causa real: cada vez que se invalidaba currentUserProvider
  // (el boton Reintentar, o Riverpod recreando el provider por cualquier
  // motivo), esta funcion volvia a ejecutar _ensureFreshToken DESDE CERO:
  // un refresh de token forzado contra el servidor (getIdToken(true), hasta
  // 5s) + 300ms de espera fija. Ese refresh solo hace falta UNA vez, recien
  // despues del login real (cuando el token puede no haber propagado
  // todavia) -- no en cada reintento del MISMO usuario ya logueado, cuyo
  // token ya esta perfectamente vigente. `_tokenEnsuredForUid` recuerda
  // para que uid ya se hizo ese refresh en esta sesión de la app, asi un
  // reintento contra el mismo usuario se reconecta directo a Firestore, sin
  // el refresh ni la demora (que es lo que se sentia como "otro login").
  String? _tokenEnsuredForUid;

  Stream<AppUser?> get currentUserStream {
    return _auth.authStateChanges().asyncExpand((fbUser) {
      if (fbUser == null) {
        _tokenEnsuredForUid = null; // logout: el proximo login si necesita el refresh
        return Stream.value(null);
      }
      final needsFreshToken = _tokenEnsuredForUid != fbUser.uid;
      final ready = needsFreshToken
          ? Stream.fromFuture(_ensureFreshToken(fbUser).then((_) => _tokenEnsuredForUid = fbUser.uid))
          : Stream<void>.value(null);
      return ready.asyncExpand((_) {
        return selfHealingStream(() => _db.collection('users').doc(fbUser.uid).snapshots().map((doc) {
              if (!doc.exists || doc.data() == null) return null;
              return AppUser.fromMap(doc.data()!, fbUser.uid);
            }));
      });
    });
  }

  Future<void> _ensureFreshToken(User fbUser) async {
    try {
      await fbUser.getIdToken(true).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Sin red / timeout: seguimos igual, mejor arrancar con el token que
      // haya (o sin el) que dejar la app colgada esperando para siempre.
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<AppUser> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );

    // FIX 2026-08-09 (mismo problema que ya se habia resuelto en signUp):
    // en una instalacion nueva del telefono, el SDK de Firestore arranca
    // "frio" (sin cache/persistencia previa) y el token de ID recien
    // emitido por signInWithEmailAndPassword puede tardar unos ms en
    // propagarse. Si el usuario llega a la pantalla principal y se
    // disparan escrituras a Firestore (sessionId, token FCM, ubicacion en
    // cuanto se otorga el permiso de GPS) antes de que eso termine, las
    // reglas de seguridad las rechazan con "permission-denied". Forzar un
    // refresh del token y esperar un instante antes de seguir evita la
    // carrera. Esto explica el bug donde, recien instalada la app, un
    // miembro no-admin veia el error de permisos justo despues de aceptar
    // el permiso de ubicacion (y al reabrir la app ya andaba, porque para
    // ese momento el token ya habia terminado de propagarse).
    await cred.user!.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 300));

    final doc = await _db.collection('users').doc(cred.user!.uid).get();
    if (!doc.exists || doc.data() == null) {
      throw Exception('Usuario no encontrado en base de datos');
    }
    final user = AppUser.fromMap(doc.data()!, cred.user!.uid);

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
      throw Exception('El nombre debe tener máximo 10 caracteres');
    }
    if (password.trim().length != 6 || int.tryParse(password.trim()) == null) {
      throw Exception('La contraseña debe ser un número de 6 digitos');
    }
    final cleanEmail = email.trim().toLowerCase();
    final cred = await _auth.createUserWithEmailAndPassword(
      email: cleanEmail,
      password: password.trim(),
    );

    // FIX PERMISOS: Forzar refresh del token de ID antes de escribir en Firestore.
    // Firebase Auth tarda unos ms en propagar el token despues de createUser.
    // Sin esto, Firestore Rules rechaza la escritura con "permission-denied".
    await cred.user!.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 300));

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

  /// Guarda el teléfono del propio usuario (se usa para el enlace directo a
  /// WhatsApp "WP" desde el mapa principal).
  Future<void> updatePhone(String uid, String? phone) async {
    await _db.collection('users').doc(uid).update({'phone': phone});
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
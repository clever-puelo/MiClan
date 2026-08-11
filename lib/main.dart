import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'models/app_models.dart';
import 'providers/app_providers.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/notification_service.dart';
import 'services/background_location_service.dart';

// ============================================================================
// BACKGROUND HANDLER - FCM
// Se ejecuta cuando llega un push con la app cerrada o en background.
// FIX 2026-08-07: Ahora lee title/body de message.data (payload data-only).
// FCM nativo NO muestra notificación automática porque no hay campo
// 'notification' en el payload. Solo este handler muestra la local.
// ============================================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();
  final channelId = message.data['channelId'] ?? 'msg_channel';
  await NotificationService.showLocalNotification(
    title: message.data['title'] ?? 'MiClan',
    body: message.data['body'] ?? '',
    channelId: channelId,
    // ID fijo para SOS: evita que se acumulen notificaciones duplicadas en
    // la barra si llegan varios pushes de la misma alerta de pánico.
    id: channelId == 'sos_channel' ? 9999 : 0,
  );
}

class AppColors {
  static const Color background = Color(0xFF273758);
  static const Color modalBg = Color(0xFF3A4A66);
  static const Color cardGlass = Color(0x0DFFFFFF);
  static const Color borderGlass = Color(0x1AFFFFFF);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentGreen = Color(0xFF22C55E);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentAmber = Color(0xFFF59E0B);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // FCM background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await NotificationService.init();

  // FIX 2026-08-10: registra (sin arrancar) el servicio nativo de Android
  // que graba la caja negra con la app en segundo plano o el telefono
  // dormido. Se arranca/detiene desde HomeScreen segun el ciclo de vida
  // de la app (ver background_location_service.dart).
  await BackgroundLocationService.initialize();

  // ==========================================================================
  // FIX 2026-08-08: pedir el permiso de notificaciones UNA sola vez, aca en
  // el arranque, completamente ANTES de mostrar cualquier pantalla y ANTES
  // de que HomeScreen pueda llegar a pedir el permiso de ubicación.
  //
  // El bug reportado ("aparece el permiso de notificaciones, y luego de
  // permitir, queda colgada") es un problema conocido de Android/Flutter:
  // si dos plugins distintos piden un permiso runtime casi al mismo tiempo
  // (por ejemplo, firebase_messaging pidiendo POST_NOTIFICATIONS mientras
  // HomeScreen recien montado pide ACCESS_FINE_LOCATION), el dialogo del
  // segundo permiso puede pisar el callback nativo del primero y dejar ese
  // primer Future esperando una respuesta que nunca llega: la app se
  // "cuelga" en el loader, aunque el usuario haya tocado "Permitir".
  //
  // Al pedirlo aca, de forma secuencial y totalmente resuelto (con timeout
  // de seguridad) antes de "runApp", se garantiza que cuando el usuario
  // llegue a Home no haya ningun otro dialogo de permiso en vuelo.
  // ==========================================================================
  try {
    await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true)
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    // Si el usuario no responde o el plugin falla, seguimos igual: la app
    // debe poder arrancar sin notificaciones en vez de quedar colgada.
  }

  runApp(const ProviderScope(child: MiClanApp()));
}

class MiClanApp extends ConsumerStatefulWidget {
  const MiClanApp({super.key});
  @override
  ConsumerState<MiClanApp> createState() => _MiClanAppState();
}

class _MiClanAppState extends ConsumerState<MiClanApp> {
  GoRouter? _router;
  final _authListener = ValueNotifier<AsyncValue<AppUser?>>(const AsyncValue.loading());
  bool _initialized = false;
  Timer? _sessionMismatchDebounce;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // Duracion minima de la pantalla de bienvenida (coincide con la
    // duracion de la animacion del logo: 2.8s + un margen), para que
    // permanezca 2.5-3s en pantalla como se pidio, sin importar que tan
    // rapido resuelva el resto de la inicializacion (sesion/auth).
    final splashMinDuration = Future.delayed(const Duration(milliseconds: 3000));

    // Sesión local (mirror liviano usado para detectar "sesión iniciada en
    // otro dispositivo"). NO es la fuente de verdad de la ruta inicial: eso
    // ahora lo decide siempre el estado real de Firebase Auth (ver abajo),
    // para no depender de que este archivo se haya escrito/leido a tiempo
    // tras un cierre abrupto de la app (swipe).
    final session = await ref.read(authServiceProvider).getLocalSession();

    ref.listenManual(currentUserProvider, (prev, next) async {
      _authListener.value = next;
      final user = next.value;

      if (user != null) {
        await _saveFcmToken(user.uid);
      }

      // FIX 2026-08-09: releer la sesión local ACTUAL en vez de usar la
      // variable `session` capturada al arrancar la app. Si el usuario
      // inicia sesión recién ahora (primera vez, o luego de un logout),
      // `session` seguiría siendo la vieja (o null) y podía disparar un
      // falso "sesión iniciada en otro dispositivo" que cerraba la sesión
      // sola en el siguiente arranque, obligando a loguearse de nuevo cada
      // vez en vez de solo la primera.
      //
      // FIX 2026-08-10 (causa real confirmada por logcat en dispositivo
      // real): justo despues de loguearse, el PRIMER snapshot del doc de
      // Firestore que recibe este listener puede traer todavia el
      // sessionId VIEJO (el de la sesion anterior en este mismo telefono):
      // el listener de currentUserStream ya esta suscripto al doc antes de
      // que el propio update({'sessionId': ...}) de signIn()/signUp()
      // termine de propagarse de vuelta. El archivo de sesion local, en
      // cambio, ya tiene el sessionId NUEVO (se escribe justo despues de
      // ese update). Comparar en ese instante contra ese primer snapshot
      // daba un falso "sesion iniciada en otro dispositivo" y cerraba la
      // sesion sola ~600ms despues de cada login (visto en logcat: 3
      // snapshots segudos, el 1ro con el sessionId viejo, y el signOut
      // disparado contra ese 1ro). Se soluciona esperando a que el estado
      // se "asiente" (sin snapshots nuevos por 1.5s) antes de evaluar el
      // mismatch, usando siempre el valor MAS RECIENTE en ese momento -- asi
      // un snapshot transitorio/viejo nunca llega a disparar el signOut,
      // pero una sesion realmente abierta en otro dispositivo (que no
      // cambia mas) se sigue detectando igual.
      _sessionMismatchDebounce?.cancel();
      if (user != null && user.sessionId != null) {
        _sessionMismatchDebounce = Timer(const Duration(milliseconds: 1500), () async {
          final latestUser = _authListener.value.valueOrNull;
          if (latestUser == null || latestUser.sessionId == null) return;
          final currentLocalSession = await ref.read(authServiceProvider).getLocalSession();
          if (currentLocalSession == null) return;
          if (latestUser.sessionId != currentLocalSession.sessionId) {
            await ref.read(authServiceProvider).signOut();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sesión iniciada en otro dispositivo'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        });
      }
    }, fireImmediately: true);

    // FCM foreground handler - FIX: lee de message.data
    FirebaseMessaging.onMessage.listen((message) async {
      final channelId = message.data['channelId'] ?? 'msg_channel';
      await NotificationService.showLocalNotification(
        title: message.data['title'] ?? 'MiClan',
        body: message.data['body'] ?? '',
        channelId: channelId,
        id: channelId == 'sos_channel' ? 9999 : 0,
      );
    });

    // ========================================================================
    // FIX 2026-08-08: esperar la primera resolución REAL del estado de auth
    // (con timeout de seguridad) antes de decidir la ruta inicial y recien
    // ahi construir el router. Antes, la ruta inicial se calculaba solo con
    // el archivo de sesión local; si ese archivo no llegaba a escribirse (o
    // tardaba en leerse) tras matar la app de un swipe, se mostraba un
    // "flash" de la pantalla de login aunque Firebase Auth ya tuviera la
    // sesión vigente, dando la sensación de que "a veces vuelve a pedir
    // login" antes de mostrar recien ahi el permiso de ubicación.
    // ========================================================================
    AsyncValue<AppUser?> resolved = _authListener.value;
    if (resolved.isLoading) {
      try {
        final user = await ref.read(currentUserProvider.future).timeout(const Duration(seconds: 6));
        resolved = AsyncValue.data(user);
      } catch (_) {
        // Sin red / timeout: seguimos con lo que tengamos (probablemente
        // loading todavia), el redirect de GoRouter se termina de resolver
        // solo apenas el stream de auth responda.
        resolved = _authListener.value;
      }
      _authListener.value = resolved;
    }

    String initialLocation;
    final resolvedUser = resolved.valueOrNull;
    if (resolved.isLoading) {
      // Ultimo recurso: si ni con el timeout se resolvio, usamos la sesión
      // local como mejor estimacion disponible (comportamiento anterior).
      if (session == null) {
        initialLocation = '/login';
      } else if (session.groupId == null) {
        initialLocation = '/onboarding';
      } else {
        initialLocation = '/home';
      }
    } else if (resolvedUser == null) {
      initialLocation = '/login';
    } else if (resolvedUser.groupId == null) {
      initialLocation = '/onboarding';
    } else {
      initialLocation = '/home';
    }

    _router = GoRouter(
      initialLocation: initialLocation,
      refreshListenable: _authListener,
      redirect: (context, state) {
        if (_authListener.value.isLoading) return null;
        final user = _authListener.value.value;
        final isLoggedIn = user != null;
        final hasGroup = user?.groupId != null;
        final path = state.matchedLocation;
        if (!isLoggedIn && path != '/login') return '/login';
        if (isLoggedIn && !hasGroup && path != '/onboarding') return '/onboarding';
        if (isLoggedIn && hasGroup && (path == '/login' || path == '/onboarding')) return '/home';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
        GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    );

    if (mounted) {
      await splashMinDuration;
    }
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _saveFcmToken(String uid) async {
    // FIX 2026-08-08: el permiso de notificaciones ya se pidio una sola vez
    // en main() antes de runApp; aca solo se obtiene/guarda el token, sin
    // volver a disparar el dialogo nativo (evita el race de permisos).
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null) {
        await ref.read(authServiceProvider).updateFcmToken(uid, token);
      }
      messaging.onTokenRefresh.listen((newToken) {
        ref.read(authServiceProvider).updateFcmToken(uid, newToken);
      });
    } catch (e) {
      debugPrint('Error FCM token: $e');
    }
  }

  @override
  void dispose() {
    _sessionMismatchDebounce?.cancel();
    _authListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _router == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: AppColors.background),
        home: const WelcomeScreen(),
      );
    }
    return MaterialApp.router(
      title: 'MiClan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.modalBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: AppColors.modalBg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accentBlue,
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      routerConfig: _router!,
    );
  }
}

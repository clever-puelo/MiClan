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
import 'services/notification_service.dart';

// ============================================================================
// BACKGROUND HANDLER - FCM
// Se ejecuta cuando llega un push con la app cerrada o en background.
// FIX 2026-08-07: Ahora lee title/body de message.data (payload data-only).
// FCM nativo NO muestra notificacion automatica porque no hay campo
// 'notification' en el payload. Solo este handler muestra la local.
// ============================================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();
  await NotificationService.showLocalNotification(
    title: message.data['title'] ?? 'MiClan',
    body: message.data['body'] ?? '',
    channelId: message.data['channelId'] ?? 'msg_channel',
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

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final session = await ref.read(authServiceProvider).getLocalSession();

    ref.listenManual(currentUserProvider, (prev, next) async {
      _authListener.value = next;
      final user = next.value;

      if (user != null) {
        await _saveFcmToken(user.uid);
      }

      if (user != null && session != null && user.sessionId != null) {
        if (user.sessionId != session.sessionId) {
          await ref.read(authServiceProvider).signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sesion iniciada en otro dispositivo'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    });

    // FCM foreground handler - FIX: lee de message.data
    FirebaseMessaging.onMessage.listen((message) async {
      await NotificationService.showLocalNotification(
        title: message.data['title'] ?? 'MiClan',
        body: message.data['body'] ?? '',
        channelId: message.data['channelId'] ?? 'msg_channel',
      );
    });

    String initialLocation;
    if (session == null) {
      initialLocation = '/login';
    } else if (session.groupId == null) {
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

    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _saveFcmToken(String uid) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
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
    _authListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _router == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: Center(child: CircularProgressIndicator(color: Colors.blue.shade400)),
        ),
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

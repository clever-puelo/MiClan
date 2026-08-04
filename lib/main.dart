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

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
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

      // Verificar sessionId: si otro dispositivo se logueo, forzar logout
      final user = next.value;
      if (user != null && session != null && user.sessionId != null) {
        if (user.sessionId != session.sessionId) {
          // Sesion invalidada desde otro dispositivo
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

    _setupFCM();
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _setupFCM() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    final user = ref.read(currentUserProvider).valueOrNull;
    if (token != null && user != null) {
      await ref.read(authServiceProvider).updateFcmToken(user.uid, token);
    }
    messaging.onTokenRefresh.listen((newToken) async {
      final u = ref.read(currentUserProvider).valueOrNull;
      if (u != null) await ref.read(authServiceProvider).updateFcmToken(u.uid, newToken);
    });
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
          backgroundColor: const Color(0xFF0F172A),
          body: Center(child: CircularProgressIndicator(color: Colors.blue.shade400)),
        ),
      );
    }
    return MaterialApp.router(
      title: 'MiClan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6), brightness: Brightness.dark),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      routerConfig: _router!,
    );
  }
}

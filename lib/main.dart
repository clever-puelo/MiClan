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
  late final GoRouter _router;
  final _authListener = ValueNotifier<AsyncValue<AppUser?>>(const AsyncValue.loading());

  @override
  void initState() {
    super.initState();
    _setupFCM();

    ref.listenManual(currentUserProvider, (prev, next) {
      _authListener.value = next;
    });

    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: _authListener,
      redirect: (context, state) {
        final userAsync = _authListener.value;
        final path = state.matchedLocation;

        if (userAsync.isLoading) {
          return path == '/' ? null : path;
        }

        final user = userAsync.value;
        final isLoggedIn = user != null;
        final hasGroup = user?.groupId != null;

        if (!isLoggedIn && path != '/login') return '/login';
        if (isLoggedIn && !hasGroup && path != '/onboarding') return '/onboarding';
        if (isLoggedIn && hasGroup && (path == '/login' || path == '/onboarding' || path == '/')) {
          return '/home';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/', redirect: (_, __) => '/home'),
        GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
        GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    );
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
    return MaterialApp.router(
      title: 'MiClan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6), brightness: Brightness.dark),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

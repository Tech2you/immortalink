import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'services/recent_cache.dart';
import 'services/onboarding_invite_state.dart';
import 'services/first_account_setup.dart';
import 'services/push_notification_service.dart';
import 'screens/join_family_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/vaults_screen.dart';
import 'utils/family_invite_share.dart';
import 'widgets/keyboard_dismiss_scope.dart';

const _staySignedInPreferenceKey = 'auth_stay_signed_in';
final _passwordRecoveryPending = ValueNotifier<bool>(false);
final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  await runZonedGuarded(_runApp, _handleUncaughtError);
}

Future<void> _runApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Preferred for hosted web builds (Firebase, Vercel, etc.)
  const definedUrl = String.fromEnvironment('SUPABASE_URL');
  const definedAnon = String.fromEnvironment('SUPABASE_ANON_KEY');

  String url = definedUrl.trim();
  String anon = definedAnon.trim();

  // 2) Fallback to public client config. Do not bundle .env as a Flutter asset;
  // Flutter Web assets are downloadable by anyone using the app.
  if (url.isEmpty || anon.isEmpty) {
    url = Env.supabaseUrl.trim();
    anon = Env.supabaseAnonKey.trim();
  }

  if (url.isEmpty || anon.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Missing SUPABASE_URL or SUPABASE_ANON_KEY.\n'
              'For hosted Flutter Web builds, use --dart-define.\n'
              'Example:\n'
              'flutter build web --release \\\n'
              '  --dart-define=SUPABASE_URL=... \\\n'
              '  --dart-define=SUPABASE_ANON_KEY=...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    return;
  }

  await Supabase.initialize(
    url: url,
    anonKey: anon,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await RecentCache.instance.setUser(Supabase.instance.client.auth.currentUser?.id);
  await PushNotificationService.configureMessageHandlers();

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final user = data.session?.user.id;
    if (RecentCache.instance.user != user) {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      unawaited(RecentCache.instance.setUser(user));
    }
    if (data.event == AuthChangeEvent.passwordRecovery) {
      _passwordRecoveryPending.value = true;
    } else if (data.event == AuthChangeEvent.signedOut) {
      _passwordRecoveryPending.value = false;
      unawaited(PushNotificationService.clearLocalTokenRegistration());
    }
  });

  runApp(const MyApp());
}

void _handleUncaughtError(Object error, StackTrace stackTrace) {
  if (error is AuthException && _isExpiredAuthLink(error)) {
    debugPrint('Ignored expired auth link: ${error.message}');
    return;
  }

  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'Ever Roots',
    ),
  );
}

bool _isExpiredAuthLink(AuthException error) {
  final message = error.message.toLowerCase();
  final code = error.code?.toLowerCase();
  final statusCode = error.statusCode?.toLowerCase();

  return code == 'access_denied' ||
      statusCode == 'otp_expired' ||
      message.contains('invalid or has expired');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ever Roots',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return KeyboardDismissScope(child: child ?? const SizedBox.shrink());
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _appLinks = AppLinks();
  bool _checkedSessionPreference = false;
  int _inviteLinkRevision = 0;
  String _lastHandledInviteCode = '';
  DateTime? _lastHandledInviteAt;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _enforceSessionPreference();
    _listenForInviteLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _enforceSessionPreference() async {
    final auth = Supabase.instance.client.auth;
    final prefs = await SharedPreferences.getInstance();
    final staySignedIn = prefs.getBool(_staySignedInPreferenceKey) ?? true;

    if (!staySignedIn && auth.currentSession != null) {
      await auth.signOut(scope: SignOutScope.local);
    }

    if (mounted) {
      setState(() => _checkedSessionPreference = true);
    }
  }

  void _listenForInviteLinks() {
    unawaited(_handleInitialInviteLink());
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleInviteLink,
      onError: (Object error) {
        debugPrint('Invite link listener failed: $error');
      },
    );
  }

  Future<void> _handleInitialInviteLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) await _handleInviteLink(uri);
    } catch (error) {
      debugPrint('Initial invite link failed: $error');
    }
  }

  Future<void> _handleInviteLink(Uri uri) async {
    final code = familyInviteCodeFromUri(uri);
    if (code.isEmpty) return;
    final now = DateTime.now();
    final lastHandledAt = _lastHandledInviteAt;
    if (code == _lastHandledInviteCode &&
        lastHandledAt != null &&
        now.difference(lastHandledAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastHandledInviteCode = code;
    _lastHandledInviteAt = now;

    await savePendingFamilyInviteCode(code);
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || _passwordRecoveryPending.value ||
        needsFirstAccountSetup(session.user.userMetadata)) {
      setState(() => _inviteLinkRevision++);
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => JoinFamilyScreen(initialInviteCode: code),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedSessionPreference) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final auth = Supabase.instance.client.auth;

    return ValueListenableBuilder<bool>(
      valueListenable: _passwordRecoveryPending,
      builder: (context, passwordRecoveryPending, _) {
        return StreamBuilder<AuthState>(
          stream: auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session = auth.currentSession;

            if (session == null) {
              return SignInScreen(key: ValueKey(_inviteLinkRevision));
            }

            if (passwordRecoveryPending) {
              return ResetPasswordScreen(
                onPasswordUpdated: () {
                  _passwordRecoveryPending.value = false;
                },
              );
            }

            return VaultsScreen(key: ValueKey(session.user.id));
          },
        );
      },
    );
  }
}

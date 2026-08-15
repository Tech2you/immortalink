import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'screens/reset_password_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/vaults_screen.dart';
import 'widgets/keyboard_dismiss_scope.dart';

const _staySignedInPreferenceKey = 'auth_stay_signed_in';
final _passwordRecoveryPending = ValueNotifier<bool>(false);

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

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      _passwordRecoveryPending.value = true;
    } else if (data.event == AuthChangeEvent.signedOut) {
      _passwordRecoveryPending.value = false;
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
  bool _checkedSessionPreference = false;

  @override
  void initState() {
    super.initState();
    _enforceSessionPreference();
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
              return const SignInScreen();
            }

            if (passwordRecoveryPending) {
              return ResetPasswordScreen(
                onPasswordUpdated: () {
                  _passwordRecoveryPending.value = false;
                },
              );
            }

            return const VaultsScreen();
          },
        );
      },
    );
  }
}

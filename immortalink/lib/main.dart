import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'screens/reset_password_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/vaults_screen.dart';
import 'widgets/keyboard_dismiss_scope.dart';

const _staySignedInPreferenceKey = 'auth_stay_signed_in';

Future<void> main() async {
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

  runApp(const MyApp());
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
  bool _passwordRecoveryCompleted = false;

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

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = auth.currentSession;
        final event = snapshot.data?.event;

        if (session == null) {
          _passwordRecoveryCompleted = false;
          return const SignInScreen();
        }

        if (event == AuthChangeEvent.passwordRecovery &&
            !_passwordRecoveryCompleted) {
          return ResetPasswordScreen(
            onPasswordUpdated: () {
              if (mounted) {
                setState(() => _passwordRecoveryCompleted = true);
              }
            },
          );
        }

        return const VaultsScreen();
      },
    );
  }
}

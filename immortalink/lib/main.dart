import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/sign_in_screen.dart';
import 'screens/vaults_screen.dart';
import 'widgets/keyboard_dismiss_scope.dart';

const _staySignedInPreferenceKey = 'auth_stay_signed_in';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) ✅ Preferred for hosted web builds (Firebase, Vercel, etc.)
  const definedUrl = String.fromEnvironment('SUPABASE_URL');
  const definedAnon = String.fromEnvironment('SUPABASE_ANON_KEY');

  String url = definedUrl.trim();
  String anon = definedAnon.trim();

  // 2) ✅ Fallback for local dev (flutter run) using .env
  // (This will usually NOT work on hosted web unless you specifically bundle .env as an asset.)
  if (url.isEmpty || anon.isEmpty) {
    try {
      await dotenv.load(fileName: ".env");
      url = (dotenv.env['SUPABASE_URL'] ?? '').trim();
      anon = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();
    } catch (_) {
      // ignore
    }
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
      title: 'ImmortaLink',
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

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = auth.currentSession;

        if (session == null) {
          return const SignInScreen();
        }

        return const VaultsScreen();
      },
    );
  }
}

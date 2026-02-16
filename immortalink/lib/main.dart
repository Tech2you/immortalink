import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/sign_in_screen.dart';
import 'screens/vaults_screen.dart';

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
    runApp(const MaterialApp(
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
    ));
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
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
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

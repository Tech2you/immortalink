import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/sign_in_screen.dart';
import 'screens/vaults_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  final url = (dotenv.env['SUPABASE_URL'] ?? '').trim();
  final anon = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();

  if (url.isEmpty || anon.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Missing SUPABASE_URL or SUPABASE_ANON_KEY.\n'
            'For Flutter Web, .env may not be loading.\n'
            'Fix the web env setup.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ));
    return;
  }

  await Supabase.initialize(url: url, anonKey: anon);

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

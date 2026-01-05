import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _message;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      setState(() {
        _message =
            "Account created. If email confirmation is ON, check your inbox to confirm before signing in.";
      });
    } on AuthException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = "Unexpected error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // go back to home for now
    } on AuthException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = "Unexpected error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sign In"),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password"),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Sign In"),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _isLoading ? null : _signUp,
                  child: const Text("Create Account"),
                ),

                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_chat_reminder_service.dart';

enum _AuthMode { signIn, signUp }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  _AuthMode _mode = _AuthMode.signIn;
  bool _loading = false;

  bool _hidePassword = true;
  bool _hideConfirm = true;

  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _loading = false;
        _error = 'Please enter a valid email.';
      });
      return;
    }
    if (password.isEmpty || password.length < 6) {
      setState(() {
        _loading = false;
        _error = 'Password must be at least 6 characters.';
      });
      return;
    }

    if (_mode == _AuthMode.signUp) {
      final confirm = _confirm.text;
      if (confirm != password) {
        setState(() {
          _loading = false;
          _error = 'Passwords do not match.';
        });
        return;
      }
    }

    try {
      final client = Supabase.instance.client;

      if (_mode == _AuthMode.signIn) {
        final response = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        final userId = response.user?.id;
        if (userId != null) {
          try {
            await AiChatReminderService.recordSuccessfulLogin(userId);
          } catch (_) {
            // A local reminder preference must never block a successful login.
          }
        }
        // Your app should route away via auth listener / main.dart.
      } else {
        await client.auth.signUp(email: email, password: password);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account created. If email confirmation is enabled, check your inbox.',
            ),
          ),
        );

        // After create, gently push back to Sign In (matches your sketch)
        setState(() {
          _mode = _AuthMode.signIn;
          _confirm.clear();
        });
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _error = 'Enter your email first, then tap “Forgot password?”',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // NOTE: Make sure you’ve configured your Supabase Auth redirect URL(s) in the dashboard.
      await client.auth.resetPasswordForEmail(email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent (if the account exists).'),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not send reset email. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchMode(_AuthMode next) {
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = next;
      _error = null;
      _loading = false;

      // keep email/password; clear confirm when leaving sign up
      if (_mode == _AuthMode.signIn) _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignIn = _mode == _AuthMode.signIn;
    final title = isSignIn ? 'Sign in' : 'Create account';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // This padding is what prevents keyboard overlap.
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Logo block
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: SizedBox(
                                    height: 210,
                                    child: Center(
                                      child: Transform.scale(
                                        scale: 2.35,
                                        child: Image.asset(
                                          'assets/images/immortalink_logo.png',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  'Keep your family connected — now and always.',
                                  style: Theme.of(context).textTheme.titleLarge,
                                  textAlign: TextAlign.center,
                                ),

                                const SizedBox(height: 18),

                                // Header (matches your sketch)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                TextField(
                                  controller: _email,
                                  focusNode: _emailFocus,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                ),
                                const SizedBox(height: 12),

                                TextField(
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  obscureText: _hidePassword,
                                  textInputAction: isSignIn
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                                  autofillHints: isSignIn
                                      ? const [AutofillHints.password]
                                      : const [AutofillHints.newPassword],
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: _hidePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () => setState(
                                        () => _hidePassword = !_hidePassword,
                                      ),
                                      icon: Icon(
                                        _hidePassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) {
                                    if (isSignIn) {
                                      _submit();
                                    } else {
                                      _confirmFocus.requestFocus();
                                    }
                                  },
                                ),

                                if (!isSignIn) ...[
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _confirm,
                                    focusNode: _confirmFocus,
                                    obscureText: _hideConfirm,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Confirm password',
                                      border: const OutlineInputBorder(),
                                      suffixIcon: IconButton(
                                        tooltip: _hideConfirm
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: () => setState(
                                          () => _hideConfirm = !_hideConfirm,
                                        ),
                                        icon: Icon(
                                          _hideConfirm
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (_) => _submit(),
                                  ),
                                ],

                                const SizedBox(height: 10),

                                if (isSignIn)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _loading
                                          ? null
                                          : _forgotPassword,
                                      child: const Text('Forgot password?'),
                                    ),
                                  ),

                                if (_error != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                ],

                                const SizedBox(height: 10),

                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _submit,
                                    child: Text(
                                      _loading
                                          ? 'Please wait...'
                                          : (isSignIn
                                                ? 'Sign in'
                                                : 'Create account'),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // Footer (matches your exact “can’t get confused” goal)
                                if (isSignIn)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'No account? ',
                                        style: TextStyle(
                                          color: Colors.black.withValues(
                                            alpha: 0.65,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () =>
                                                  _switchMode(_AuthMode.signUp),
                                        child: const Text('Create one'),
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Account created? ',
                                        style: TextStyle(
                                          color: Colors.black.withValues(
                                            alpha: 0.65,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () =>
                                                  _switchMode(_AuthMode.signIn),
                                        child: const Text('Sign in now'),
                                      ),
                                    ],
                                  ),

                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

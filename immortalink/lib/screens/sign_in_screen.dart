import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_chat_reminder_service.dart';

enum _AuthMode { signIn, signUp }

const _passwordResetRedirectUrl = 'com.everroots.app://login-callback';
const _staySignedInPreferenceKey = 'auth_stay_signed_in';

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
  bool _staySignedIn = true;

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
    if (password.isEmpty || password.length < 8) {
      setState(() {
        _loading = false;
        _error = 'Password must be at least 8 characters.';
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_staySignedInPreferenceKey, _staySignedIn);
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

      // Keep web on the configured Site URL; native builds return through the app.
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? null : _passwordResetRedirectUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If that email has an account, a reset link is on its way.',
          ),
        ),
      );
    } on AuthException {
      setState(() => _error = 'Could not send the reset email. Try again.');
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
    final theme = Theme.of(context);
    final muted = Colors.black.withValues(alpha: 0.58);

    InputDecoration authDecoration(
      String label, {
      IconData? icon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 21),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF70539A), width: 1.8),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFFFF8FE),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 760 || constraints.maxWidth < 390;
            final tight = constraints.maxHeight < 680;
            final cardPadding = compact
                ? (tight
                      ? const EdgeInsets.fromLTRB(16, 14, 16, 16)
                      : const EdgeInsets.fromLTRB(18, 16, 18, 18))
                : const EdgeInsets.fromLTRB(24, 20, 24, 22);
            final logoHeight = tight ? 122.0 : (compact ? 156.0 : 214.0);
            final logoScale = tight ? 1.62 : (compact ? 1.9 : 2.32);
            final verticalGap = tight ? 8.0 : (compact ? 12.0 : 16.0);
            final outerPadding = tight ? 12.0 : 22.0;
            final switchTextStyle = TextStyle(
              color: muted,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            );
            final switchButtonStyle = OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF70539A),
              backgroundColor: const Color(0xFFF4EDF8),
              side: BorderSide(
                color: const Color(0xFF70539A).withValues(alpha: 0.26),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(0, 42),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            );

            return SingleChildScrollView(
              // This padding is what prevents keyboard overlap.
              padding: EdgeInsets.fromLTRB(
                outerPadding,
                outerPadding,
                outerPadding,
                MediaQuery.of(context).viewInsets.bottom + outerPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFF8FE),
                        Color(0xFFF6F9FF),
                        Color(0xFFFFFBF7),
                      ],
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF70539A,
                              ).withValues(alpha: 0.10),
                              blurRadius: 28,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: cardPadding,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: logoHeight,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: logoHeight * 1.55,
                                      height: logoHeight * 0.86,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        gradient: RadialGradient(
                                          colors: [
                                            const Color(
                                              0xFF0F7C82,
                                            ).withValues(alpha: 0.16),
                                            const Color(
                                              0xFF70539A,
                                            ).withValues(alpha: 0.07),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                    Transform.scale(
                                      scale: logoScale,
                                      child: Image.asset(
                                        'assets/images/immortalink_logo.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: verticalGap),

                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Color(0xFF23192C),
                                        Color(0xFF6E5A93),
                                        Color(0xFF138489),
                                      ],
                                    ).createShader(bounds),
                                child: Text(
                                  'Keep your family close\nnow and always',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                    height: 1.08,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),

                              SizedBox(
                                height: tight ? 12 : (compact ? 18 : 24),
                              ),

                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              TextField(
                                controller: _email,
                                focusNode: _emailFocus,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: authDecoration(
                                  'Email',
                                  icon: Icons.mail_outline,
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
                                decoration: authDecoration(
                                  'Password',
                                  icon: Icons.lock_outline,
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
                                  decoration: authDecoration(
                                    'Confirm password',
                                    icon: Icons.verified_user_outlined,
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

                              if (isSignIn) ...[
                                SizedBox(height: tight ? 8 : 10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFF4EDF8,
                                    ).withValues(alpha: 0.70),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: CheckboxListTile(
                                    dense: tight,
                                    visualDensity: tight
                                        ? VisualDensity.compact
                                        : VisualDensity.standard,
                                    value: _staySignedIn,
                                    onChanged: _loading
                                        ? null
                                        : (value) => setState(
                                            () => _staySignedIn = value ?? true,
                                          ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    title: const Text(
                                      'Stay signed in',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Keep this account open on this device.',
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _loading
                                        ? null
                                        : _forgotPassword,
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                              ],

                              if (_error != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE9E9),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFF9E2A2A),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],

                              SizedBox(height: tight ? 8 : 10),

                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF70539A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
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

                              SizedBox(height: tight ? 6 : (compact ? 10 : 14)),

                              if (isSignIn)
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'No account? ',
                                      style: switchTextStyle,
                                    ),
                                    OutlinedButton(
                                      style: switchButtonStyle,
                                      onPressed: _loading
                                          ? null
                                          : () => _switchMode(_AuthMode.signUp),
                                      child: const Text('Create one'),
                                    ),
                                  ],
                                )
                              else
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Account created? ',
                                      style: switchTextStyle,
                                    ),
                                    OutlinedButton(
                                      style: switchButtonStyle,
                                      onPressed: _loading
                                          ? null
                                          : () => _switchMode(_AuthMode.signIn),
                                      child: const Text('Sign in now'),
                                    ),
                                  ],
                                ),
                            ],
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

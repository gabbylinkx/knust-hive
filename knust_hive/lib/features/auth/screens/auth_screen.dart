import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  bool isSignUp = false;
  bool loading = false;
  bool passwordVisible = false;
  String? error;
  String? notice;

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() {
      loading = true;
      error = null;
      notice = null;
    });
    try {
      await action();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = _friendlyDatabaseError(e));
    } on AuthException catch (e) {
      if (mounted) setState(() => error = _friendlyAuthError(e));
    } catch (e) {
      if (mounted) setState(() => error = _friendlyNetworkError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _friendlyDatabaseError(PostgrestException exception) {
    if (exception.code == 'PGRST205' ||
        exception.code == '42P01' ||
        exception.message.toLowerCase().contains('profiles')) {
      return 'Supabase is reachable, but KNUST Hive’s database schema is missing. In Supabase SQL Editor, run the project’s supabase/schema.sql file, then retry. Do not use a service-role key in the app.';
    }
    return exception.message;
  }

  String _friendlyAuthError(AuthException exception) {
    final message = exception.message.toLowerCase();
    final code = exception.code?.toLowerCase();
    if (_isNetworkError(message)) {
      return 'KNUST Hive could not reach Supabase. Check your internet connection and retry. If this continues, confirm the Supabase project is active and its Auth service is available.';
    }
    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return 'That email and password do not match. Check your details, create an account if you are new, or use “Forgot password?”.';
    }
    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return 'Confirm your email using the link we sent before signing in.';
    }
    if (code == 'user_already_exists' ||
        message.contains('already registered')) {
      return 'An account already exists for this email. Sign in or reset its password.';
    }
    if (exception.statusCode == '429' ||
        message.contains('too many requests')) {
      return 'Too many attempts. Wait a few minutes, then try again.';
    }
    if (message.contains('redirect') && message.contains('allow')) {
      return 'Supabase blocked the email redirect. Add this app URL under Authentication → URL Configuration → Redirect URLs, then request a new email link.';
    }
    return exception.message;
  }

  String _friendlyNetworkError(Object exception) {
    if (_isNetworkError(exception.toString().toLowerCase())) {
      return 'KNUST Hive could not reach Supabase. Check your internet connection and retry. If this continues, confirm the Supabase project is active and its Auth service is available.';
    }
    return exception.toString();
  }

  bool _isNetworkError(String message) =>
      message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('xmlhttprequest') ||
      message.contains('clientexception') ||
      message.contains('network request failed') ||
      message.contains('connection refused') ||
      message.contains('timed out') ||
      message.contains('failed to fetch');

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
        ? null
        : 'Enter a valid email address';
  }

  Future<void> _sendPasswordRecovery() async {
    final email = emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() {
        error = 'Enter your email above first so we can send a recovery link.';
        notice = null;
      });
      return;
    }
    await _runAuth(() async {
      await ref.read(authActionsProvider).sendPasswordRecovery(email: email);
      if (mounted) {
        setState(() {
          notice =
              'If an account exists for $email, a password recovery link has been sent. Check your inbox and spam folder.';
        });
      }
    });
  }

  Future<void> _resendConfirmation() async {
    final email = emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() {
        error = 'Enter your email above first so we can resend confirmation.';
        notice = null;
      });
      return;
    }
    await _runAuth(() async {
      await ref.read(authActionsProvider).resendConfirmation(email: email);
      if (mounted) {
        setState(() {
          notice =
              'If this account still needs confirmation, a new link was sent to $email.';
        });
      }
    });
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    final auth = ref.read(authActionsProvider);
    await _runAuth(() async {
      if (isSignUp) {
        final response = await auth.signUpWithEmail(
          email: emailCtrl.text.trim(),
          password: passwordCtrl.text,
          displayName: nameCtrl.text.trim(),
        );
        if (response.session == null && mounted) {
          setState(
            () => notice =
                'Check your email and tap the confirmation link. It will return you here and sign you in automatically.',
          );
        }
      } else {
        await auth.signIn(
          email: emailCtrl.text.trim(),
          password: passwordCtrl.text,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.hive_rounded, color: AppColors.gold, size: 44),
            const SizedBox(height: 10),
            Text(
              'KNUST Hive',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your campus, in one place',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.goldSoft),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    if (isSignUp) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Create an account with your email to join KNUST Hive.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameCtrl,
                        decoration:
                            const InputDecoration(hintText: 'Full name'),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter your name'
                                : null,
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextFormField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(hintText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passwordCtrl,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: passwordVisible
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () => setState(
                              () => passwordVisible = !passwordVisible),
                          icon: Icon(passwordVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                        ),
                      ),
                      obscureText: !passwordVisible,
                      autofillHints: [
                        isSignUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      validator: (value) => (value?.length ?? 0) < 6
                          ? 'Password must be at least 6 characters'
                          : null,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: AppColors.clay,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (!isSignUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: loading ? null : _sendPasswordRecovery,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    if (!isSignUp)
                      TextButton(
                        onPressed: loading ? null : _resendConfirmation,
                        child: const Text('Resend confirmation email'),
                      ),
                    if (notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          notice!,
                          style: const TextStyle(
                            color: AppColors.forest,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(isSignUp ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (SupabaseService.isGoogleOAuthEnabled)
                      OutlinedButton.icon(
                        onPressed: loading
                            ? null
                            : () => _runAuth(
                                  () => ref
                                      .read(authActionsProvider)
                                      .signInWithGoogle(),
                                ),
                        icon: const Icon(Icons.g_mobiledata),
                        label: const Text('Continue with Google'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: loading
                  ? null
                  : () => setState(() {
                        isSignUp = !isSignUp;
                        error = null;
                        notice = null;
                        formKey.currentState?.reset();
                      }),
              child: Text(
                isSignUp
                    ? 'Already have an account? Sign in'
                    : 'New here? Create an account',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

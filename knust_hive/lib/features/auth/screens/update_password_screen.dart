import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _loading = false;
  bool _updated = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _error = 'Use at least 6 characters for your password.');
      return;
    }
    if (password != _confirmationController.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) setState(() => _updated = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Could not update your password. The recovery link may have expired. Request a new link and try again. ($error)');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _returnToSignIn() async {
    await SupabaseService.client.auth.signOut();
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final hasRecoverySession =
        SupabaseService.client.auth.currentSession != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasRecoverySession)
                  const Text(
                    'This recovery link is missing or expired. Return to sign in and request a new password reset link.',
                    textAlign: TextAlign.center,
                  )
                else if (_updated) ...[
                  const Icon(Icons.check_circle_outline,
                      size: 48, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text(
                    'Your password has been updated. Sign in with the new password.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _returnToSignIn,
                    child: const Text('Return to sign in'),
                  ),
                ] else ...[
                  const Text('Choose a new password for your account.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmationController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm password'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _updatePassword,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save new password'),
                  ),
                ],
                if (!hasRecoverySession) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => context.go('/auth'),
                    child: const Text('Return to sign in'),
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

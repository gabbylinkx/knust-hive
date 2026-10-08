import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Streams auth state so the router (see core/router/app_router.dart) can
/// redirect signed-out users to /auth without polling.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseService.client.auth.onAuthStateChange;
});

class AuthActions {
  final _client = SupabaseService.client;

  Future<void> _verifyAppSchema() async {
    await _client.from('profiles').select('id').limit(0);
  }

  Future<void> signIn({required String email, required String password}) async {
    await _verifyAppSchema();
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> sendPasswordRecovery({required String email}) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb
          ? Uri.base
              .replace(path: '/', query: '', fragment: '/update-password')
              .toString()
          : null,
    );
  }

  Future<void> resendConfirmation({required String email}) async {
    await _client.auth.resend(
      email: email,
      type: OtpType.signup,
      emailRedirectTo: kIsWeb
          ? Uri.base.replace(path: '/', query: '', fragment: '').toString()
          : null,
    );
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _verifyAppSchema();
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: kIsWeb
          ? Uri.base.replace(path: '/', query: '', fragment: '').toString()
          : null,
      data: {'display_name': displayName},
    );
    return response;
  }

  Future<void> completeProfile({
    required String displayName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to complete your profile');
    await _client.auth.updateUser(
      UserAttributes(
        data: {'display_name': displayName},
      ),
    );
    await _client.from('profiles').upsert({
      'id': user.id,
      'display_name': displayName,
    });
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  Future<void> signOut() => _client.auth.signOut();
}

final authActionsProvider = Provider((ref) => AuthActions());

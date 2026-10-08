import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/screens/profile_onboarding_screen.dart';
import '../../features/auth/screens/update_password_screen.dart';
import '../../features/chat/screens/chat_room_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../services/supabase_service.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable =
      GoRouterRefreshStream(SupabaseService.client.auth.onAuthStateChange);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppShell()),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/update-password',
        builder: (context, state) => const UpdatePasswordScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const ProfileOnboardingScreen(),
      ),
      GoRoute(
          path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) => ChatRoomScreen(
          chatId: state.pathParameters['id']!,
          title: state.uri.queryParameters['title'] ?? 'Conversation',
        ),
      ),
    ],
    redirect: (context, state) async {
      final user = SupabaseService.client.auth.currentUser;
      final signedIn = user != null;
      final goingToAuth = state.matchedLocation == '/auth';
      final updatingPassword = state.matchedLocation == '/update-password';
      final goingToOnboarding = state.matchedLocation == '/onboarding';
      if (!signedIn && !goingToAuth && !updatingPassword) return '/auth';
      if (!signedIn) return null;
      if (updatingPassword) return null;
      if (goingToAuth) return '/';

      final profile = await SupabaseService.client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null && !goingToOnboarding) return '/onboarding';
      if (profile != null && goingToOnboarding) return '/';
      return null;
    },
    refreshListenable: refreshListenable,
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase init so main.dart stays clean and every feature
/// can reach the client the same way: `SupabaseService.client`.
class SupabaseService {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static const isGoogleOAuthEnabled =
      bool.fromEnvironment('ENABLE_GOOGLE_AUTH');

  static SupabaseClient? _client;

  static bool get isConfigured {
    final uri = Uri.tryParse(_url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        _key.isNotEmpty &&
        !_url.contains('YOUR_') &&
        !_key.startsWith('YOUR_');
  }

  static bool get isInitialized => _client != null;

  static SupabaseClient get client {
    final initializedClient = _client;
    if (initializedClient == null) {
      throw StateError('Supabase has not been initialized.');
    }
    return initializedClient;
  }

  static Future<void> init() async {
    if (!isConfigured) {
      throw StateError(
        'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or '
        'SUPABASE_ANON_KEY) to connect the app to Supabase.',
      );
    }

    await Supabase.initialize(
      url: _url,
      publishableKey: _key,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _client = Supabase.instance.client;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/router/app_router.dart';
import 'core/screens/setup_screen.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  String? startupError;
  if (SupabaseService.isConfigured) {
    try {
      await SupabaseService.init();
    } catch (error) {
      startupError = 'Could not connect to Supabase: $error';
    }
  }

  runApp(ProviderScope(child: KnustHiveApp(startupError: startupError)));
}

class KnustHiveApp extends ConsumerWidget {
  const KnustHiveApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = SupabaseService.isInitialized;
    if (!isConnected) {
      return MaterialApp(
        title: 'KNUST Hive',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: SetupScreen(error: startupError),
      );
    }

    return MaterialApp.router(
      title: 'KNUST Hive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key, this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.hive_rounded,
                      color: AppColors.forest, size: 48),
                  const SizedBox(height: 16),
                  Text('Connect KNUST Hive',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'The app needs a Supabase project before student accounts and campus data can load.',
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Run from the knust_hive project folder:',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const SelectableText(
                    'flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co '
                    '--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_KEY',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Use the publishable key from Supabase Project Settings → API. '
                    'Do not put a service-role key in a mobile app.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

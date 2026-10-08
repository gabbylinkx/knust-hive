import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knust_hive/core/screens/setup_screen.dart';
import 'package:knust_hive/main.dart';

void main() {
  testWidgets('explains how to configure Supabase without crashing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SetupScreen()),
    );

    expect(find.text('Connect KNUST Hive'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(
        find.textContaining('Do not put a service-role key'), findsOneWidget);
  });

  testWidgets('shows initialization errors explicitly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SetupScreen(error: 'Supabase is unreachable')),
    );

    expect(find.text('Supabase is unreachable'), findsOneWidget);
  });

  testWidgets('app shows setup UI when Supabase has not been initialized',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KnustHiveApp()),
    );

    expect(find.text('Connect KNUST Hive'), findsOneWidget);
  });
}

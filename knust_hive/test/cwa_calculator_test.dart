import 'package:flutter_test/flutter_test.dart';
import 'package:knust_hive/features/tools/cwa_calculator.dart';

void main() {
  group('calculateCwa', () {
    test('returns the credit-weighted percentage average', () {
      final cwa = calculateCwa([
        (score: 80.0, creditHours: 3.0),
        (score: 60.0, creditHours: 1.0),
      ]);

      expect(cwa, 75.0);
    });

    test('does not fabricate an average when there are no course marks', () {
      expect(calculateCwa([]), isNull);
    });

    test('ignores invalid scores and non-positive credit values', () {
      final cwa = calculateCwa([
        (score: 75.0, creditHours: 2.0),
        (score: 101.0, creditHours: 2.0),
        (score: 20.0, creditHours: 0.0),
      ]);

      expect(cwa, 75.0);
    });
  });
}

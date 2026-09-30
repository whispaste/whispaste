import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'tolerant_golden_comparator.dart';

void main() {
  test('accepts the cross-host anti-aliasing noise seen on hosted CI', () {
    // Largest diff of the 24 goldens that failed in run 36710725313: 0.02 %.
    expect(
      withinGoldenTolerance(
        ComparisonResult(passed: false, diffPercent: 0.0002),
      ),
      isTrue,
    );
    expect(
      withinGoldenTolerance(
        ComparisonResult(passed: false, diffPercent: 0.001),
      ),
      isTrue,
    );
  });

  test('rejects anything above 0.1 % — a real UI change', () {
    expect(
      withinGoldenTolerance(
        ComparisonResult(passed: false, diffPercent: 0.0011),
      ),
      isFalse,
    );
    expect(
      withinGoldenTolerance(ComparisonResult(passed: false, diffPercent: 0.05)),
      isFalse,
    );
  });

  test('the file-level config installs the tolerant comparator', () {
    expect(goldenFileComparator, isA<TolerantGoldenComparator>());
  });

  // golden_screenshot's testGoldens defaults to allowedDiffPercent 0.1 but
  // compares it against a pixel *fraction* (flutter's diffPercent), so the
  // default lets 10 % of a screenshot change unnoticed.
  testGoldens(
    'testGoldens with allowedDiffPercent 0 keeps the 0.1 % comparator',
    (tester) async {
      expect(goldenFileComparator, isA<TolerantGoldenComparator>());
    },
    allowedDiffPercent: 0,
  );

  testGoldens('testGoldens by default swaps in the 10 % fuzzy comparator', (
    tester,
  ) async {
    expect(goldenFileComparator, isA<FuzzyComparator>());
    expect((goldenFileComparator as FuzzyComparator).allowedDiffPercent, 0.1);
  });

  test('every testGoldens call site opts out of the 10 % default', () {
    final offenders = <String>[];
    for (final file in Directory('test').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('tolerant_golden_comparator_test.dart')) continue;
      final source = file.readAsStringSync();
      final calls = RegExp(r'\btestGoldens\(').allMatches(source).length;
      final optOuts = RegExp(
        r'allowedDiffPercent:\s*0\s*[,)]',
      ).allMatches(source).length;
      if (calls > optOuts) offenders.add(file.path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Pass allowedDiffPercent: 0 to testGoldens so the 0.1 % '
          'TolerantGoldenComparator applies instead of a 10 % allowance.',
    );
  });
}

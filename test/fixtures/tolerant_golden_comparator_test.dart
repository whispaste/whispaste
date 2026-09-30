import 'package:flutter_test/flutter_test.dart';

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
}

import 'package:flutter_test/flutter_test.dart';

import '../../tool/headless_benchmark_check.dart';

Map<String, Object?> _report({
  String platform = 'linux',
  String engine = 'whisper',
  String model = 'whisper-small',
  double rtfMedian = 0.5,
}) => {
  'platform': platform,
  'engine': engine,
  'model': model,
  'rtfMedian': rtfMedian,
  'loadMs': 900,
  'transcript': 'hello',
};

void main() {
  const baseline = <String, Object?>{
    'tolerance': 1.5,
    'rtfMedian': {'linux/whisper/whisper-small': 0.4},
  };

  test('passes a run within the tolerated slowdown', () {
    final verdict = checkHeadlessBenchmark(baseline, [
      _report(rtfMedian: 0.59),
    ]);

    expect(verdict.failures, isEmpty);
    expect(verdict.summary.single, contains('linux/whisper/whisper-small'));
  });

  test('fails a run slower than baseline x tolerance', () {
    final verdict = checkHeadlessBenchmark(baseline, [
      _report(rtfMedian: 0.61),
    ]);

    expect(verdict.failures.single, contains('linux/whisper/whisper-small'));
    expect(verdict.failures.single, contains('0.61'));
  });

  test('a configuration without baseline only warns, so a new platform or '
      'model can be calibrated from its first run', () {
    final verdict = checkHeadlessBenchmark(baseline, [
      _report(platform: 'windows'),
    ]);

    expect(verdict.failures, isEmpty);
    expect(verdict.warnings.single, contains('windows/whisper/whisper-small'));
  });

  test('defaults the tolerance when the baseline omits it', () {
    final verdict = checkHeadlessBenchmark(
      const {
        'rtfMedian': {'linux/whisper/whisper-small': 0.4},
      },
      [_report(rtfMedian: 0.61)],
    );

    expect(verdict.failures, hasLength(1));
  });
}

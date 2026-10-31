/// Wall-clock budgets for [toNumericOnly] (itn-cad-zahlen Slice 6, PRD §8.5,
/// P1/P2). The structural guard P3 stays in test/services/.
///
/// Not part of a test run: see benchmarks/README.md.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/number_transforms.dart';

void main() {
  group('toNumericOnly — §8.5 Performance (P1/P2)', () {
    // A realistic dictation transcript entirely made of number words, built
    // by repeating the Nutzer-Mail phrase (§8.3 Fall 3) until it reaches the
    // PRD's ~2000-character budget without truncating mid-token — a
    // mid-word cut would introduce an UNKNOWN token and short-circuit the
    // all-or-nothing path, which would under-measure the real cost.
    String buildLongDictationSample() {
      const phrase = 'fünf komma zwei minus drei ';
      final buffer = StringBuffer();
      while (buffer.length < 2000) {
        buffer.write(phrase);
      }
      return buffer.toString().trim();
    }

    test('P1: a single call on a ~2000-char transcript stays under 5ms '
        '(warmup discarded, median of 5 measured calls)', () {
      final sample = buildLongDictationSample();
      expect(sample.length, greaterThanOrEqualTo(2000));

      // Warmup — discard JIT/cache effects, not a measured sample.
      toNumericOnly(sample);

      final samples = <int>[];
      for (var i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        final result = toNumericOnly(sample);
        sw.stop();
        expect(result, isNotNull, reason: 'sample must be fully convertible');
        samples.add(sw.elapsedMicroseconds);
      }
      samples.sort();
      final medianMicros = samples[samples.length ~/ 2];

      expect(
        medianMicros,
        lessThan(5000),
        reason:
            'median of 5 runs was $medianMicros'
            'µs, budget is 5ms (all samples: $samples)',
      );
    });

    test('P2: 1000 repetitions of the Nutzer-Mail example stay under 50ms '
        'total (warmup pass discarded)', () {
      const phrase = 'fünf komma zwei minus drei';

      // Warmup pass — discard JIT/cache effects.
      for (var i = 0; i < 1000; i++) {
        toNumericOnly(phrase);
      }

      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        final result = toNumericOnly(phrase);
        expect(result, '5,2-3');
      }
      sw.stop();

      expect(
        sw.elapsedMicroseconds,
        lessThan(50000),
        reason:
            '1000 repetitions took ${sw.elapsedMicroseconds}µs, budget is 50ms',
      );
    });
  });
}

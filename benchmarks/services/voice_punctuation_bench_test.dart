/// Wall-clock budgets for the voice punctuation command pass: linear growth
/// and an absolute bound on a large dictation. The output of the same pass is
/// tested in test/services/voice_punctuation_test.dart.
///
/// Not part of a test run: see benchmarks/README.md.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/voice_punctuation.dart';

String _apply(String text, [String lang = 'de']) =>
    applyVoicePunctuation(text, languageCode: lang);

void main() {
  group('voice punctuation budgets', () {
    const chunk = 'Hallo Komma wie geht es dir Punkt das ist gut Fragezeichen ';

    // Median of five timed runs: one slow run on a loaded runner must not
    // decide the ratio. Linear growth gives about 4x for 4x input, quadratic
    // about 16x; the bound of 10x separates the two with margin.
    int medianOf5(String text) {
      final times = <int>[];
      for (var run = 0; run < 5; run++) {
        final watch = Stopwatch()..start();
        _apply(text);
        watch.stop();
        times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      return times[2];
    }

    test('run time grows linearly with the text, not quadratically', () {
      final small = List.filled(500, chunk).join();
      final large = List.filled(2000, chunk).join(); // 4x the input
      _apply(small); // warm up the compiled matcher
      final t1 = medianOf5(small);
      final t4 = medianOf5(large);
      expect(
        t4,
        lessThan(10 * t1),
        reason: 'x4 input took $t4 us, x1 took $t1 us',
      );
    });

    test(
      'a very large dictation finishes within a generous absolute bound',
      () {
        final text = List.filled(2000, chunk).join();
        final watch = Stopwatch()..start();
        final result = _apply(text);
        watch.stop();
        expect(
          result.startsWith('Hallo, wie geht es dir. Das ist gut? Hallo, wie'),
          isTrue,
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );
  });
}

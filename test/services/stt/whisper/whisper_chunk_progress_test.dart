/// Chunk aggregation of the whisper progress callback (IMP-PROG-2): the
/// overall fraction of a pause-split transcription must rise monotonically
/// from 0 to 1 no matter how each chunk reports its own progress.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';

void main() {
  group('chunkedProgressFraction', () {
    test('rises monotonically from 0 to 1 across all chunks', () {
      const chunkCount = 4;
      final overall = <double>[];
      for (var chunk = 0; chunk < chunkCount; chunk++) {
        // Each chunk reports 0..100 percent of its own decode, in steps.
        for (var percent = 0; percent <= 100; percent += 10) {
          overall.add(
            chunkedProgressFraction(
              chunkIndex: chunk,
              chunkCount: chunkCount,
              withinChunk: percent / 100,
            ),
          );
        }
      }

      for (var i = 1; i < overall.length; i++) {
        expect(
          overall[i],
          greaterThanOrEqualTo(overall[i - 1]),
          reason: 'step $i went backwards',
        );
      }
      expect(overall.first, 0);
      expect(overall.last, 1);
    });

    test('a finished chunk counts fully and the next one starts there', () {
      final endOfFirst = chunkedProgressFraction(
        chunkIndex: 0,
        chunkCount: 2,
        withinChunk: 1,
      );
      final startOfSecond = chunkedProgressFraction(
        chunkIndex: 1,
        chunkCount: 2,
        withinChunk: 0,
      );
      expect(endOfFirst, 0.5);
      expect(startOfSecond, 0.5);
    });

    test('a single chunk maps the engine fraction directly', () {
      expect(
        chunkedProgressFraction(
          chunkIndex: 0,
          chunkCount: 1,
          withinChunk: 0.42,
        ),
        closeTo(0.42, 1e-9),
      );
    });

    test('out-of-range inputs are clamped, never leave 0..1', () {
      expect(
        chunkedProgressFraction(chunkIndex: 0, chunkCount: 3, withinChunk: 7),
        closeTo(1 / 3, 1e-9),
      );
      expect(
        chunkedProgressFraction(
          chunkIndex: 0,
          chunkCount: 3,
          withinChunk: double.nan,
        ),
        0,
      );
      expect(
        chunkedProgressFraction(chunkIndex: 9, chunkCount: 3, withinChunk: 1),
        1,
      );
      expect(
        chunkedProgressFraction(chunkIndex: 0, chunkCount: 0, withinChunk: 0.5),
        0,
      );
    });
  });
}

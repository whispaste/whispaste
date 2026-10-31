/// Unit tests for the sliding-window PCM trim used by the
/// live-transcript-during-recording preview.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/pcm_sliding_window.dart';

void main() {
  group('trimPcmToWindow', () {
    test('returns the same instance unchanged when already within window', () {
      final buffer = Uint8List(100);

      final result = trimPcmToWindow(
        buffer,
        sampleRate: 16000,
        windowSeconds: 25.0,
      );

      expect(result, same(buffer));
    });

    test('trims down to the trailing window, aligned to whole samples', () {
      const sampleRate = 16000;
      const bytesPerSample = 2;
      const windowSeconds = 1.0;
      const windowBytes = sampleRate * bytesPerSample; // 32000 bytes = 1s
      final buffer = Uint8List(windowBytes * 3);
      // Fill with an ascending byte pattern so we can verify it's the TAIL kept.
      for (var i = 0; i < buffer.length; i++) {
        buffer[i] = i % 256;
      }

      final result = trimPcmToWindow(
        buffer,
        sampleRate: sampleRate,
        windowSeconds: windowSeconds,
      );

      expect(result.length, windowBytes);
      // The tail must match the last `windowBytes` of the original buffer.
      expect(
        result,
        Uint8List.sublistView(buffer, buffer.length - windowBytes),
      );
    });

    test(
      'never splits a sample: cut point is always a multiple of bytesPerSample',
      () {
        const sampleRate = 16000;
        const windowSeconds =
            0.5; // 0.5s * 16000 * 2 bytes = 16000 bytes exactly
        final buffer = Uint8List(
          50001,
        ); // deliberately odd length / not a clean window

        final result = trimPcmToWindow(
          buffer,
          sampleRate: sampleRate,
          windowSeconds: windowSeconds,
        );

        expect(result.length % 2, 0);
        expect(result.length, lessThanOrEqualTo(buffer.length));
      },
    );

    test(
      'returns buffer unchanged for non-positive sampleRate or windowSeconds',
      () {
        final buffer = Uint8List(100);

        expect(
          trimPcmToWindow(buffer, sampleRate: 0, windowSeconds: 25.0),
          same(buffer),
        );
        expect(
          trimPcmToWindow(buffer, sampleRate: 16000, windowSeconds: 0),
          same(buffer),
        );
        expect(
          trimPcmToWindow(buffer, sampleRate: 16000, windowSeconds: -1),
          same(buffer),
        );
      },
    );

    test('empty buffer stays empty', () {
      final result = trimPcmToWindow(
        Uint8List(0),
        sampleRate: 16000,
        windowSeconds: 25.0,
      );

      expect(result, isEmpty);
    });
  });
}

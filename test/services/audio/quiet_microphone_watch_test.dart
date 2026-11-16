/// Too-quiet hint timing (overlay decision 4) and the RMS reading it relies on.
///
/// Time is injected: the watch takes the reading time as a parameter, and the
/// meter runs under fakeAsync, so nothing waits in real time.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/amplitude_from_pcm.dart';
import 'package:whispaste/services/audio/quiet_microphone_watch.dart';

/// Little-endian int16 PCM where every sample has the same value.
Uint8List _constantPcm(int value, int samples) {
  final bytes = Uint8List(samples * 2);
  for (var i = 0; i < samples; i++) {
    bytes[i * 2] = value & 0xFF;
    bytes[i * 2 + 1] = (value >> 8) & 0xFF;
  }
  return bytes;
}

void main() {
  final t0 = DateTime(2026, 10, 30, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('QuietMicrophoneWatch', () {
    test('the threshold and hold are the documented starting values', () {
      expect(quietMicRmsThresholdDbFs, -55.0);
      expect(quietMicHoldDuration, const Duration(seconds: 5));
    });

    test('hint stays off until the level has been quiet for the hold time', () {
      final watch = QuietMicrophoneWatch();
      watch.observe(-70, at(0));
      watch.observe(-70, at(4999));
      expect(watch.hinting, isFalse);

      expect(watch.observe(-70, at(5000)), isTrue);
      expect(watch.hinting, isTrue);
    });

    test(
      'a level above the threshold restarts the count and clears a hint',
      () {
        final watch = QuietMicrophoneWatch();
        watch.observe(-70, at(0));
        watch.observe(-70, at(5000));
        expect(watch.hinting, isTrue);

        expect(watch.observe(-30, at(5100)), isTrue);
        expect(watch.hinting, isFalse);

        // A new quiet stretch has to run the full hold again.
        watch.observe(-70, at(6000));
        watch.observe(-70, at(10999));
        expect(watch.hinting, isFalse);
      },
    );

    test('digital silence is not counted as quiet', () {
      final watch = QuietMicrophoneWatch();
      watch.observe(-70, at(0));
      watch.observe(double.negativeInfinity, at(3000));
      watch.observe(-70, at(4000));
      watch.observe(-70, at(8000));
      expect(
        watch.hinting,
        isFalse,
        reason: 'the silence path has its own notice; the count restarts',
      );
    });

    test('reports only real changes of the hint state', () {
      final watch = QuietMicrophoneWatch();
      expect(watch.observe(-70, at(0)), isFalse);
      expect(watch.observe(-70, at(5000)), isTrue);
      expect(watch.observe(-70, at(6000)), isFalse);
    });

    test('reset clears the state for the next recording', () {
      final watch = QuietMicrophoneWatch();
      watch.observe(-70, at(0));
      watch.observe(-70, at(5000));
      watch.reset();
      expect(watch.hinting, isFalse);
    });
  });

  group('AmplitudeFromPcm RMS', () {
    test('a steady half-scale signal reads about -6 dBFS RMS', () {
      fakeAsync((async) {
        final meter = AmplitudeFromPcm(
          pollInterval: const Duration(milliseconds: 40),
        );
        final halfScale = (32768 / 2).round();
        meter.addChunk(_constantPcm(halfScale, 640));
        async.elapse(const Duration(milliseconds: 40));
        expect(
          meter.lastRmsDbFs,
          closeTo(20 * math.log(0.5) / math.ln10, 0.05),
        );
        unawaited(meter.dispose());
      });
    });

    test('RMS is -inf after a stall past maxHold', () {
      fakeAsync((async) {
        final meter = AmplitudeFromPcm(
          pollInterval: const Duration(milliseconds: 40),
        );
        meter.addChunk(_constantPcm(8000, 640));
        async.elapse(const Duration(milliseconds: 40));
        expect(meter.lastRmsDbFs.isFinite, isTrue);
        async.elapse(
          AmplitudeFromPcm.maxHold + const Duration(milliseconds: 80),
        );
        expect(meter.lastRmsDbFs, double.negativeInfinity);
        unawaited(meter.dispose());
      });
    });
  });
}

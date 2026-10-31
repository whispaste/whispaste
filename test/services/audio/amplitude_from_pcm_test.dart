/// Tests for [AmplitudeFromPcm] — the in-process PCM-to-dBFS calculator
/// that replaces `recorder.onAmplitudeChanged()` for the stream-based
/// recording pipeline.
///
/// Verifies dBFS output for silence, full-scale, and a mid-amplitude sine,
/// plus that multi-chunk accumulation produces a single consolidated value
/// per polling interval.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/amplitude_from_pcm.dart';

/// Encodes a list of int16 samples into a little-endian PCM byte buffer.
Uint8List _pcmFromSamples(List<int> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Generates a sine wave at the given peak amplitude (16-bit signed range).
List<int> _sineSamples({
  required int count,
  required int peak,
  double cyclesPerSample = 0.05,
}) {
  return List<int>.generate(count, (i) {
    final theta = 2 * math.pi * cyclesPerSample * i;
    return (math.sin(theta) * peak).round().clamp(-32768, 32767);
  });
}

void main() {
  const interval = Duration(milliseconds: 40);

  group('AmplitudeFromPcm — instantaneous dBFS', () {
    test('silence chunk emits a value at or below the speech-level floor', () {
      fakeAsync((async) {
        final calc = AmplitudeFromPcm(pollInterval: interval);
        final values = <double>[];
        final sub = calc.stream.listen(values.add);

        // 320 silent samples = 20 ms of mono 16 kHz audio.
        calc.addChunk(_pcmFromSamples(List<int>.filled(320, 0)));
        async.elapse(interval + const Duration(milliseconds: 5));

        expect(values, isNotEmpty);
        // Silence is conventionally reported as -∞ dB, but any value at or
        // below the perceptual speech floor (-50 dB) is acceptable; the
        // downstream mapper clamps to 0.0 from there.
        expect(values.last, lessThanOrEqualTo(-50.0));

        sub.cancel();
        calc.dispose();
      });
    });

    test('full-scale sample is reported near 0 dBFS (peak metric)', () {
      fakeAsync((async) {
        final calc = AmplitudeFromPcm(pollInterval: interval);
        final values = <double>[];
        final sub = calc.stream.listen(values.add);

        // 320 alternating full-scale samples.
        final samples = <int>[];
        for (var i = 0; i < 320; i++) {
          samples.add(i.isEven ? 32767 : -32768);
        }
        calc.addChunk(_pcmFromSamples(samples));
        async.elapse(interval + const Duration(milliseconds: 5));

        expect(values, isNotEmpty);
        expect(values.last, closeTo(0.0, 0.5));

        sub.cancel();
        calc.dispose();
      });
    });

    test('half-amplitude sine reports ≈ -6 dBFS within ±0.5 dB', () {
      fakeAsync((async) {
        final calc = AmplitudeFromPcm(pollInterval: interval);
        final values = <double>[];
        final sub = calc.stream.listen(values.add);

        // Half-scale peak — 16384 ≈ 32768 / 2 → -6 dBFS peak.
        final samples = _sineSamples(count: 640, peak: 16384);
        calc.addChunk(_pcmFromSamples(samples));
        async.elapse(interval + const Duration(milliseconds: 5));

        expect(values, isNotEmpty);
        expect(values.last, closeTo(-6.0, 0.5));

        sub.cancel();
        calc.dispose();
      });
    });
  });

  group('AmplitudeFromPcm — accumulation', () {
    test('multiple small chunks within one interval produce one value', () {
      fakeAsync((async) {
        final calc = AmplitudeFromPcm(pollInterval: interval);
        final values = <double>[];
        final sub = calc.stream.listen(values.add);

        // Three small chunks all delivered within the polling interval.
        calc.addChunk(_pcmFromSamples(_sineSamples(count: 80, peak: 16384)));
        async.elapse(const Duration(milliseconds: 5));
        calc.addChunk(_pcmFromSamples(_sineSamples(count: 80, peak: 16384)));
        async.elapse(const Duration(milliseconds: 5));
        calc.addChunk(_pcmFromSamples(_sineSamples(count: 80, peak: 16384)));

        // Now flush the polling interval.
        async.elapse(interval);

        expect(
          values.length,
          1,
          reason: 'one emission per polling interval, not one per chunk',
        );

        sub.cancel();
        calc.dispose();
      });
    });

    test('chunks across multiple intervals each emit their own value', () {
      fakeAsync((async) {
        final calc = AmplitudeFromPcm(pollInterval: interval);
        final values = <double>[];
        final sub = calc.stream.listen(values.add);

        for (var i = 0; i < 3; i++) {
          calc.addChunk(_pcmFromSamples(List<int>.filled(80, 16384)));
          async.elapse(interval + const Duration(milliseconds: 5));
        }

        expect(values, hasLength(3));

        sub.cancel();
        calc.dispose();
      });
    });
  });
}

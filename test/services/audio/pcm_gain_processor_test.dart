import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/pcm_gain_processor.dart';

/// Encodes a list of signed int16 samples into a little-endian PCM byte buffer
/// of the shape `record` emits.
Uint8List _pcm(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

/// Decodes a PCM byte buffer back into the int16 samples it represents.
List<int> _samples(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < bytes.length ~/ 2; i++)
      view.getInt16(i * 2, Endian.little),
  ];
}

void main() {
  group('PcmGainProcessor', () {
    test('gain=1.0 is identity — output bytewise equal to input', () {
      final input = _pcm([0, 1, -1, 100, -100, 12345, -12345, 32767, -32768]);
      final processor = PcmGainProcessor(gain: 1.0);

      final output = processor.process(input);

      expect(output, equals(input));
      expect(processor.clippedSamples, 0);
    });

    test('gain=0.5 halves samples within safe range (± rounding)', () {
      final input = _pcm([10000, -10000, 4, -4, 0]);
      final processor = PcmGainProcessor(gain: 0.5);

      final output = _samples(processor.process(input));

      expect(output, [5000, -5000, 2, -2, 0]);
      expect(processor.clippedSamples, 0);
    });

    test('gain=2.0 doubles samples in safe range', () {
      final input = _pcm([10000, -10000, 1000, -1, 0]);
      final processor = PcmGainProcessor(gain: 2.0);

      final output = _samples(processor.process(input));

      expect(output, [20000, -20000, 2000, -2, 0]);
      expect(processor.clippedSamples, 0);
    });

    test('gain=0.0 zeroes all samples', () {
      final input = _pcm([10000, -32768, 32767, 1, -1, 7777]);
      final processor = PcmGainProcessor(gain: 0.0);

      final output = _samples(processor.process(input));

      expect(output, [0, 0, 0, 0, 0, 0]);
      expect(processor.clippedSamples, 0);
    });

    test('gain=10.0 with +10000 saturates to +32767 and counts one clip', () {
      final input = _pcm([10000]);
      final processor = PcmGainProcessor(gain: 10.0);

      final output = _samples(processor.process(input));

      expect(output, [32767]);
      expect(processor.clippedSamples, 1);
    });

    test('gain=10.0 with -10000 saturates to -32768 and counts one clip', () {
      final input = _pcm([-10000]);
      final processor = PcmGainProcessor(gain: 10.0);

      final output = _samples(processor.process(input));

      expect(output, [-32768]);
      expect(processor.clippedSamples, 1);
    });

    test(
      'mixed chunk with partial clipping increments counter only for clipped samples',
      () {
        // gain=4.0:
        //   +1000   ×4 =   +4000     (safe)
        //   +20000  ×4 = +80000   → +32767 (CLIP)
        //   -20000  ×4 = -80000   → -32768 (CLIP)
        //     +500  ×4 =  +2000     (safe)
        //       0  ×4 =       0     (safe)
        //   +8000   ×4 = +32000     (safe)
        //   -9000   ×4 = -36000   → -32768 (CLIP)
        final input = _pcm([1000, 20000, -20000, 500, 0, 8000, -9000]);
        final processor = PcmGainProcessor(gain: 4.0);

        final output = _samples(processor.process(input));

        expect(output, [4000, 32767, -32768, 2000, 0, 32000, -32768]);
        expect(processor.clippedSamples, 3);
      },
    );

    test('clippedSamples accumulates across multiple process() calls', () {
      final processor = PcmGainProcessor(gain: 10.0);

      processor.process(_pcm([10000])); // +1 clip
      processor.process(_pcm([-10000, 1])); // +1 clip (the -10000 sample)
      processor.process(_pcm([5000])); // 0 clips: 50000 → +32767 IS a clip

      // Re-check: gain=10.0 * 5000 = 50000 → clamps to +32767 → IS a clip.
      // So the running total is 3.
      expect(processor.clippedSamples, 3);
    });
  });
}

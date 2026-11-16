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

/// Limiter ceiling (-1 dBFS) in int16 units, rounded up.
const int _ceiling = 29205;

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

    test('gain=10.0 bends +10000 below -1 dBFS and counts one clip', () {
      final processor = PcmGainProcessor(gain: 10.0);

      final output = _samples(processor.process(_pcm([10000])));

      expect(output.single, inInclusiveRange(25000, _ceiling));
      expect(processor.clippedSamples, 1);
    });

    test('gain=10.0 bends -10000 above -(-1 dBFS) and counts one clip', () {
      final processor = PcmGainProcessor(gain: 10.0);

      final output = _samples(processor.process(_pcm([-10000])));

      expect(output.single, inInclusiveRange(-_ceiling, -25000));
      expect(processor.clippedSamples, 1);
    });

    test('the limiter is soft: louder input stays louder, never cut flat', () {
      final processor = PcmGainProcessor(gain: 4.0);

      final output = _samples(processor.process(_pcm([7000, 9000, 20000])));

      expect(output[0], lessThan(output[1]));
      expect(output[1], lessThan(output[2]));
      expect(output[2], lessThanOrEqualTo(_ceiling));
      // 9000 × 4 and 20000 × 4 leave the int16 range; 7000 × 4 does not.
      expect(processor.clippedSamples, 2);
    });

    test('counters accumulate across process() calls', () {
      final processor = PcmGainProcessor(gain: 10.0);

      processor.process(_pcm([10000]));
      processor.process(_pcm([-10000, 1]));
      processor.process(_pcm([5000]));

      expect(processor.clippedSamples, 3);
      expect(processor.sampleCount, 4);
    });

    test('the identity gain counts samples but changes nothing', () {
      final processor = PcmGainProcessor(gain: 1.0);
      processor.process(_pcm([1, 2, 3]));
      expect(processor.sampleCount, 3);
      expect(processor.clippedSamples, 0);
    });
  });
}

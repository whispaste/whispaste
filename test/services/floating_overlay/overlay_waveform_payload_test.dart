import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/overlay_waveform_payload.dart';

/// ticket phase 2, plan item 5: the macOS waveform path sends one byte per bar
/// instead of one 8-byte double, and skips a payload identical to the last one.
void main() {
  group('encodeWaveformBars', () {
    test('one byte per bar, same count as the input', () {
      final bytes = encodeWaveformBars(const [0.0, 0.5, 1.0]);

      expect(bytes, isA<Uint8List>());
      expect(bytes.length, 3);
    });

    test('0.0 maps to 0, 1.0 maps to 255, the midpoint rounds', () {
      expect(encodeWaveformBars(const [0.0, 1.0]), [0, 255]);
      expect(encodeWaveformBars(const [0.5]), [128]);
    });

    test('out-of-range levels are clamped', () {
      expect(encodeWaveformBars(const [-0.2, 1.7]), [0, 255]);
    });

    test('the payload is 8x smaller than the 8-byte double list', () {
      const levels = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8];
      final doubleBytes = levels.length * 8;

      expect(doubleBytes ~/ encodeWaveformBars(levels).lengthInBytes, 8);
    });
  });

  group('decodeWaveformBars', () {
    test('a byte payload round-trips within one quantisation step', () {
      const levels = [0.0, 0.1, 0.333, 0.75, 1.0];
      final back = decodeWaveformBars(encodeWaveformBars(levels));

      expect(back.length, levels.length);
      for (var i = 0; i < levels.length; i++) {
        expect(back[i], closeTo(levels[i], 1 / 255));
      }
    });

    test('a plain double list (other platforms) is still accepted', () {
      expect(decodeWaveformBars(<double>[0.25, 0.5]), [0.25, 0.5]);
    });

    test('a malformed payload decodes to an empty list', () {
      expect(decodeWaveformBars('nope'), isEmpty);
      expect(decodeWaveformBars(null), isEmpty);
    });
  });

  group('WaveformSendGate', () {
    test('the first payload is always sent', () {
      final gate = WaveformSendGate();
      expect(gate.accept(encodeWaveformBars(const [0.0])), isTrue);
    });

    test('an identical payload is suppressed (silence, settled release)', () {
      final gate = WaveformSendGate();
      gate.accept(encodeWaveformBars(const [0.0, 0.2]));

      expect(gate.accept(encodeWaveformBars(const [0.0, 0.2])), isFalse);
      expect(gate.accept(encodeWaveformBars(const [0.0, 0.3])), isTrue);
    });

    test('a suppressed payload does not become the new baseline', () {
      final gate = WaveformSendGate();
      gate.accept(encodeWaveformBars(const [0.5]));
      gate.accept(encodeWaveformBars(const [0.9]));

      expect(gate.accept(encodeWaveformBars(const [0.5])), isTrue);
    });
  });
}

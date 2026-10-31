/// Tests for [SpeechLevelMapper].
///
/// The mapper performs a pure, linear mapping of raw dBFS values from the
/// perceptual speech range `[floorDb, ceilingDb] = [-50, -3]` to a normalised
/// visual level in `[0.0, 1.0]`, with a hard clamp outside that window and a
/// defined zero-fallback for `double.negativeInfinity` and `double.nan`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/audio/speech_level_mapper.dart';

void main() {
  group('SpeechLevelMapper.map — table values', () {
    const mapper = SpeechLevelMapper();

    test('-60 dB clamps to 0.0 (below floor)', () {
      expect(mapper.map(-60.0), 0.0);
    });

    test('-50 dB maps to 0.0 (floor edge)', () {
      expect(mapper.map(-50.0), 0.0);
    });

    test('-26.5 dB maps to ~0.5 (midpoint of [-50, -3])', () {
      expect(mapper.map(-26.5), closeTo(0.5, 0.01));
    });

    test('-3 dB maps to 1.0 (ceiling edge)', () {
      expect(mapper.map(-3.0), 1.0);
    });

    test('0 dB clamps to 1.0 (above ceiling)', () {
      expect(mapper.map(0.0), 1.0);
    });
  });

  group('SpeechLevelMapper.map — edge values', () {
    const mapper = SpeechLevelMapper();

    test('negativeInfinity → 0.0', () {
      expect(mapper.map(double.negativeInfinity), 0.0);
    });

    test('NaN → 0.0', () {
      expect(mapper.map(double.nan), 0.0);
    });
  });

  group('SpeechLevelMapper.map — monotonicity', () {
    const mapper = SpeechLevelMapper();

    // Deterministic sample sweep spanning below floor, inside the window,
    // and above ceiling. Each consecutive pair satisfies db1 < db2.
    final samples = <double>[
      -80.0,
      -55.0,
      -50.0,
      -45.0,
      -40.0,
      -30.0,
      -20.0,
      -10.0,
      -5.0,
      -3.0,
      0.0,
      5.0,
    ];

    test('non-decreasing across ≥ 10 deterministic pairs', () {
      // 12 samples → 11 consecutive pairs (> 10 required).
      for (var i = 0; i < samples.length - 1; i++) {
        final db1 = samples[i];
        final db2 = samples[i + 1];
        final m1 = mapper.map(db1);
        final m2 = mapper.map(db2);
        expect(
          m1 <= m2,
          isTrue,
          reason:
              'monotonicity violated at pair ($db1 → $m1, $db2 → $m2): '
              'expected map($db1) <= map($db2)',
        );
      }
    });
  });

  group('SpeechLevelMapper — named constants', () {
    test('floorDb is -50.0', () {
      expect(speechLevelFloorDb, -50.0);
    });

    test('ceilingDb is -3.0', () {
      expect(speechLevelCeilingDb, -3.0);
    });
  });
}

/// Tests for [SpeechLevelMapper], the one dBFS → level curve every live
/// waveform and the safety guard read through.
///
/// Logic only: the noise floor rests at 0, normal speech lands mid-range,
/// the top is reserved for loud input, the output never leaves [0, 1] and
/// never falls as the input rises.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/audio/level_smoother.dart';
import 'package:whispaste/services/audio/speech_level_mapper.dart';
import 'package:whispaste/services/recording/safety_guard.dart';

void main() {
  const mapper = SpeechLevelMapper();

  group('SpeechLevelMapper.map', () {
    test('the noise floor and below rest at 0', () {
      expect(mapper.map(-60.0), 0.0);
      expect(mapper.map(-80.0), 0.0);
      expect(mapper.map(double.negativeInfinity), 0.0);
      expect(mapper.map(double.nan), 0.0);
    });

    test('normal speech (-30..-18 dBFS) lands mid-range', () {
      for (var db = -30.0; db <= -18.0; db += 1.0) {
        expect(mapper.map(db), inInclusiveRange(0.4, 0.75), reason: '$db');
      }
    });

    test('only -8 dBFS and louder reach the top', () {
      expect(mapper.map(-9.0), lessThan(1.0));
      expect(mapper.map(-8.0), 1.0);
      expect(mapper.map(0.0), 1.0);
      expect(mapper.map(12.0), 1.0);
    });

    test('rises monotonically and never leaves [0, 1]', () {
      var previous = 0.0;
      for (var db = -90.0; db <= 10.0; db += 0.5) {
        final level = mapper.map(db);
        expect(level, inInclusiveRange(0.0, 1.0), reason: '$db');
        expect(level, greaterThanOrEqualTo(previous), reason: '$db');
        previous = level;
      }
    });

    test('the safety guard keeps its silence point at about -49 dBFS', () {
      expect(mapper.map(-49.5), lessThan(SafetyGuard.silenceThreshold));
      expect(mapper.map(-48.5), greaterThan(SafetyGuard.silenceThreshold));
    });
  });

  group('LevelSmoother', () {
    test('a syllable peak shows within one 40 ms meter window', () {
      final smoother = LevelSmoother();
      expect(smoother.step(0.7, 40), greaterThan(0.6));
    });

    test('a pause between syllables shows as a dip', () {
      final smoother = LevelSmoother()..step(0.7, 1000);
      // ~200 ms gap between syllables.
      for (var i = 0; i < 5; i++) {
        smoother.step(0.0, 40);
      }
      expect(smoother.value, lessThan(0.7 * 0.4));
    });

    test('falls slower than it rises', () {
      final rising = LevelSmoother().step(0.7, 40);
      final falling = (LevelSmoother()..step(0.7, 1000)).step(0.0, 40);
      expect(0.7 - falling, lessThan(rising));
    });

    test('never overshoots the target and stays in [0, 1]', () {
      final smoother = LevelSmoother();
      for (final target in [1.0, 0.0, 0.6, 1.0, 0.2]) {
        for (var i = 0; i < 20; i++) {
          expect(smoother.step(target, 40), inInclusiveRange(0.0, 1.0));
        }
        expect(smoother.value, closeTo(target, 0.01));
      }
    });

    test('reset returns to rest', () {
      final smoother = LevelSmoother()..step(1.0, 1000);
      smoother.reset();
      expect(smoother.value, 0.0);
    });
  });
}

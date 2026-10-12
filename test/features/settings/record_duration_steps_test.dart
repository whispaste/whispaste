import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/record_duration_steps.dart';

void main() {
  group('record duration steps', () {
    test('grid is 30 s, 1-10 min, 15-20 min, 30-60 min', () {
      expect(kRecordDurationStepSeconds, [
        30,
        60,
        120,
        180,
        240,
        300,
        360,
        420,
        480,
        540,
        600,
        900,
        1200,
        1800,
        2700,
        3600,
      ]);
      expect(kRecordDurationStepCount, 17);
    });

    test('Unlimited is the last (rightmost) position and stored as 0', () {
      expect(kRecordDurationUnlimitedIndex, 16);
      expect(recordDurationSecondsAt(kRecordDurationUnlimitedIndex), 0);
      expect(recordDurationStepIndex(0), kRecordDurationUnlimitedIndex);
    });

    test('index to seconds round-trips on every step', () {
      for (var i = 0; i < kRecordDurationStepSeconds.length; i++) {
        final seconds = kRecordDurationStepSeconds[i];
        expect(recordDurationSecondsAt(i), seconds);
        expect(recordDurationStepIndex(seconds), i);
      }
    });

    test('out-of-range indices are clamped', () {
      expect(recordDurationSecondsAt(-1), 30);
      expect(recordDurationSecondsAt(99), 0);
    });

    test('60 minutes is reachable and sits just before Unlimited', () {
      final index = recordDurationStepIndex(3600);
      expect(recordDurationSecondsAt(index), 3600);
      expect(index, kRecordDurationUnlimitedIndex - 1);
    });

    test('legacy off-grid values map to the nearest step', () {
      // 90 s is equidistant from 60 s and 120 s: the shorter limit wins.
      expect(recordDurationSecondsAt(recordDurationStepIndex(90)), 60);
      // 150 s is equidistant from 120 s and 180 s: the shorter limit wins.
      expect(recordDurationSecondsAt(recordDurationStepIndex(150)), 120);
      // 100 s is nearer to 120 s than to 60 s.
      expect(recordDurationSecondsAt(recordDurationStepIndex(100)), 120);
      // 10 s (below the smallest step) maps to 30 s.
      expect(recordDurationSecondsAt(recordDurationStepIndex(10)), 30);
      // 7200 s (above the largest step) maps to 60 min, not Unlimited.
      expect(recordDurationStepIndex(7200), kRecordDurationUnlimitedIndex - 1);
    });

    test('negative stored values count as Unlimited', () {
      expect(recordDurationStepIndex(-5), kRecordDurationUnlimitedIndex);
    });

    test('mapping never returns a position past Unlimited', () {
      for (var s = -10; s <= 8000; s += 7) {
        final index = recordDurationStepIndex(s);
        expect(index, inInclusiveRange(0, kRecordDurationUnlimitedIndex));
      }
    });
  });
}

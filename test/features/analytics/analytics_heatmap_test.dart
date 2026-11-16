import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';

/// #887: heatmap layout and the streak with one forgiven day.
void main() {
  group('analyticsStreakDays', () {
    test('one missed day does not break the streak', () {
      expect(analyticsStreakDays([1, 1, 0, 1, 1]), 4);
    });

    test('two missed days in a row end it', () {
      expect(analyticsStreakDays([1, 1, 0, 0, 1]), 1);
    });

    test('a quiet today is not a miss yet', () {
      expect(analyticsStreakDays([1, 1, 1, 0]), 3);
      expect(analyticsStreakDays([1, 0, 1, 0]), 2);
    });

    test('no activity, no streak', () {
      expect(analyticsStreakDays(const []), 0);
      expect(analyticsStreakDays([0, 0, 0]), 0);
    });
  });

  group('heatmapCells', () {
    // 2026-11-11 is a Wednesday: row 2 of the last column.
    final wednesday = DateTime(2026, 11, 11);

    test('today sits in the last column, later days stay empty', () {
      final cells = heatmapCells([4, 9], wednesday);
      expect(cells, hasLength(16 * 7));
      const last = 15 * 7;
      expect(cells[last + 2], 9); // today
      expect(cells[last + 1], 4); // yesterday
      expect(cells[last + 0], 0); // before the data starts
      expect(cells.sublist(last + 3), everyElement(isNull));
    });

    test('a full week back is the same row one column left', () {
      final daily = List<int>.generate(8, (i) => i + 1); // today = 8
      final cells = heatmapCells(daily, wednesday);
      expect(cells[14 * 7 + 2], 1);
    });
  });

  group('snapshot', () {
    test('round-trips the figures', () {
      const data = AnalyticsData(
        totalRecordings: 3,
        totalDurationMinutes: 2,
        totalWords: 40,
        totalDurationSec: 95.5,
        timeSavedMinutes: 1,
        dailyActivity: [0, 2, 1],
        modelUsage: [],
        durationBuckets: [1, 1, 1, 0, 0],
        localSavingsUsd: 0.5,
        cloudCostUsd: 0.25,
        activeDays: 2,
      );
      final back = AnalyticsData.fromSnapshotJson(data.toSnapshotJson())!;
      expect(back.totalRecordings, 3);
      expect(back.totalDurationSec, 95.5);
      expect(back.dailyActivity, [0, 2, 1]);
      expect(back.durationBuckets, [1, 1, 1, 0, 0]);
      expect(back.cloudCostUsd, 0.25);
      expect(back.activeDays, 2);
      expect(back.failedPanels, isEmpty);
    });

    test('an unreadable or foreign snapshot is ignored', () {
      expect(AnalyticsData.fromSnapshotJson('not json'), isNull);
      expect(AnalyticsData.fromSnapshotJson('{"v":2}'), isNull);
    });
  });
}

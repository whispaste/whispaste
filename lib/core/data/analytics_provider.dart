/// Riverpod providers for the analytics dashboard.
///
/// Queries real data from [HistoryDatabase] and exposes it as
/// [AnalyticsData] to the UI via [analyticsProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// All aggregated analytics data needed by the dashboard.
class AnalyticsData {
  const AnalyticsData({
    required this.totalRecordings,
    required this.totalDurationMinutes,
    required this.totalWords,
    required this.timeSavedMinutes,
    required this.weeklyActivity,
    required this.modelUsage,
    required this.durationBuckets,
    required this.localSavingsUsd,
    required this.cloudCostUsd,
  });

  static const empty = AnalyticsData(
    totalRecordings: 0,
    totalDurationMinutes: 0,
    totalWords: 0,
    timeSavedMinutes: 0,
    weeklyActivity: [0, 0, 0, 0, 0, 0, 0],
    modelUsage: [],
    durationBuckets: [0, 0, 0, 0, 0],
    localSavingsUsd: 0,
    cloudCostUsd: 0,
  );

  final int totalRecordings;
  final int totalDurationMinutes;
  final int totalWords;

  /// Estimated time saved vs. manual typing (dictation is ~3× faster).
  final int timeSavedMinutes;

  /// Recordings per day-of-week: [Mon, Tue, Wed, Thu, Fri, Sat, Sun].
  final List<double> weeklyActivity;

  /// Per-model usage breakdown.
  final List<AnalyticsModelUsage> modelUsage;

  /// Duration distribution: [<15s, 15-30s, 30-60s, 1-3m, >3m].
  final List<int> durationBuckets;

  final double localSavingsUsd;
  final double cloudCostUsd;

  bool get isEmpty => totalRecordings == 0;
}

// ---------------------------------------------------------------------------
// Period filter
// ---------------------------------------------------------------------------

enum AnalyticsPeriod { last7d, last30d, last90d, allTime }

/// User-selected analytics period. Defaults to all-time.
final analyticsPeriodProvider =
    NotifierProvider<AnalyticsPeriodNotifier, AnalyticsPeriod>(
      AnalyticsPeriodNotifier.new,
    );

class AnalyticsPeriodNotifier extends Notifier<AnalyticsPeriod> {
  @override
  AnalyticsPeriod build() => AnalyticsPeriod.allTime;

  void setPeriod(AnalyticsPeriod period) => state = period;
}

// ---------------------------------------------------------------------------
// Analytics provider — auto-refreshes when period changes
// ---------------------------------------------------------------------------

final analyticsProvider = FutureProvider<AnalyticsData>((ref) async {
  final db = ref.watch(historyDatabaseProvider);
  final period = ref.watch(analyticsPeriodProvider);

  final since = _sinceForPeriod(period);

  final results = await Future.wait([
    db.analyticsEntryCount(since: since), // 0
    db.analyticsTotalDurationSec(since: since), // 1
    db.analyticsTotalWords(since: since), // 2
    db.analyticsTotalCostUsd(since: since), // 3
    db.analyticsLocalSavingsUsd(since: since), // 4
    db.analyticsModelUsage(since: since), // 5
    db.analyticsWeeklyActivity(), // 6 — always last 7 days
    db.analyticsDurationBuckets(since: since), // 7
  ]);

  final totalRecordings = results[0] as int;
  final totalDurationSec = results[1] as double;
  final totalWords = results[2] as int;
  final cloudCost = results[3] as double;
  final localSavings = results[4] as double;
  final modelUsage = results[5] as List<AnalyticsModelUsage>;
  final weeklyActivity = results[6] as List<double>;
  final durationBuckets = results[7] as List<int>;

  final totalMinutes = (totalDurationSec / 60).round();
  // Estimate: dictation is ~3× faster than typing → saved 2/3 of the time.
  final timeSaved = (totalMinutes * 2 / 3).round();

  return AnalyticsData(
    totalRecordings: totalRecordings,
    totalDurationMinutes: totalMinutes,
    totalWords: totalWords,
    timeSavedMinutes: timeSaved,
    weeklyActivity: weeklyActivity,
    modelUsage: modelUsage,
    durationBuckets: durationBuckets,
    localSavingsUsd: localSavings,
    cloudCostUsd: cloudCost,
  );
});

DateTime? _sinceForPeriod(AnalyticsPeriod period) {
  final now = DateTime.now();
  return switch (period) {
    AnalyticsPeriod.last7d => now.subtract(const Duration(days: 7)),
    AnalyticsPeriod.last30d => now.subtract(const Duration(days: 30)),
    AnalyticsPeriod.last90d => now.subtract(const Duration(days: 90)),
    AnalyticsPeriod.allTime => null,
  };
}

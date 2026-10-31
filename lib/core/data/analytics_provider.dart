/// Riverpod providers for the analytics dashboard.
///
/// Queries real data from [HistoryDatabase] and exposes it as
/// [AnalyticsData] to the UI via [analyticsProvider].
library;

import 'dart:math' as math;

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
    this.totalDurationSec = 0,
    required this.timeSavedMinutes,
    required this.weeklyActivity,
    required this.modelUsage,
    required this.durationBuckets,
    required this.localSavingsUsd,
    required this.cloudCostUsd,
    this.averageStopToTextMs,
    this.wording = AnalyticsWording.zero,
    this.topCorrections = const <AnalyticsCorrection>[],
    this.activeDays = 0,
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

  /// Exact dictated time in seconds; [totalDurationMinutes] is its rounding.
  final double totalDurationSec;

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

  /// Average time from the recording stop to the delivered text in
  /// milliseconds, local-only (XP-6-09). `null` when no sample has one yet.
  final double? averageStopToTextMs;

  /// Raw versus revised words and the number of transform actions.
  final AnalyticsWording wording;

  /// Most frequent corrections, most frequent first.
  final List<AnalyticsCorrection> topCorrections;

  /// Distinct days of the period with at least one dictated word, from the
  /// daily aggregates (a statistics reset clears them too).
  final int activeDays;

  bool get isEmpty => totalRecordings == 0;

  /// Words per dictated minute, or null before any dictated time exists.
  double? get wordsPerMinute =>
      totalDurationSec < 1 ? null : totalWords / (totalDurationSec / 60);
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
  return loadAnalyticsData(db, since: _sinceForPeriod(period));
});

/// The dashboard figures of [db] since [since] (null: all time). Shared by the
/// Statistik page and the Übersicht figures, so both count the same way.
Future<AnalyticsData> loadAnalyticsData(
  HistoryDatabase db, {
  DateTime? since,
}) async {
  final results = await Future.wait([
    db.analyticsEntryCount(since: since), // 0
    db.analyticsTotalDurationSec(since: since), // 1
    db.analyticsTotalWords(since: since), // 2
    db.analyticsTotalCostUsd(since: since), // 3
    db.analyticsLocalSavingsUsd(since: since), // 4
    db.analyticsModelUsage(since: since), // 5
    db.analyticsWeeklyActivity(), // 6 — always last 7 days
    db.analyticsDurationBuckets(since: since), // 7
    db.analyticsAverageStopToTextMs(since: since), // 8
    db.analyticsWording(since: since), // 9
    db.analyticsTopCorrections(since: since), // 10
    db.analyticsActiveDays(since: since), // 11
  ]);

  final totalRecordings = results[0] as int;
  final totalDurationSec = results[1] as double;
  final totalWords = results[2] as int;
  final cloudCost = results[3] as double;
  final localSavings = results[4] as double;
  final modelUsage = results[5] as List<AnalyticsModelUsage>;
  final weeklyActivity = results[6] as List<double>;
  final durationBuckets = results[7] as List<int>;
  final averageStopToTextMs = results[8] as double?;
  final wording = results[9] as AnalyticsWording;
  final topCorrections = results[10] as List<AnalyticsCorrection>;
  final activeDays = results[11] as int;

  final totalMinutes = (totalDurationSec / 60).round();
  final timeSaved = analyticsTimeSavedMinutes(
    totalWords: totalWords,
    totalDurationSec: totalDurationSec,
  );

  return AnalyticsData(
    totalRecordings: totalRecordings,
    totalDurationMinutes: totalMinutes,
    totalWords: totalWords,
    totalDurationSec: totalDurationSec,
    timeSavedMinutes: timeSaved,
    weeklyActivity: weeklyActivity,
    modelUsage: modelUsage,
    durationBuckets: durationBuckets,
    localSavingsUsd: localSavings,
    cloudCostUsd: cloudCost,
    averageStopToTextMs: averageStopToTextMs,
    wording: wording,
    topCorrections: topCorrections,
    activeDays: activeDays,
  );
}

DateTime? _sinceForPeriod(AnalyticsPeriod period) {
  final now = DateTime.now();
  return switch (period) {
    AnalyticsPeriod.last7d => now.subtract(const Duration(days: 7)),
    AnalyticsPeriod.last30d => now.subtract(const Duration(days: 30)),
    AnalyticsPeriod.last90d => now.subtract(const Duration(days: 90)),
    AnalyticsPeriod.allTime => null,
  };
}

/// The typing speed the time-saved estimate assumes, in words per minute.
/// Shown next to the figure, so the estimate states its own assumption.
const kAnalyticsTypingWordsPerMinute = 50;

/// Minutes saved over a period: the time typing [totalWords] would have
/// taken at [kAnalyticsTypingWordsPerMinute], minus the time spent speaking
/// them. Never negative: a period of slow, long recordings saved nothing
/// rather than cost time.
int analyticsTimeSavedMinutes({
  required int totalWords,
  required double totalDurationSec,
}) {
  final typing = totalWords / kAnalyticsTypingWordsPerMinute;
  final spoken = totalDurationSec / 60;
  return math.max(0, (typing - spoken).round());
}

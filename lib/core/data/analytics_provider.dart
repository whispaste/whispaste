/// Riverpod providers for the analytics dashboard.
///
/// Queries real data from [HistoryDatabase] and exposes it as
/// [AnalyticsData] to the UI via [analyticsProvider]. Every figure comes from
/// the daily aggregates or the correction counters, never from history text
/// (issue #887), and the last result per period is kept as a snapshot that
/// [analyticsSnapshotProvider] shows at once on the next open.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/logging/app_logger.dart';

final _log = AppLogger('Analytics');

/// The dashboard panels that load and fail independently (issue #887).
enum AnalyticsPanel {
  overview,
  activity,
  models,
  durations,
  costs,
  wording,
  corrections,
}

/// Days of daily activity the heatmap and the streak look back over.
const kAnalyticsActivityDays = 7 * 52;

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
    this.dailyActivity = const <int>[],
    required this.modelUsage,
    required this.durationBuckets,
    required this.localSavingsUsd,
    required this.cloudCostUsd,
    this.averageStopToTextMs,
    this.wording = AnalyticsWording.zero,
    this.topCorrections = const <AnalyticsCorrection>[],
    this.activeDays = 0,
    this.failedPanels = const <AnalyticsPanel>{},
  });

  static const empty = AnalyticsData(
    totalRecordings: 0,
    totalDurationMinutes: 0,
    totalWords: 0,
    timeSavedMinutes: 0,
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

  /// Recordings per local day, oldest first and today last, independent of
  /// the period (heatmap and streak). Shorter lists mean zeros before them.
  final List<int> dailyActivity;

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

  /// Panels whose query failed; each shows its own error state with a retry
  /// instead of the whole page failing (issue #887).
  final Set<AnalyticsPanel> failedPanels;

  /// No recordings in the period. A failed overview is not "empty": the
  /// count is unknown, so the dashboard shows that panel's error instead.
  bool get isEmpty =>
      totalRecordings == 0 && !failedPanels.contains(AnalyticsPanel.overview);

  /// Consecutive active days ending today, with one missed day forgiven.
  int get streakDays => analyticsStreakDays(dailyActivity);

  /// The figures as a local snapshot (counts and correction pairs only).
  String toSnapshotJson() => jsonEncode({
    'v': 1,
    'recordings': totalRecordings,
    'minutes': totalDurationMinutes,
    'words': totalWords,
    'durationSec': totalDurationSec,
    'saved': timeSavedMinutes,
    'daily': dailyActivity,
    'models': [
      for (final m in modelUsage)
        {'model': m.model, 'count': m.count, 'fraction': m.fraction},
    ],
    'buckets': durationBuckets,
    'savingsUsd': localSavingsUsd,
    'costUsd': cloudCostUsd,
    'stopToTextMs': averageStopToTextMs,
    'raw': wording.rawWords,
    'revised': wording.revisedWords,
    'actions': wording.actionCount,
    'corrections': [
      for (final c in topCorrections)
        {'source': c.sourceText, 'target': c.targetText, 'count': c.count},
    ],
    'activeDays': activeDays,
  });

  /// Parses [toSnapshotJson]; null for anything unreadable or of another
  /// snapshot version, so a bad snapshot only means no instant figures.
  static AnalyticsData? fromSnapshotJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['v'] != 1) return null;
      List<int> ints(Object? v) => [for (final e in v! as List) e as int];
      return AnalyticsData(
        totalRecordings: j['recordings'] as int,
        totalDurationMinutes: j['minutes'] as int,
        totalWords: j['words'] as int,
        totalDurationSec: (j['durationSec'] as num).toDouble(),
        timeSavedMinutes: j['saved'] as int,
        dailyActivity: ints(j['daily']),
        modelUsage: [
          for (final m in j['models'] as List)
            AnalyticsModelUsage(
              model: (m as Map<String, dynamic>)['model'] as String,
              count: m['count'] as int,
              fraction: (m['fraction'] as num).toDouble(),
            ),
        ],
        durationBuckets: ints(j['buckets']),
        localSavingsUsd: (j['savingsUsd'] as num).toDouble(),
        cloudCostUsd: (j['costUsd'] as num).toDouble(),
        averageStopToTextMs: (j['stopToTextMs'] as num?)?.toDouble(),
        wording: AnalyticsWording(
          rawWords: j['raw'] as int,
          revisedWords: j['revised'] as int,
          actionCount: j['actions'] as int,
        ),
        topCorrections: [
          for (final c in j['corrections'] as List)
            AnalyticsCorrection(
              sourceText: (c as Map<String, dynamic>)['source'] as String,
              targetText: c['target'] as String,
              count: c['count'] as int,
            ),
        ],
        activeDays: j['activeDays'] as int,
      );
    } on Object {
      return null;
    }
  }

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
  final data = await loadAnalyticsData(db, since: _sinceForPeriod(period));
  // Only complete figures become the next open's snapshot.
  if (data.failedPanels.isEmpty) {
    unawaited(
      db
          .writeAppMeta(analyticsSnapshotKey(period), data.toSnapshotJson())
          .catchError((Object e) => _log.warning('Snapshot not saved', e)),
    );
  }
  return data;
});

/// The `app_meta` key of the snapshot for [period].
String analyticsSnapshotKey(AnalyticsPeriod period) =>
    '${HistoryDatabase.analyticsSnapshotKeyPrefix}${period.name}';

/// The last complete figures of the selected period, read in one lookup so
/// the page shows them at once while [analyticsProvider] refreshes in the
/// background. Null when there is none or it cannot be read.
final analyticsSnapshotProvider = FutureProvider.autoDispose<AnalyticsData?>((
  ref,
) async {
  final period = ref.watch(analyticsPeriodProvider);
  try {
    final db = ref.watch(historyDatabaseProvider);
    final raw = await db.readAppMeta(analyticsSnapshotKey(period));
    return raw == null ? null : AnalyticsData.fromSnapshotJson(raw);
  } on Object catch (e) {
    _log.warning('Snapshot not read', e);
    return null;
  }
});

/// The dashboard figures of [db] since [since] (null: all time). Shared by the
/// Statistik page and the Übersicht figures, so both count the same way.
///
/// Each panel's queries are guarded on their own: a failing one yields its
/// fallback and lands in [AnalyticsData.failedPanels], the rest still load.
Future<AnalyticsData> loadAnalyticsData(
  HistoryDatabase db, {
  DateTime? since,
}) async {
  final failed = <AnalyticsPanel>{};
  Future<T> guard<T>(
    AnalyticsPanel panel,
    Future<T> Function() query,
    T fallback,
  ) async {
    try {
      return await query();
    } on Object catch (e, st) {
      _log.warning('Analytics panel ${panel.name} failed', e, st);
      failed.add(panel);
      return fallback;
    }
  }

  const overview = AnalyticsPanel.overview;
  final results = await Future.wait<Object?>([
    guard(overview, () => db.analyticsEntryCount(since: since), 0), // 0
    guard(overview, () => db.analyticsTotalDurationSec(since: since), 0.0),
    guard(overview, () => db.analyticsTotalWords(since: since), 0), // 2
    guard(
      AnalyticsPanel.costs,
      () => db.analyticsTotalCostUsd(since: since),
      0.0,
    ), // 3
    guard(
      AnalyticsPanel.costs,
      () => db.analyticsLocalSavingsUsd(since: since),
      0.0,
    ), // 4
    guard(
      AnalyticsPanel.models,
      () => db.analyticsModelUsage(since: since),
      const <AnalyticsModelUsage>[],
    ), // 5
    guard(
      AnalyticsPanel.activity,
      () => db.analyticsDailyActivity(days: kAnalyticsActivityDays),
      const <int>[],
    ), // 6 — independent of the period
    guard(
      AnalyticsPanel.durations,
      () => db.analyticsDurationBuckets(since: since),
      const [0, 0, 0, 0, 0],
    ), // 7
    guard<double?>(
      overview,
      () => db.analyticsAverageStopToTextMs(since: since),
      null,
    ), // 8
    guard(
      AnalyticsPanel.wording,
      () => db.analyticsWording(since: since),
      AnalyticsWording.zero,
    ), // 9
    guard(
      AnalyticsPanel.corrections,
      () => db.analyticsTopCorrections(since: since),
      const <AnalyticsCorrection>[],
    ), // 10
    guard(overview, () => db.analyticsActiveDays(since: since), 0), // 11
  ]);

  final totalRecordings = results[0]! as int;
  final totalDurationSec = results[1]! as double;
  final totalWords = results[2]! as int;
  final cloudCost = results[3]! as double;
  final localSavings = results[4]! as double;
  final modelUsage = results[5]! as List<AnalyticsModelUsage>;
  final dailyActivity = results[6]! as List<int>;
  final durationBuckets = results[7]! as List<int>;
  final averageStopToTextMs = results[8] as double?;
  final wording = results[9]! as AnalyticsWording;
  final topCorrections = results[10]! as List<AnalyticsCorrection>;
  final activeDays = results[11]! as int;

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
    dailyActivity: dailyActivity,
    modelUsage: modelUsage,
    durationBuckets: durationBuckets,
    localSavingsUsd: localSavings,
    cloudCostUsd: cloudCost,
    averageStopToTextMs: averageStopToTextMs,
    wording: wording,
    topCorrections: topCorrections,
    activeDays: activeDays,
    failedPanels: failed,
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

/// Consecutive active days ending today in [daily] (oldest first, today
/// last), forgiving up to [graceDays] missed days in a row: a single gap does
/// not end the streak, [graceDays] + 1 do. Today still being quiet is not a
/// miss, the day is not over. Only active days count towards the result.
int analyticsStreakDays(List<int> daily, {int graceDays = 1}) {
  var streak = 0;
  var missed = 0;
  for (var i = daily.length - 1; i >= 0; i--) {
    if (daily[i] > 0) {
      streak++;
      missed = 0;
      continue;
    }
    if (i == daily.length - 1) continue;
    missed++;
    if (missed > graceDays) break;
  }
  return streak;
}

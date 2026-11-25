/// One-time activation events: `activation/dictations` with the name `1`, `5`,
/// `25` or `100` when the count of successful dictations first reaches that
/// threshold. Content-free: only the threshold id leaves the device, through
/// the consent-gated [TelemetryService].
///
/// State lives in SharedPreferences (a counter and the reached thresholds), so
/// each threshold fires once per install. An install that already has
/// dictations when this first runs starts from its current count and does not
/// report thresholds it passed earlier.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import 'review_prompt_service.dart' show countEligibleRecordings;
import 'shared_prefs_safe_read.dart';
import 'telemetry_model_buckets.dart' show activationMilestones;
import 'telemetry_service.dart';

const _keyCount = 'activation_dictation_count';
const _keyReached = 'activation_milestones_reached';

final _log = AppLogger('Activation');

/// Thresholds in [thresholds] that [count] has reached and that are not in
/// [alreadyReached] yet, ascending. Pure.
List<int> newlyReachedMilestones({
  required int count,
  required Set<int> alreadyReached,
  List<int> thresholds = activationMilestones,
}) => [
  for (final t in thresholds)
    if (count >= t && !alreadyReached.contains(t)) t,
];

/// Counts one successful dictation and reports newly reached thresholds when
/// [report] is true (usage sharing on, onboarding done). With [report] false
/// the thresholds are marked reached silently, so turning sharing on later does
/// not send old milestones. Never throws.
Future<void> countActivationDictation(Ref ref, {required bool report}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    var count = readIntPrefSafe(prefs, _keyCount);
    var reached = _readReached(prefs);
    if (count == null) {
      // First run of this code: take over the existing history. At most one
      // entry is a fresh install whose first dictation may already be saved.
      final existing = await countEligibleRecordings(
        prefs,
        ref.read(historyDatabaseProvider),
      );
      count = existing <= 1 ? 0 : existing;
      reached = {
        for (final t in activationMilestones)
          if (count >= t) t,
      };
    }
    count += 1;
    final fresh = newlyReachedMilestones(count: count, alreadyReached: reached);
    await prefs.setInt(_keyCount, count);
    if (fresh.isEmpty) return;
    await prefs.setStringList(_keyReached, [
      for (final t in {...reached, ...fresh}) '$t',
    ]);
    if (!report || !ref.mounted) return;
    final telemetry = ref.read(telemetryProvider);
    for (final t in fresh) {
      telemetry.trackEvent(
        category: 'activation',
        action: 'dictations',
        name: '$t',
      );
    }
  } on Object catch (e) {
    _log.debug('activation count skipped: $e');
  }
}

Set<int> _readReached(SharedPreferences prefs) {
  final raw = prefs.get(_keyReached);
  if (raw is! List) return <int>{};
  return {for (final v in raw) ?int.tryParse('$v')};
}

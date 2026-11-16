import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';

/// Static one-shot values for the bounded history readers of the app shell
/// (tray, side panel, Übersicht, first steps, figures; #1643). Live Drift
/// streams under FakeAsync would keep pending timers.
List historySourceOverrides([List<HistoryEntry> rows = const []]) => [
  historyHeadProvider.overrideWith(
    (ref, limit) => Stream.value(rows.take(limit).toList()),
  ),
  latestRecordingsProvider.overrideWith(
    (ref) => Stream.value(rows.take(kLatestRecordingsLimit).toList()),
  ),
  historyTargetAppsProvider.overrideWith(
    (ref) => Stream.value([
      for (final e in rows) (targetApp: e.targetApp, timestamp: e.timestamp),
    ]),
  ),
  historyRevisionProvider.overrideWith((ref) => Stream.value(0)),
];

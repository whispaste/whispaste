/// Core data-stream providers for history entries.
///
/// These providers bridge Drift database streams to Riverpod and are usable
/// across all layers (services, features, widgets) without creating
/// feature-to-feature dependency violations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

// No provider streams the whole history (#1643): every reader names how many
// rows it shows, counts come from SQL aggregates, and the Aufnahmen page pages
// its lists (features/history/data/providers.dart).

/// The first [limit] rows of the recordings list (not deleted, not
/// archived), pinned first, then newest, live. For the tray, the side panel
/// and the Automation API, each with its own [limit].
final historyHeadProvider = StreamProvider.family<List<HistoryEntry>, int>((
  ref,
  limit,
) {
  return ref.watch(historyDatabaseProvider).watchEntries(limit: limit);
});

/// How many recordings [latestRecordingsProvider] holds: the rows of the
/// Übersicht card.
const kLatestRecordingsLimit = 5;

/// The newest recordings (pins do not jump the queue), live. Backs the
/// Übersicht card and the reactions to a newly saved recording.
final latestRecordingsProvider = StreamProvider<List<HistoryEntry>>((ref) {
  return ref
      .watch(historyDatabaseProvider)
      .watchLatestEntries(limit: kLatestRecordingsLimit);
});

/// The target apps of the recordings with the time each was last used, one
/// row per stored app name (SQL `GROUP BY`), live.
final historyTargetAppsProvider =
    StreamProvider<List<({String? targetApp, DateTime timestamp})>>((ref) {
      return ref.watch(historyDatabaseProvider).watchTargetAppUsage();
    });

/// Grows with every write to the recordings. Watched by views that read
/// aggregates (figures, totals) to know when to read them again.
final historyRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(historyDatabaseProvider).watchHistoryRevision();
});

/// Live stream of archived entries.
final archivedEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchArchived();
});

/// Live stream of trashed entries.
final trashEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchTrash();
});

/// The full row (all texts) of one entry, live. The lists above carry only
/// previews, so whatever opens, copies or exports an entry reads it here
/// (#1324).
final historyFullEntryProvider = StreamProvider.autoDispose
    .family<HistoryEntry?, String>((ref, entryId) {
      return ref.watch(historyDatabaseProvider).watchEntry(entryId);
    });

/// Watch notes for a specific entry.
///
/// `autoDispose` — without it, every history entry ever opened during a
/// session leaves its Drift stream subscription running forever (only one
/// entry's notes are ever visible at a time; watched from
/// `history_notes_section.dart`'s build via `ref.watch`, never `ref.read`,
/// so nothing needs the provider to outlive its last watcher).
final entryNotesProvider = StreamProvider.autoDispose
    .family<List<EntryNote>, String>((ref, entryId) {
      final db = ref.watch(historyDatabaseProvider);
      return db.watchNotesForEntry(entryId);
    });

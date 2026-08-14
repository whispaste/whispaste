/// Core data-stream providers for history entries.
///
/// These providers bridge Drift database streams to Riverpod and are usable
/// across all layers (services, features, widgets) without creating
/// feature-to-feature dependency violations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Live stream of all non-deleted, non-archived history entries, newest first.
final historyEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchEntries();
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

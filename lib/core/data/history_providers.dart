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
  return db.watchEntries(limit: 500);
});

/// Live stream of archived entries.
final archivedEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchArchived(limit: 500);
});

/// Live stream of trashed entries.
final trashEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchTrash(limit: 500);
});

/// Watch notes for a specific entry.
final entryNotesProvider =
    StreamProvider.family<List<EntryNote>, String>((ref, entryId) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchNotesForEntry(entryId);
});

/// Core data-stream providers for the sidebar Notizen area (schema v17).
///
/// Same core-layer placement as `history_providers.dart` so that
/// `lib/features/notes/` never needs a feature-to-feature dependency on
/// `lib/features/history/`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Live stream of active (non-deleted) notes, favourites first then most
/// recently updated — sort order lives in SQL, see [HistoryDatabase.watchNotes].
final notesProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchNotes();
});

/// The live note taken from recording `entryId` ("Als Notiz übernehmen"), or
/// null. Trashed notes do not count: the link goes quiet with them.
final noteTakenFromEntryProvider = StreamProvider.autoDispose
    .family<Note?, String>((ref, entryId) {
      final db = ref.watch(historyDatabaseProvider);
      return db.watchNoteTakenFromEntry(entryId);
    });

/// Recording `entryId` while it is live (not trashed, not deleted), or null.
final liveEntryProvider = StreamProvider.autoDispose
    .family<HistoryEntry?, String>((ref, entryId) {
      final db = ref.watch(historyDatabaseProvider);
      return db.watchLiveEntry(entryId);
    });

/// Live stream of trashed notes, most recently deleted first.
final trashNotesProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchTrashNotes();
});

/// Live stream of tags linked to a single note, alphabetically sorted.
///
/// `autoDispose` — without it, every note ever selected during a session
/// leaves its Drift stream subscription running forever (only the current
/// selection's tags are ever visible; watched from `notes_page.dart`'s
/// build via `ref.watch`, never `ref.read`, so nothing needs the provider
/// to outlive its last watcher).
final noteTagsProvider = StreamProvider.autoDispose.family<List<Tag>, String>((
  ref,
  noteId,
) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchTagsForNote(noteId);
});

/// Live stream of ALL note→tags links, grouped by note id — backs Ticket 06's
/// search-by-tag, since [Note] has no denormalized tags column to query.
final allNoteTagsProvider = StreamProvider<Map<String, List<Tag>>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchAllNoteTags();
});

/// Full texts of the notes whose text contains `query`, by note id. Only read
/// while a search is running: the lists themselves carry just previews (#639).
/// Re-read when a list changes so a save during a search shows up.
final noteTextHitsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, query) {
      ref.watch(notesProvider);
      ref.watch(trashNotesProvider);
      return ref.watch(historyDatabaseProvider).noteTextsMatching(query);
    });

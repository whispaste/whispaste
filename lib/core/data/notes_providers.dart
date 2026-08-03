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

/// Live stream of trashed notes, most recently deleted first.
final trashNotesProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchTrashNotes();
});

/// Live stream of tags linked to a single note, alphabetically sorted.
final noteTagsProvider = StreamProvider.family<List<Tag>, String>((
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

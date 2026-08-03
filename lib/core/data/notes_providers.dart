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

// trashNotesProvider (wrapping HistoryDatabase.watchTrashNotes) lands in
// Ticket 04 together with its first consumer, the trash filter view.

/// Stateless write-side facade for the sidebar Notizen area.
///
/// UI reads live data from `notesProvider`/`trashNotesProvider`
/// (`core/data/notes_providers.dart`) and writes exclusively through
/// [NotesActions] — one data flow, no `NotesDetailNotifier`-style duplicate
/// state (a note is a flat object; there's nothing to hold beyond what the
/// stream providers already emit).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';

class NotesActions {
  NotesActions(this._db);

  final HistoryDatabase _db;

  Future<Note> create() => _db.createNote();

  Future<void> save(String noteId, String content) =>
      _db.updateNoteContent(noteId, content);

  Future<void> togglePin(String noteId, {required bool pinned}) =>
      _db.toggleNotePin(noteId, pinned: pinned);

  Future<void> moveToTrash(String noteId) => _db.softDeleteNote(noteId);

  Future<void> restore(String noteId) => _db.restoreNote(noteId);

  Future<void> deleteForever(String noteId) => _db.permanentDeleteNote(noteId);

  /// Deletes active notes whose content is blank — the empty-discard
  /// safety-net sweep run once when the Notizen page mounts.
  Future<int> purgeEmpty() => _db.purgeEmptyNotes();
}

final notesActionsProvider = Provider<NotesActions>((ref) {
  return NotesActions(ref.watch(historyDatabaseProvider));
});

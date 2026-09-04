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

  Future<Note?> duplicate(String noteId) => _db.duplicateNote(noteId);

  /// One-shot read of a single note — the deep-link case (open exactly this
  /// note), where the id is known but the note may not be in the currently
  /// streamed list at all (wrong filter, list not emitted yet). Returns
  /// `null` when the note no longer exists.
  Future<Note?> getNote(String noteId) => _db.getNote(noteId);

  Future<void> save(String noteId, String content) =>
      _db.updateNoteContent(noteId, content);

  Future<void> togglePin(String noteId, {required bool pinned}) =>
      _db.toggleNotePin(noteId, pinned: pinned);

  /// Marks [noteId] as the exclusive quick note (the target the quick-note
  /// hotkey appends to), unmarking whichever note held the mark before.
  Future<void> markAsQuickNote(String noteId) => _db.setQuickNote(noteId);

  /// Clears the quick-note mark without marking another note.
  Future<void> clearQuickNoteMark() => _db.clearQuickNote();

  Future<void> moveToTrash(String noteId) => _db.softDeleteNote(noteId);

  Future<void> restore(String noteId) => _db.restoreNote(noteId);

  Future<void> deleteForever(String noteId) => _db.permanentDeleteNote(noteId);

  /// Deletes active notes whose content is blank — the empty-discard
  /// safety-net sweep run once when the Notizen page mounts.
  Future<int> purgeEmpty() => _db.purgeEmptyNotes();

  /// Empty-discard for a single note (leaving it, closing the page): deletes
  /// [noteId] only if it is still blank and not the marked quick note.
  Future<bool> discardIfBlank(String noteId) => _db.discardNoteIfBlank(noteId);

  /// Add an existing or new tag to a note (find-or-create by name), mirrors
  /// `HistoryDetailNotifier.addTag`.
  Future<void> addTag(String noteId, String tagName) async {
    final name = tagName.trim().toLowerCase();
    if (name.isEmpty) return;

    final existing = await _db.searchTags(name);
    final tag = existing.any((t) => t.name == name)
        ? existing.firstWhere((t) => t.name == name)
        : await _db.createTag(name);

    await _db.tagNote(noteId, tag.id);
  }

  /// Remove a tag from a note (does not delete the tag itself).
  Future<void> removeTag(String noteId, String tagId) =>
      _db.untagNote(noteId, tagId);
}

final notesActionsProvider = Provider<NotesActions>((ref) {
  return NotesActions(ref.watch(historyDatabaseProvider));
});

import 'package:flutter/material.dart';

import '../../../core/data/database.dart';
import '../../../widgets/wp_split_view.dart';
import 'note_editor_panel.dart';
import 'notes_list_view.dart';

// ---------------------------------------------------------------------------
// Split-view layout — the geometry, the divider and the note-to-note
// cross-fade come from WpSplitView; what stays here is the notes-specific
// content of the two columns. Deliberately simpler than history's: a flat
// note list left, the editor right, no view modes, no multi-select, no date
// groups (CONTEXT.md §5.9).
// ---------------------------------------------------------------------------

class NotesSplitView extends StatelessWidget {
  const NotesSplitView({
    super.key,
    required this.notes,
    required this.tagsByNoteId,
    required this.isTrashView,
    required this.selectedNote,
    required this.focusedNoteId,
    required this.selectedNoteTags,
    required this.editorController,
    required this.editorFocusNode,
    this.scrollEditorToEnd,
    required this.onNoteTap,
    required this.onCopy,
    required this.onDuplicate,
    required this.onCloseEditor,
    required this.onFavoriteToggle,
    required this.onQuickNoteSet,
    required this.onQuickNoteClear,
    required this.onMoveToTrash,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onExport,
    required this.onVoiceTranscript,
  });

  final List<Note> notes;

  /// Note id → linked tags for the list tiles (from allNoteTagsProvider).
  final Map<String, List<Tag>> tagsByNoteId;

  /// Whether the trash filter is active — swaps the per-note actions
  /// (favourite/trash vs. restore/delete-forever) in list tiles and editor.
  final bool isTrashView;
  final Note? selectedNote;

  /// Keyboard-focused note id (the list's virtual cursor, owned by
  /// `_NotesPageState`) — passed through to the list tiles for highlighting.
  final String? focusedNoteId;

  /// Tags of the note currently open in the editor — resolved by the caller
  /// (noteTagsProvider), empty when no note is selected.
  final List<Tag> selectedNoteTags;

  /// Owned by `_NotesPageState` (NOT by the editor panel) so cursor and IME
  /// state survive rebuilds triggered by the notes stream.
  final TextEditingController editorController;
  final FocusNode editorFocusNode;

  /// Fires when the editor's body field should jump to the end of the note —
  /// owned by `_NotesPageState` too. See [NoteEditorPanel.scrollEditorToEnd].
  final Listenable? scrollEditorToEnd;
  final ValueChanged<Note> onNoteTap;
  final ValueChanged<Note> onCopy;
  final ValueChanged<Note> onDuplicate;
  final VoidCallback onCloseEditor;
  final ValueChanged<Note> onFavoriteToggle;

  /// Make the given note the quick note (the note the quick-note hotkey
  /// appends to). Exclusive — the write path drops the previous mark.
  final ValueChanged<Note> onQuickNoteSet;

  /// Drop the quick-note mark; at most one note holds it, so no note is
  /// needed to say which.
  final VoidCallback onQuickNoteClear;
  final ValueChanged<Note> onMoveToTrash;
  final ValueChanged<Note> onRestore;
  final ValueChanged<Note> onDeleteForever;

  /// Add/remove a tag on the note currently open in the editor
  /// (tagName / tagId).
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;

  /// Export the note currently open in the editor.
  final VoidCallback onExport;

  /// Raw transcript from the editor's voice-input button — passed through to
  /// [NoteEditorPanel]; insertion happens in `_NotesPageState`.
  final ValueChanged<String> onVoiceTranscript;

  Widget _buildListBody(BuildContext context, String? selectedId) {
    return NotesListView(
      notes: notes,
      tagsByNoteId: tagsByNoteId,
      isTrashView: isTrashView,
      selectedId: selectedId,
      focusedId: focusedNoteId,
      onNoteTap: onNoteTap,
      onCopy: onCopy,
      onDuplicate: onDuplicate,
      onFavoriteToggle: onFavoriteToggle,
      onQuickNoteSet: onQuickNoteSet,
      onQuickNoteClear: onQuickNoteClear,
      onRestore: onRestore,
      onDeleteForever: onDeleteForever,
    );
  }

  Widget _buildEditorPanel(BuildContext context, Note note) {
    return NoteEditorPanel(
      note: note,
      tags: selectedNoteTags,
      controller: editorController,
      focusNode: editorFocusNode,
      scrollEditorToEnd: scrollEditorToEnd,
      onClose: onCloseEditor,
      onToggleFavorite: () => onFavoriteToggle(note),
      onQuickNoteSet: () => onQuickNoteSet(note),
      onQuickNoteClear: onQuickNoteClear,
      onMoveToTrash: () => onMoveToTrash(note),
      onRestore: () => onRestore(note),
      onDeleteForever: () => onDeleteForever(note),
      onAddTag: onAddTag,
      onRemoveTag: onRemoveTag,
      onExport: onExport,
      onVoiceTranscript: onVoiceTranscript,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WpSplitView<Note>(
      selectedItem: selectedNote,
      idOf: (note) => note.id,
      listBuilder: _buildListBody,
      detailBuilder: _buildEditorPanel,
      // The editor's controller and focus node are owned by `_NotesPageState`
      // and outlive the panel, so the two panels a cross-fade keeps mounted
      // side by side would both bind them — see WpSplitView.crossFadeDetail.
      crossFadeDetail: false,
    );
  }
}

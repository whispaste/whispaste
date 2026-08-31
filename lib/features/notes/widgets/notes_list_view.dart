import 'package:flutter/material.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import 'notes_list_tile.dart';

// ---------------------------------------------------------------------------
// Flat note list — no date groups (notes are sorted favourites-first, then
// most recently updated, straight from SQL; see notesProvider).
// ---------------------------------------------------------------------------

class NotesListView extends StatelessWidget {
  const NotesListView({
    super.key,
    required this.notes,
    required this.tagsByNoteId,
    required this.isTrashView,
    required this.selectedId,
    required this.focusedId,
    required this.onNoteTap,
    required this.onCopy,
    required this.onFavoriteToggle,
    required this.onQuickNoteSet,
    required this.onQuickNoteClear,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final List<Note> notes;

  /// Note id → linked tags (from allNoteTagsProvider); notes without tags
  /// simply have no entry here.
  final Map<String, List<Tag>> tagsByNoteId;
  final bool isTrashView;
  final String? selectedId;

  /// Keyboard-focused note id (the list's virtual cursor).
  final String? focusedId;
  final ValueChanged<Note> onNoteTap;
  final ValueChanged<Note> onCopy;
  final ValueChanged<Note> onFavoriteToggle;

  /// Make the given note the quick note (exclusive — the previous mark is
  /// dropped by the write path, not here).
  final ValueChanged<Note> onQuickNoteSet;

  /// Drop the quick-note mark altogether. Takes no note: there is at most one
  /// marked note, so "which one" is never a question.
  final VoidCallback onQuickNoteClear;
  final ValueChanged<Note> onRestore;
  final ValueChanged<Note> onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      label: l10n.notesListSemantics,
      child: ListView.builder(
        // The list owns the horizontal page inset (tiles carry none), so its
        // left/right edge lands exactly on NotesSearchBar's xl inset — same
        // arrangement as WpSearchableListPage's list.
        padding: const EdgeInsets.fromLTRB(
          WpSpacing.xl,
          WpSpacing.xs,
          WpSpacing.xl,
          WpSpacing.xxl,
        ),
        itemCount: notes.length,
        itemBuilder: (_, i) {
          final note = notes[i];
          return NotesListTile(
            key: ValueKey(note.id),
            note: note,
            tags: tagsByNoteId[note.id] ?? const [],
            isTrashView: isTrashView,
            isSelected: note.id == selectedId,
            isFocused: note.id == focusedId,
            onTap: () => onNoteTap(note),
            onCopy: () => onCopy(note),
            onFavoriteToggle: () => onFavoriteToggle(note),
            onQuickNoteSet: () => onQuickNoteSet(note),
            onQuickNoteClear: onQuickNoteClear,
            onRestore: () => onRestore(note),
            onDeleteForever: () => onDeleteForever(note),
          );
        },
      ),
    );
  }
}

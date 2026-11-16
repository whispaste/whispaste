import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/sorting/list_sort.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/sorting/list_sort_preference.dart';
import '../../history/widgets/history_date_header.dart';
import '../data/notes_view_options.dart';
import '../data/providers.dart';
import 'notes_favorites_header.dart';
import 'notes_list_tile.dart';
import '../../../widgets/wp_collection_list_pane.dart';

// ---------------------------------------------------------------------------
// Note list — favourites first, then the chosen sort order (filteredNotesProvider).
// With "group by date" on, date headers split it into sections (#654).
// ---------------------------------------------------------------------------

class NotesListView extends ConsumerWidget {
  const NotesListView({
    super.key,
    required this.notes,
    required this.tagsByNoteId,
    required this.isTrashView,
    this.isSearch = false,
    required this.selectedId,
    required this.focusedId,
    this.selecting = false,
    this.checkedIds = const <String>{},
    required this.onNoteTap,
    required this.onCopy,
    required this.onDuplicate,
    required this.onFavoriteToggle,
    required this.onQuickNoteSet,
    required this.onQuickNoteClear,
    required this.onRestore,
    required this.onDeleteForever,
    this.onMoveToTrash,
  });

  final List<Note> notes;

  /// Note id → linked tags (from allNoteTagsProvider); notes without tags
  /// simply have no entry here.
  final Map<String, List<Tag>> tagsByNoteId;
  final bool isTrashView;

  /// The list is the hit list of a search: flat, without favourites or date
  /// sections (#830).
  final bool isSearch;
  final String? selectedId;

  /// Keyboard-focused note id (the list's virtual cursor).
  final String? focusedId;

  /// Multi-select is on (#655): every row shows a checkbox, [checkedIds]
  /// are ticked, and the editor highlight gives way to the checked state.
  final bool selecting;
  final Set<String> checkedIds;
  final ValueChanged<Note> onNoteTap;
  final ValueChanged<Note> onCopy;
  final ValueChanged<Note> onDuplicate;
  final ValueChanged<Note> onFavoriteToggle;

  /// Make the given note the quick note (exclusive — the previous mark is
  /// dropped by the write path, not here).
  final ValueChanged<Note> onQuickNoteSet;

  /// Drop the quick-note mark altogether. Takes no note: there is at most one
  /// marked note, so "which one" is never a question.
  final VoidCallback onQuickNoteClear;
  final ValueChanged<Note> onRestore;
  final ValueChanged<Note> onDeleteForever;

  /// The row's visible Delete action (moves the note to the trash).
  final ValueChanged<Note>? onMoveToTrash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final sort = ref.watch(notesSortProvider).value ?? kNotesDefaultSort;
    final browsing = !isTrashView && !isSearch;
    // The hit list marks the search term in each tile's excerpt (#872).
    final query = isSearch ? ref.watch(notesSearchProvider).trim() : '';
    final grouped =
        browsing &&
        canGroupByDate(sort) &&
        (ref.watch(notesGroupByDateProvider).value ?? false);
    final collapsed =
        browsing && (ref.watch(notesFavoritesCollapsedProvider).value ?? false);
    final rows = _rows(
      l10n,
      groupSort: grouped ? sort : null,
      favorites: browsing,
      collapsed: collapsed,
    );
    Widget header(_Row row) {
      if (row.favoritesCount != null) {
        return NotesFavoritesHeader(
          key: const ValueKey('notes-favorites-toggle'),
          label: l10n.historyPinned,
          count: row.favoritesCount!,
          collapsed: collapsed,
          onToggle: () => unawaited(
            ref.read(notesFavoritesCollapsedProvider.notifier).toggle(),
          ),
        );
      }
      return HistoryDateHeader(
        key: ValueKey('notes-group-${row.groupId}'),
        label: row.header!,
      );
    }

    return WpCollectionListPane<Note>(
      storageKey: 'notes-scroll-list',
      copyTargetPrefix: 'note',
      semanticsLabel: l10n.notesListSemantics,
      semanticsIdentifier: 'notes-list',
      focusedId: focusedId,
      rows: [
        for (final row in rows)
          if (row.note case final note?)
            WpCollectionItemRow<Note>(note.id, note)
          else
            WpCollectionHeaderRow<Note>(header(row)),
      ],
      itemBuilder: (_, note) => NotesListTile(
        key: ValueKey(note.id),
        note: note,
        searchQuery: query,
        tags: tagsByNoteId[note.id] ?? const [],
        isTrashView: isTrashView,
        isSelected: selecting
            ? checkedIds.contains(note.id)
            : note.id == selectedId,
        isFocused: note.id == focusedId,
        selecting: selecting,
        onTap: () => onNoteTap(note),
        onCopy: () => onCopy(note),
        onDuplicate: () => onDuplicate(note),
        onFavoriteToggle: () => onFavoriteToggle(note),
        onQuickNoteSet: () => onQuickNoteSet(note),
        onQuickNoteClear: onQuickNoteClear,
        onRestore: () => onRestore(note),
        onDeleteForever: () => onDeleteForever(note),
        onMoveToTrash: onMoveToTrash == null
            ? null
            : () => onMoveToTrash!(note),
      ),
    );
  }

  /// The list rows: the notes alone, or with a toggle head before the
  /// favourites ([favorites], hiding them while [collapsed]) and a header
  /// before each date group ([groupSort]).
  List<_Row> _rows(
    L10n l10n, {
    required ListSort? groupSort,
    required bool favorites,
    required bool collapsed,
  }) {
    final rows = <_Row>[];
    final pinnedCount = favorites ? notes.where((n) => n.pinned).length : 0;
    if (pinnedCount > 0) rows.add(_Row.favorites(pinnedCount));
    final now = DateTime.now();
    NotesDateGroup? last;
    var otherHeadShown = false;
    for (final note in notes) {
      if (favorites && note.pinned) {
        if (!collapsed) rows.add(_Row.note(note));
        continue;
      }
      if (groupSort != null) {
        final group = dateGroupOf(note, groupSort, now);
        if (group != last) {
          rows.add(_Row.header(group.name, _groupLabel(l10n, group)));
          last = group;
        }
      } else if (pinnedCount > 0 && !otherHeadShown) {
        // Favourites on top and nothing to tell them from the rest otherwise.
        rows.add(_Row.header('other', l10n.notesOtherNotes));
        otherHeadShown = true;
      }
      rows.add(_Row.note(note));
    }
    return rows;
  }

  static String _groupLabel(L10n l10n, NotesDateGroup group) => switch (group) {
    NotesDateGroup.pinned => l10n.historyPinned,
    NotesDateGroup.today => l10n.historyToday,
    NotesDateGroup.yesterday => l10n.historyYesterday,
    NotesDateGroup.thisWeek => l10n.historyThisWeek,
    NotesDateGroup.older => l10n.historyOlder,
  };
}

class _Row {
  const _Row.note(Note this.note)
    : header = null,
      groupId = null,
      favoritesCount = null;
  const _Row.header(String this.groupId, String this.header)
    : note = null,
      favoritesCount = null;
  const _Row.favorites(int this.favoritesCount)
    : note = null,
      header = null,
      groupId = null;

  final int? favoritesCount;

  final Note? note;
  final String? header;
  final String? groupId;
}

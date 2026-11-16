/// Feature-local providers for the Notizen sidebar area — filter/search UI
/// state layered on top of the core data-stream providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/sorting/list_sort_preference.dart';

import 'notes_view_options.dart';

// Re-export the core data-stream providers so feature-local imports don't
// need to reach into `core/data/` directly (mirrors
// `features/history/data/providers.dart`).
export 'package:whispaste/core/data/notes_providers.dart';

/// Active/trash filter for the Notizen page.
enum NotesFilter { active, trash }

class NotesFilterNotifier extends Notifier<NotesFilter> {
  @override
  NotesFilter build() => NotesFilter.active;

  void set(NotesFilter filter) => state = filter;
}

final notesFilterProvider = NotifierProvider<NotesFilterNotifier, NotesFilter>(
  NotesFilterNotifier.new,
);

/// Search query for the Notizen page.
class NotesSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final notesSearchProvider = NotifierProvider<NotesSearchNotifier, String>(
  NotesSearchNotifier.new,
);

/// Filtered + searched notes for the active/trash filter — the main data
/// source for the list. No FTS/DB-level search for Notizen (per the
/// Ticket-02 plan): a non-empty query filters in-memory against note
/// title, content and linked tag names via [allNoteTagsProvider]. The active
/// view is ordered by [notesSortProvider] and tag-filtered by
/// [notesTagFilterProvider] (#654); with a query it is the ranked hit list
/// ([searchHits], #830). The trash keeps its deletion order.
final filteredNotesProvider = Provider<AsyncValue<List<Note>>>((ref) {
  final filter = ref.watch(notesFilterProvider);
  final isTrash = filter == NotesFilter.trash;
  final notesAsync = ref.watch(isTrash ? trashNotesProvider : notesProvider);
  final tagsByNoteId =
      ref.watch(allNoteTagsProvider).value ?? const <String, List<Tag>>{};

  final query = ref.watch(notesSearchProvider).trim().toLowerCase();
  // Precompiled outside the loop — avoids allocating a lowercased copy of
  // every note's content on every keystroke.
  final queryRegex = query.isEmpty
      ? null
      : RegExp(RegExp.escape(query), caseSensitive: false);

  var result = notesAsync;
  if (queryRegex != null) {
    // The list rows hold previews only (#639): the notes whose text matches
    // get their full text for the search, the snippet and the relevance.
    final hits = ref.watch(noteTextHitsProvider(query)).value;
    if (hits != null) {
      result = result.whenData(
        (notes) => [
          for (final n in notes)
            hits.containsKey(n.id) ? n.copyWith(content: hits[n.id]) : n,
        ],
      );
    }
  }
  if (queryRegex != null && isTrash) {
    result = result.whenData(
      (notes) => notes.where((note) {
        if (queryRegex.hasMatch(note.content)) return true;
        final tags = tagsByNoteId[note.id] ?? const [];
        return tags.any((t) => t.name.contains(query));
      }).toList(),
    );
  }
  if (isTrash) return result;

  // The default order (as the database delivers it) holds until the saved
  // choice is read.
  final sortAsync = ref.watch(notesSortProvider);
  final sort = sortAsync.value ?? kNotesDefaultSort;
  final inUse = {for (final t in ref.watch(notesTagsInUseProvider)) t.id};
  final tagIds = ref.watch(notesTagFilterProvider).intersection(inUse);
  // A search shows its own hit list (#830): best answers first, favourites
  // not on top, no date sections; a chosen tag filter still narrows it.
  if (query.isNotEmpty) {
    return result.whenData(
      (notes) => searchHits(
        notes,
        query,
        sort,
        tagIds: tagIds,
        tagsByNoteId: tagsByNoteId,
      ),
    );
  }
  return result.whenData(
    (notes) =>
        arrangeNotes(notes, sort, tagIds: tagIds, tagsByNoteId: tagsByNoteId),
  );
});

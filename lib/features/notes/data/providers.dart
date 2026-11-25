/// Feature-local providers for the Notizen sidebar area — filter/search UI
/// state layered on top of the core data-stream providers.
library;

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/content_metadata.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/sorting/list_sort_preference.dart';
import 'package:whispaste/core/views/smart_view.dart';
import 'package:whispaste/core/views/smart_view_items.dart';
import 'package:whispaste/core/views/smart_view_providers.dart';

import 'note_folder_tree.dart';
import 'notes_view_options.dart';

// Re-export the core data-stream providers so feature-local imports don't
// need to reach into `core/data/` directly (mirrors
// `features/history/data/providers.dart`).
export 'package:whispaste/core/data/notes_providers.dart';

/// Storage shown on the Notizen page: active notes, the archive (#656) or
/// the trash — the same three as for recordings.
enum NotesFilter { active, archive, trash }

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

/// The folder chosen on the Notizen page (#659), null for all notes. It
/// narrows the active list only; archive, trash and saved views stay
/// folder-independent (ADR 0034).
class NotesFolderFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? folderId) => state = folderId;
}

final notesFolderFilterProvider =
    NotifierProvider<NotesFolderFilterNotifier, String?>(
      NotesFolderFilterNotifier.new,
    );

/// The note folders by id, empty until they are loaded.
final noteFoldersByIdProvider = Provider<Map<String, NoteFolder>>((ref) {
  final folders = ref.watch(noteFoldersProvider).value ?? const [];
  return {for (final f in folders) f.id: f};
});

/// The chosen folder while it still exists, else null (a deleted folder
/// falls back to all notes).
final shownNoteFolderIdProvider = Provider<String?>((ref) {
  final id = ref.watch(notesFolderFilterProvider);
  if (id == null) return null;
  return ref.watch(noteFoldersByIdProvider).containsKey(id) ? id : null;
});

/// Filtered + searched notes for the chosen storage — the main data
/// source for the list. No FTS/DB-level search for Notizen (per the
/// Ticket-02 plan): a non-empty query filters in-memory against note
/// title, content and linked tag names via [allNoteTagsProvider]. The active
/// view is ordered by [notesSortProvider] and tag-filtered by
/// [notesTagFilterProvider] (#654); with a query it is the ranked hit list
/// ([searchHits], #830). Archive and trash keep their own order (last edit
/// resp. deletion) and are searched by plain match.
final filteredNotesProvider = Provider<AsyncValue<List<Note>>>((ref) {
  final filter = ref.watch(notesFilterProvider);
  // Archive and trash are storages: own order, plain-match search.
  final isStorage = filter != NotesFilter.active;
  final notesAsync = ref.watch(switch (filter) {
    NotesFilter.active => notesProvider,
    NotesFilter.archive => archivedNotesProvider,
    NotesFilter.trash => trashNotesProvider,
  });
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
  if (queryRegex != null && isStorage) {
    result = result.whenData(
      (notes) => notes.where((note) {
        if (queryRegex.hasMatch(note.content)) return true;
        final tags = tagsByNoteId[note.id] ?? const [];
        return tags.any((t) => t.name.contains(query));
      }).toList(),
    );
  }
  if (isStorage) return result;

  // A saved view (#658) narrows the active list before search, sort and the
  // tag filter, so all of them combine with it.
  final view = ref.watch(shownSmartViewProvider(SmartViewScope.notes));
  final foldersById = ref.watch(noteFoldersByIdProvider);
  if (view != null) {
    final readsFolders = view.rules.any((r) => r is FolderRule);
    final checklists = smartViewNeedsChecklists(view)
        ? ref.watch(checklistDocumentsProvider).value ?? const <ContentKey>{}
        : const <ContentKey>{};
    final appended = view.rules.any((r) => r is SourceRule)
        ? ref.watch(noteIdsWithAppendsProvider).value ?? const <String>{}
        : const <String>{};
    final now = clock.now();
    result = result.whenData(
      (notes) => [
        for (final n in notes)
          if (smartViewMatches(
            view,
            noteSmartViewItem(
              n,
              tagsByNoteId[n.id] ?? const [],
              hasAppends: appended.contains(n.id),
              hasChecklist: checklists.contains((
                kind: ContentKind.note,
                id: n.id,
              )),
              folderIds: readsFolders
                  ? noteFolderAncestry(n.folderId, foldersById)
                  : const {},
            ),
            now,
          ))
            n,
      ],
    );
  } else if (ref.watch(shownNoteFolderIdProvider) case final folderId?) {
    // A chosen folder narrows the list to it and its subfolders; search,
    // sort and the tag filter then work inside it. A shown view wins over
    // the folder: views reach across folders (ADR 0034).
    result = result.whenData(
      (notes) => [
        for (final n in notes)
          if (noteInFolder(n.folderId, folderId, foldersById)) n,
      ],
    );
  }

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

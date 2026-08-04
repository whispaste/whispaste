/// Feature-local providers for the Notizen sidebar area — filter/search UI
/// state layered on top of the core data-stream providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';

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
/// content and linked tag names via [allNoteTagsProvider]. An empty query
/// passes the stream through unchanged, preserving the SQL sort order.
final filteredNotesProvider = Provider<AsyncValue<List<Note>>>((ref) {
  final filter = ref.watch(notesFilterProvider);
  final baseProvider = filter == NotesFilter.trash
      ? trashNotesProvider
      : notesProvider;
  final notesAsync = ref.watch(baseProvider);

  final query = ref.watch(notesSearchProvider).trim().toLowerCase();
  if (query.isEmpty) return notesAsync;

  final tagsByNoteId =
      ref.watch(allNoteTagsProvider).value ?? const <String, List<Tag>>{};
  return notesAsync.whenData(
    (notes) => notes.where((note) {
      if (note.content.toLowerCase().contains(query)) return true;
      final tags = tagsByNoteId[note.id] ?? const [];
      return tags.any((t) => t.name.contains(query));
    }).toList(),
  );
});

/// Date grouping and tag filter of the note list, and the arrangement the
/// list shows (#654).
///
/// Pure functions plus two small notifiers. The sort itself is the shared
/// [ListSort] of the other lists (`notesSortProvider`). Pinned notes stay on
/// top for every choice.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/sorting/list_sort.dart';

import 'package:whispaste/core/logging/app_logger.dart';

import 'note_title.dart';

final _log = AppLogger('NotesViewOptions');

/// A [Note] as the shared list sort sees it.
class _SortableNote implements ListSortable {
  _SortableNote(this.note) : sortTitle = noteSortTitle(note);

  final Note note;

  @override
  String get sortId => note.id;

  // Derived once: the comparator asks for it on every comparison.
  @override
  final String sortTitle;

  @override
  String get sortResult => '';

  @override
  DateTime get sortCreatedAt => note.createdAt;

  @override
  DateTime get sortChangedAt => note.updatedAt;
}

/// The title the list shows for [note]: the explicit one, else the first line.
String noteSortTitle(Note note) {
  final explicit = note.title?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  return deriveNoteTitle(note.content) ?? '';
}

/// [notes] that carry every tag in [tagIds], ordered by [sort]; pinned notes
/// first. The order is total, so it does not depend on the input order.
List<Note> arrangeNotes(
  List<Note> notes,
  ListSort sort, {
  required Set<String> tagIds,
  required Map<String, List<Tag>> tagsByNoteId,
  bool pinnedFirst = true,
}) {
  final kept = tagIds.isEmpty
      ? notes
      : notes.where((n) {
          final ids = (tagsByNoteId[n.id] ?? const <Tag>[])
              .map((t) => t.id)
              .toSet();
          return ids.containsAll(tagIds);
        });
  List<Note> ordered(Iterable<Note> part) => [
    for (final s in sortListItems(part.map(_SortableNote.new), sort)) s.note,
  ];
  if (!pinnedFirst) return ordered(kept);
  return [
    ...ordered(kept.where((n) => n.pinned)),
    ...ordered(kept.where((n) => !n.pinned)),
  ];
}

/// How well [note] answers [needle] (lower-cased) / [pattern] (the same text,
/// compiled once for the whole list): 0 the title contains it, 1 a tag name
/// does, 2 only the text does, null no match.
int? searchRelevance(Note note, String needle, RegExp pattern, List<Tag> tags) {
  if (pattern.hasMatch(noteSortTitle(note))) return 0;
  if (tags.any((t) => t.name.toLowerCase().contains(needle))) return 1;
  if (pattern.hasMatch(note.content)) return 2;
  return null;
}

/// The hit list of a search: the notes that match, best answers first (title,
/// then tag, then text), within one rank in the chosen [sort] order, and only
/// those carrying every tag in [tagIds]. Pinned
/// notes get no special place: a hit list is not the browsing list.
List<Note> searchHits(
  List<Note> notes,
  String query,
  ListSort sort, {
  Set<String> tagIds = const <String>{},
  required Map<String, List<Tag>> tagsByNoteId,
}) {
  final needle = query.trim().toLowerCase();
  // Compiled once: no lower-cased copy of every note's text per keystroke.
  final pattern = RegExp(RegExp.escape(needle), caseSensitive: false);
  final byRank = <int, List<Note>>{};
  for (final note in notes) {
    final rank = searchRelevance(
      note,
      needle,
      pattern,
      tagsByNoteId[note.id] ?? const <Tag>[],
    );
    if (rank != null) (byRank[rank] ??= []).add(note);
  }
  return [
    for (final rank in const [0, 1, 2])
      ...arrangeNotes(
        byRank[rank] ?? const <Note>[],
        sort,
        tagIds: tagIds,
        tagsByNoteId: tagsByNoteId,
        pinnedFirst: false,
      ),
  ];
}

/// [notes] without the pinned ones while the favourites section is folded.
/// Only the active browsing list folds; a search or the trash never does.
List<Note> withoutFoldedFavorites(List<Note> notes) => [
  for (final n in notes)
    if (!n.pinned) n,
];

/// Section of the date grouping.
enum NotesDateGroup { pinned, today, yesterday, thisWeek, older }

/// The group of [note] at [now]. Pinned notes form their own group; the date
/// is the creation date for the created order, else the edit date.
NotesDateGroup dateGroupOf(Note note, ListSort sort, DateTime now) {
  if (note.pinned) return NotesDateGroup.pinned;
  final at = sort.field == ListSortField.added
      ? note.createdAt
      : note.updatedAt;
  final today = DateTime(now.year, now.month, now.day);
  final age = today.difference(DateTime(at.year, at.month, at.day)).inDays;
  if (age <= 0) return NotesDateGroup.today;
  if (age == 1) return NotesDateGroup.yesterday;
  if (age <= 6) return NotesDateGroup.thisWeek;
  return NotesDateGroup.older;
}

/// Whether the favourites section of the list is folded. Remembered like the
/// sort: a user who folds it wants it folded at the next start too.
class NotesFavoritesCollapsedNotifier extends AsyncNotifier<bool> {
  static const _key = 'notes_favorites_collapsed';

  @override
  Future<bool> build() async {
    final raw = await ref.read(historyDatabaseProvider).readAppSetting(_key);
    return raw == '1';
  }

  Future<void> toggle() async {
    final next = !(state.value ?? false);
    state = AsyncData(next);
    try {
      await ref
          .read(historyDatabaseProvider)
          .writeAppSetting(_key, next ? '1' : '0');
    } on Object catch (e, st) {
      _log.warning('Could not save the folded favourites', e, st);
    }
  }
}

final notesFavoritesCollapsedProvider =
    AsyncNotifierProvider<NotesFavoritesCollapsedNotifier, bool>(
      NotesFavoritesCollapsedNotifier.new,
    );

/// The tags the list is filtered by. Not remembered: a filter that outlives
/// the session hides notes the user forgot about.
class NotesTagFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void toggle(String tagId) {
    final next = {...state};
    if (!next.remove(tagId)) next.add(tagId);
    state = next;
  }

  void clear() => state = const <String>{};
}

final notesTagFilterProvider =
    NotifierProvider<NotesTagFilterNotifier, Set<String>>(
      NotesTagFilterNotifier.new,
    );

/// Whether the list can show date sections: not for the title order, where
/// notes of one date are not next to each other.
bool canGroupByDate(ListSort sort) => sort.field != ListSortField.title;

/// The tags at least one active note carries, by name. A chosen tag that no
/// active note carries any more (or that hangs on trashed notes only) is not
/// listed and does not filter.
final notesTagsInUseProvider = Provider<List<Tag>>((ref) {
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  final byNote =
      ref.watch(allNoteTagsProvider).value ?? const <String, List<Tag>>{};
  final unique = <String, Tag>{
    for (final note in notes)
      for (final tag in byNote[note.id] ?? const <Tag>[]) tag.id: tag,
  };
  return unique.values.toList()
    ..sort((a, b) => compareListText(a.name, b.name));
});

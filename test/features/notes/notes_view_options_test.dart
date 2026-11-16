/// Sort, date grouping and tag filter of the note list (#654): pure logic and
/// the remembered options.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/sorting/list_sort.dart';
import 'package:whispaste/features/notes/data/notes_view_options.dart';
import 'package:whispaste/features/notes/data/providers.dart';

Note _note(
  String id, {
  String content = '',
  String? title,
  bool pinned = false,
  required DateTime created,
  required DateTime updated,
}) => Note(
  id: id,
  content: content,
  title: title,
  pinned: pinned,
  isQuickNote: false,
  createdAt: created,
  updatedAt: updated,
);

Tag _tag(String id) => Tag(id: id, name: id, createdAt: DateTime(2026));

void main() {
  final d1 = DateTime(2026, 11, 1, 10);
  final d2 = DateTime(2026, 11, 2, 10);
  final d3 = DateTime(2026, 11, 3, 10);

  final a = _note('a', content: 'Banane', created: d3, updated: d1);
  final b = _note('b', content: 'apfel', created: d1, updated: d2);
  final c = _note('c', content: '', title: 'Zitrone', created: d2, updated: d3);
  final pinned = _note(
    'p',
    content: 'Mango',
    pinned: true,
    created: d1,
    updated: d1,
  );
  final all = [a, b, c, pinned];

  List<String> ids(List<Note> notes) => [for (final n in notes) n.id];

  const byChanged = ListSort(ListSortField.changed);

  List<String> arrange(
    ListSort sort, {
    Set<String> tagIds = const {},
    Map<String, List<Tag>> tags = const {},
    List<Note>? notes,
  }) =>
      ids(arrangeNotes(notes ?? all, sort, tagIds: tagIds, tagsByNoteId: tags));

  group('arrangeNotes', () {
    test('default: pinned first, then the most recently edited', () {
      expect(arrange(byChanged), ['p', 'c', 'b', 'a']);
    });

    test('created order and its reverse, pinned stay on top', () {
      expect(arrange(const ListSort(ListSortField.added)), [
        'p',
        'a',
        'c',
        'b',
      ]);
      expect(arrange(const ListSort(ListSortField.added, reversed: true)), [
        'p',
        'b',
        'c',
        'a',
      ]);
    });

    test('title order uses the explicit title and ignores case', () {
      expect(arrange(const ListSort(ListSortField.title)), [
        'p',
        'b',
        'a',
        'c',
      ]);
    });

    test('equal keys give the same order for any input order', () {
      final x = _note('x', content: 'same', created: d1, updated: d1);
      final y = _note('y', content: 'same', created: d1, updated: d1);
      expect(arrange(byChanged, notes: [x, y]), ['x', 'y']);
      expect(arrange(byChanged, notes: [y, x]), ['x', 'y']);
    });

    test('a tag filter keeps only notes that carry every chosen tag', () {
      final tags = {
        'a': [_tag('t1'), _tag('t2')],
        'b': [_tag('t1')],
        'c': [_tag('t2')],
      };
      List<String> with_(Set<String> wanted) =>
          arrange(byChanged, tagIds: wanted, tags: tags);
      expect(with_({'t1'}), ['b', 'a']);
      expect(with_({'t1', 't2'}), ['a']);
      expect(with_({'t3'}), isEmpty);
      expect(with_({}), ['p', 'c', 'b', 'a']);
    });
  });

  group('dateGroupOf', () {
    final now = DateTime(2026, 11, 6, 12);

    NotesDateGroup groupAt(DateTime updated, {bool pinned = false}) =>
        dateGroupOf(
          _note('n', pinned: pinned, created: updated, updated: updated),
          byChanged,
          now,
        );

    test('today, yesterday, this week, older', () {
      expect(groupAt(DateTime(2026, 11, 6, 0, 1)), NotesDateGroup.today);
      expect(groupAt(DateTime(2026, 11, 5, 23, 59)), NotesDateGroup.yesterday);
      expect(groupAt(DateTime(2026, 11, 4)), NotesDateGroup.thisWeek);
      expect(groupAt(DateTime(2026, 10, 31)), NotesDateGroup.thisWeek);
      expect(groupAt(DateTime(2026, 10, 30)), NotesDateGroup.older);
    });

    test('pinned notes form their own group', () {
      expect(
        groupAt(DateTime(2026, 11, 6), pinned: true),
        NotesDateGroup.pinned,
      );
    });

    test('the created order groups by the creation date', () {
      final n = _note('n', created: DateTime(2026, 1, 1), updated: now);
      expect(
        dateGroupOf(n, const ListSort(ListSortField.added), now),
        NotesDateGroup.older,
      );
      expect(dateGroupOf(n, byChanged, now), NotesDateGroup.today);
    });
  });

  test('the tag filter toggles tags and clears', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(notesTagFilterProvider.notifier);
    notifier.toggle('t1');
    notifier.toggle('t2');
    notifier.toggle('t1');
    expect(container.read(notesTagFilterProvider), {'t2'});
    notifier.clear();
    expect(container.read(notesTagFilterProvider), isEmpty);
  });

  test('only the date orders can be grouped', () {
    expect(canGroupByDate(const ListSort(ListSortField.title)), isFalse);
    expect(canGroupByDate(const ListSort(ListSortField.added)), isTrue);
    expect(canGroupByDate(byChanged), isTrue);
  });

  group('searchHits (#830)', () {
    final titled = _note(
      't',
      content: 'nothing here',
      title: 'Mango Rezepte',
      created: d1,
      updated: d1,
    );
    final tagged = _note('g', content: 'x', created: d1, updated: d2);
    final texty = _note(
      'x',
      content: 'Einkauf\nein Mango Lassi',
      created: d1,
      updated: d3,
    );
    final favText = _note(
      'f',
      content: 'Einkauf\nMango pur',
      pinned: true,
      created: d1,
      updated: d1,
    );
    final tags = {
      'g': [_tag('mango')],
    };

    List<String> hits(String q, {Set<String> tagIds = const {}}) => ids(
      searchHits(
        [titled, tagged, texty, favText],
        q,
        byChanged,
        tagIds: tagIds,
        tagsByNoteId: tags,
      ),
    );

    test(
      'title (or first line) before tag before text, then the chosen order',
      () {
        // texty (changed d3) beats the pinned favText (d1) at the same rank:
        // a hit list gives favourites no special place.
        expect(hits('mango'), ['t', 'g', 'x', 'f']);
      },
    );

    test('matches case-insensitively and ignores surrounding blanks', () {
      expect(hits('  MANGO '), ['t', 'g', 'x', 'f']);
    });

    test('regex characters in the query are literal', () {
      expect(hits('.*'), isEmpty);
    });

    test('a chosen tag still narrows the hits', () {
      expect(hits('mango', tagIds: {'mango'}), ['g']);
    });
  });

  test('withoutFoldedFavorites drops exactly the pinned notes', () {
    expect(ids(withoutFoldedFavorites(all)), ['a', 'b', 'c']);
  });

  group('providers', () {
    ProviderContainer open({List<Note> notes = const []}) {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) => db),
          notesProvider.overrideWith((ref) => Stream.value(notes)),
          allNoteTagsProvider.overrideWith(
            (ref) => Stream.value({
              'a': [_tag('t1')],
              'trashed': [_tag('t2')],
            }),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      return container;
    }

    test('grouping is off by default and remembered', () async {
      final container = open();
      expect(await container.read(notesGroupByDateProvider.future), isFalse);
      await container.read(notesGroupByDateProvider.notifier).choose(true);
      expect(container.read(notesGroupByDateProvider).value, isTrue);
    });

    test('the folded favourites are off by default and toggle', () async {
      final container = open();
      expect(
        await container.read(notesFavoritesCollapsedProvider.future),
        isFalse,
      );
      await container.read(notesFavoritesCollapsedProvider.notifier).toggle();
      expect(container.read(notesFavoritesCollapsedProvider).value, isTrue);
      await container.read(notesFavoritesCollapsedProvider.notifier).toggle();
      expect(container.read(notesFavoritesCollapsedProvider).value, isFalse);
    });

    test('a search gives the ranked hit list, not favourites first', () async {
      final container = open(notes: [pinned, a, c]);
      container.listen(filteredNotesProvider, (_, _) {});
      await pumpEventQueue();
      expect(ids(container.read(filteredNotesProvider).value!), [
        'p',
        'c',
        'a',
      ]);
      container.read(notesSearchProvider.notifier).set('mango');
      await pumpEventQueue();
      expect(ids(container.read(filteredNotesProvider).value!), ['p']);
      container.read(notesSearchProvider.notifier).set('zitrone');
      await pumpEventQueue();
      // The explicit title is searched too.
      expect(ids(container.read(filteredNotesProvider).value!), ['c']);
    });

    test('tags of trashed notes are not offered', () async {
      final container = open(notes: [a]);
      container.listen(notesTagsInUseProvider, (_, _) {});
      await pumpEventQueue();
      expect(
        [for (final t in container.read(notesTagsInUseProvider)) t.id],
        ['t1'],
      );
    });
  });
}

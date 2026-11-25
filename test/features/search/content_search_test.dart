import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/notes/data/note_search_snippet.dart';
import 'package:whispaste/features/search/data/providers.dart';

/// #628: one query over recordings, notes and snippets, grouped by area,
/// with the search syntax of the Aufnahmen page.
void main() {
  late HistoryDatabase db;
  final now = DateTime(2026, 6, 15, 12);

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> recording(
    String id,
    String text, {
    String lang = 'de',
    double sec = 10,
  }) => db.upsertEntry(
    HistoryEntriesCompanion.insert(
      id: id,
      timestamp: now.subtract(const Duration(hours: 1)),
      content: Value(text),
      language: Value(lang),
      durationSec: Value(sec),
    ),
  );

  Future<String> note(String text) async {
    final n = await db.createNote();
    await db.updateNoteContent(n.id, text);
    return n.id;
  }

  Future<void> snippet(String id, String title, String body) =>
      db.upsertSnippet(
        id: id,
        title: title,
        body: body,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      );

  Future<ContentSearchResults> search(String q, {bool private = true}) =>
      searchAllContent(db, q, now: now, includePrivate: private);

  Map<ContentSearchArea, List<String>> ids(ContentSearchResults r) => {
    for (final g in r.groups) g.area: [for (final h in g.shown) h.id],
  };

  test('one query finds every area, grouped in area order', () async {
    await recording('e1', 'Meeting about the budget');
    final n = await note('Budget plan for next year');
    await snippet('s1', 'Budget mail', 'Here is the budget.');
    await snippet('s2', 'Signature', 'Kind regards');

    final r = await search('budg');
    expect(ids(r), {
      ContentSearchArea.recordings: ['e1'],
      ContentSearchArea.notes: [n],
      ContentSearchArea.snippets: ['s1'],
    });
    expect(r.flat.map((h) => h.id), ['e1', n, 's1']);
    expect(r.withheld, isFalse);
  });

  test('an empty query searches nothing', () async {
    await snippet('s1', 'Budget', 'x');
    expect((await search('   ')).isEmpty, isTrue);
  });

  test('a hit carries the excerpt and the match offsets', () async {
    const text = 'First line.\nThe Budgetplan is due.';
    final n = await note(text);
    final hit = (await search('budget')).flat.single;
    expect(hit.id, n);
    expect(hit.excerpt?.match, 'Budgetplan');
    expect(text.substring(hit.matchStart!, hit.matchEnd!), 'Budgetplan');
  });

  test('a word part in the middle falls back to a substring match', () async {
    await snippet('s1', 'Mail', 'Our Jahresbudget is set.');
    final hit = (await search('budget')).flat.single;
    expect(hit.id, 's1');
    expect(hit.excerpt?.match, 'budget');
  });

  test('#tag keeps tagged notes and snippets, untagged ones drop', () async {
    final tagged = await note('Project alpha');
    await note('Project beta');
    await snippet('s1', 'Project', 'alpha');
    await snippet('s2', 'Project', 'beta');
    final tag = await db.createTag('work');
    await db.tagNote(tagged, tag.id);
    await db.tagSnippet('s1', tag.id);

    expect(ids(await search('#work project')), {
      ContentSearchArea.notes: [tagged],
      ContentSearchArea.snippets: ['s1'],
    });
  });

  test('a snippet must carry every named tag (#662)', () async {
    await snippet('s1', 'Reply', 'x');
    await snippet('s2', 'Reply', 'y');
    final work = await db.createTag('work');
    final mail = await db.createTag('mail');
    await db.tagSnippet('s1', work.id);
    await db.tagSnippet('s1', mail.id);
    await db.tagSnippet('s2', work.id);

    expect(ids(await search('#work #mail')), {
      ContentSearchArea.snippets: ['s1'],
    });
  });

  test('free text finds a snippet by its tag name', () async {
    await snippet('s1', 'Signature', 'Kind regards');
    final tag = await db.createTag('customers');
    await db.tagSnippet('s1', tag.id);

    expect(ids(await search('custom')), {
      ContentSearchArea.snippets: ['s1'],
    });
  });

  test('note and snippet hits carry their tags, by name', () async {
    final n = await note('Budget plan');
    await snippet('s1', 'Budget mail', 'x');
    final b = await db.createTag('beta');
    final a = await db.createTag('alpha');
    await db.tagNote(n, b.id);
    await db.tagSnippet('s1', b.id);
    await db.tagSnippet('s1', a.id);

    final hits = {for (final h in (await search('budget')).flat) h.id: h};
    expect(hits[n]!.tags, ['beta']);
    expect(hits['s1']!.tags, ['alpha', 'beta']);
  });

  test('lang:, longer: and shorter: match recordings only', () async {
    await recording('de1', 'Hallo Welt', lang: 'de', sec: 5);
    await recording('en1', 'Hello world', lang: 'en', sec: 120);
    await note('Hallo Notiz');
    await snippet('s1', 'Hallo', 'x');

    expect(ids(await search('lang:de')), {
      ContentSearchArea.recordings: ['de1'],
    });
    expect(ids(await search('longer:1m')), {
      ContentSearchArea.recordings: ['en1'],
    });
  });

  test('date: means the last change for notes and snippets', () async {
    await snippet('old', 'Budget', 'x');
    await db.upsertSnippet(
      id: 'older',
      title: 'Budget',
      body: 'x',
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now.subtract(const Duration(days: 30)),
    );
    final r = await search('budget date:7d');
    expect(ids(r)[ContentSearchArea.snippets], ['old']);
  });

  test('the closed PIN lock withholds recordings and notes', () async {
    await recording('e1', 'Budget call');
    await note('Budget note');
    await snippet('s1', 'Budget', 'x');

    final r = await search('budget', private: false);
    expect(ids(r), {
      ContentSearchArea.snippets: ['s1'],
    });
    expect(r.withheld, isTrue);
  });

  test('each area shows a bounded number and counts the rest', () async {
    for (var i = 0; i < 5; i++) {
      await snippet('s$i', 'Budget $i', 'x');
    }
    final r = await searchAllContent(
      db,
      'budget',
      now: now,
      shownPerArea: 2,
      candidates: 4,
    );
    final g = r.groups.single;
    expect(g.shown, hasLength(2));
    expect(g.total, 4);
    expect(g.more, isTrue);
  });

  test('the best match ranks first, not only the newest', () async {
    await snippet('body', 'Mail', 'a word about the invoice');
    await db.upsertSnippet(
      id: 'title',
      title: 'Invoice',
      body: 'x',
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 3)),
    );
    expect(ids(await search('invoice'))[ContentSearchArea.snippets], [
      'title',
      'body',
    ]);
  });

  group('contentMatchPattern', () {
    test('marks the whole word a prefix started', () {
      final p = contentMatchPattern(['bud'])!;
      expect(p.firstMatch('the Budgetplan here')![0], 'Budgetplan');
      expect(p.firstMatch('Jahresbudget'), isNull);
    });

    test('prefers the longer of two terms and reads any script', () {
      final p = contentMatchPattern(['über', 'überall'])!;
      expect(p.firstMatch('suche Überallhin')![0], 'Überallhin');
    });

    test('substring mode marks the term inside a word', () {
      final p = contentMatchPattern(['budget'], substring: true)!;
      expect(p.firstMatch('Jahresbudget')![0], 'budget');
    });

    test('no terms, no pattern', () {
      expect(contentMatchPattern(const []), isNull);
    });
  });

  test('noteSearchSnippet takes a pattern instead of the query', () {
    final s = noteSearchSnippet(
      'Alpha and Betatest',
      '',
      pattern: RegExp('beta\\w*', caseSensitive: false),
    )!;
    expect(s.match, 'Betatest');
    expect(s.before, 'Alpha and ');
  });

  group('opening a hit', () {
    ContentSearchHit hit(ContentSearchArea area) => ContentSearchHit(
      area: area,
      id: 'x1',
      title: 'T',
      preview: '',
      changedAt: now,
      matchStart: 4,
      matchEnd: 9,
    );

    test('a recording opens in the Aufnahmen detail', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      openContentSearchHit(c.read, hit(ContentSearchArea.recordings));
      expect(c.read(activePageProvider), 'history');
      expect(c.read(historyOpenEntryProvider), 'x1');
    });

    test('a note opens with the match to select', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      openContentSearchHit(c.read, hit(ContentSearchArea.notes));
      expect(c.read(activePageProvider), 'notes');
      expect(c.read(notesRevealTargetProvider), (
        noteId: 'x1',
        start: 4,
        end: 9,
      ));
    });

    test('a snippet opens beside its list', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      openContentSearchHit(c.read, hit(ContentSearchArea.snippets));
      expect(c.read(activePageProvider), 'snippets');
      expect(c.read(snippetsOpenTargetProvider), 'x1');
    });
  });
}

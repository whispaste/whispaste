/// The app's one search ranking: title before body, whole word before part,
/// all query words required, folding, typo tolerance behind exact hits, and
/// a bounded, fading boost from earlier picks.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/search/bounded_edit_distance.dart';
import 'package:whispaste/core/search/search_ranker.dart';

SearchDoc _snippet(String id, String title, String body) =>
    SearchDoc(id, [SearchField(title, 3), SearchField(body, 1)]);

List<String> _ids(List<SearchDoc> docs, String query, {SearchMemory? memory}) =>
    [
      for (final h in rankSearch(
        docs,
        query,
        memory: memory ?? SearchMemory.empty,
        nowUtc: _now,
      ))
        docs[h.index].id,
    ];

final _now = DateTime.utc(2026, 11, 1, 9);

void main() {
  final snippets = [
    _snippet(
      'feature',
      'New Feature',
      'Analysiere Produkt, Zielgruppen und Kern-Workflows.',
    ),
    _snippet(
      'pr',
      'Github Pull Requests',
      'Offene Issues und fehlgeschlagene GitHub-Actions-Workflows.',
    ),
    _snippet(
      'workflows',
      'Github Workflows Review',
      'Behebe CI-Fehler und spare Actions-Minuten.',
    ),
  ];

  group('ranking', () {
    test('a title match beats body-only matches (the "workflo" case)', () {
      expect(_ids(snippets, 'workflo').first, 'workflows');
    });

    test('a whole word beats a word start, which beats a part of a word', () {
      final docs = [
        const SearchDoc('part', [SearchField('Subworkflow', 1)]),
        const SearchDoc('start', [SearchField('Workflows', 1)]),
        const SearchDoc('whole', [SearchField('Workflow', 1)]),
      ];
      expect(_ids(docs, 'workflow'), ['whole', 'start', 'part']);
    });

    test('every query word must match, in any order', () {
      expect(_ids(snippets, 'review github'), ['workflows']);
      expect(_ids(snippets, 'github nothing'), isEmpty);
    });

    test('ties keep the base order and an empty query returns all of it', () {
      final docs = [
        const SearchDoc('a', [SearchField('Mail', 1)]),
        const SearchDoc('b', [SearchField('Mail', 1)]),
      ];
      expect(_ids(docs, 'mail'), ['a', 'b']);
      expect(_ids(snippets, '  '), ['feature', 'pr', 'workflows']);
    });

    test('folds case, umlauts and ß', () {
      final docs = [
        const SearchDoc('k', [SearchField('Tastenkürzel', 1)]),
        const SearchDoc('s', [SearchField('Straße', 1)]),
      ];
      expect(_ids(docs, 'TASTENKURZEL'), ['k']);
      expect(_ids(docs, 'strasse'), ['s']);
    });
  });

  group('typos', () {
    test('a typo still finds the word, behind exact matches', () {
      final docs = [
        const SearchDoc('typo', [SearchField('Workflow', 3)]),
        const SearchDoc('exact', [SearchField('Wrkflow', 1)]),
      ];
      expect(_ids(docs, 'wrkflow'), ['exact', 'typo']);
    });

    test('also while the word is still being typed', () {
      final docs = [
        const SearchDoc('w', [SearchField('Workflows', 1)]),
      ];
      expect(_ids(docs, 'wrkflo'), ['w']);
    });

    test('short words get no typo tolerance', () {
      final docs = [
        const SearchDoc('cat', [SearchField('cat', 1)]),
      ];
      expect(_ids(docs, 'cut'), isEmpty);
    });

    test('the distance stops at its bound', () {
      expect(boundedEditDistance('workflow', 'wrokflow', 1), 1);
      expect(boundedEditDistance('workflow', 'wrkflw', 1), isNull);
      expect(boundedEditDistance('abc', 'abcdef', 2), isNull);
    });
  });

  group('learning from picks', () {
    final mails = [
      const SearchDoc('a', [SearchField('Mail to the team', 3)]),
      const SearchDoc('b', [SearchField('Mail to customers', 3)]),
    ];

    SearchMemory picked(String id, int count, DateTime at) => SearchMemory({
      id: {'mail': SearchPickStat(count, at)},
    });

    test('an item picked for a word moves up for that word', () {
      expect(_ids(mails, 'mail'), ['a', 'b']);
      expect(_ids(mails, 'mail', memory: picked('b', 3, _now)), ['b', 'a']);
    });

    test('a hit reports the item words a pick records, never the query', () {
      final hit = rankSearch(snippets, 'workflo', nowUtc: _now).first;
      expect(hit.matchedWords, {'workflows'});
    });

    test('the boost fades with time', () {
      final fresh = rankSearch(
        mails,
        'mail',
        memory: picked('b', 3, _now),
        nowUtc: _now,
      ).first.score;
      final old = rankSearch(
        mails,
        'mail',
        memory: picked('b', 3, _now.subtract(const Duration(days: 365))),
        nowUtc: _now,
      ).firstWhere((h) => mails[h.index].id == 'b').score;
      expect(old, lessThan(fresh));
    });

    test('picks never lift a body-only hit above a title word hit', () {
      final docs = [
        _snippet('title', 'Workflow review', 'CI'),
        _snippet('body', 'Pull requests', 'Workflow failures'),
      ];
      final lifted = SearchMemory({
        'body': {'workflow': SearchPickStat(1000, _now)},
      });
      expect(_ids(docs, 'workflow', memory: lifted).first, 'title');
    });
  });

  test('large lists rank the same off the UI isolate', () async {
    final many = [
      for (var i = 0; i < 50; i++)
        SearchDoc('$i', [SearchField('note $i workflow', 1)]),
    ];
    final hits = await rankSearchAsync(
      many,
      'workflow',
      nowUtc: _now,
      isolateFrom: 10,
    );
    expect(
      hits.map((h) => h.index),
      rankSearch(many, 'workflow', nowUtc: _now).map((h) => h.index),
    );
  });
}

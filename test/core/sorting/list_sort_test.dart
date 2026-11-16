import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/sorting/list_sort.dart';

/// Minimal [ListSortable] for the pure comparator tests.
class _Entry implements ListSortable {
  _Entry(
    this.sortId, {
    String? title,
    this.sortResult = '',
    required this.sortCreatedAt,
    DateTime? changed,
  }) : sortTitle = title ?? sortId,
       sortChangedAt = changed ?? sortCreatedAt;

  @override
  final String sortId;
  @override
  final String sortTitle;
  @override
  final String sortResult;
  @override
  final DateTime sortCreatedAt;
  @override
  final DateTime sortChangedAt;

  @override
  String toString() => sortId;
}

final _t0 = DateTime(2026, 1, 1);
DateTime _day(int n) => _t0.add(Duration(days: n));

List<String> _ids(List<_Entry> entries) => [for (final e in entries) e.sortId];

void main() {
  group('compareListText', () {
    test('ignores case', () {
      expect(compareListText('apple', 'Banana'), lessThan(0));
      expect(compareListText('Banana', 'apple'), greaterThan(0));
    });

    test('folds diacritics so umlauts sort next to their base letter', () {
      final words = ['Zebra', 'Ärger', 'Arzt', 'Ofen', 'Öl', 'Ulm'];
      final sorted = [...words]..sort(compareListText);
      // Ö folds to o, so Öl sorts with the o-words, after Ofen.
      expect(sorted, ['Ärger', 'Arzt', 'Ofen', 'Öl', 'Ulm', 'Zebra']);
    });

    test('skips leading punctuation and whitespace', () {
      expect(compareListText('  -beta', 'alpha'), greaterThan(0));
      expect(compareListText('"gamma', 'beta'), greaterThan(0));
    });

    test('compares digit runs by value', () {
      final sorted = ['item 10', 'item 2', 'item 1'];
      sorted.sort(compareListText);
      expect(sorted, ['item 1', 'item 2', 'item 10']);
    });

    test('is a total order: different strings never compare equal', () {
      expect(compareListText('Abc', 'abc'), isNot(0));
      expect(compareListText('a', 'a'), 0);
    });
  });

  group('ListSort codec', () {
    const allowed = {ListSortField.trigger, ListSortField.added};

    test('round-trips a plain and a reversed sort', () {
      for (final sort in [
        const ListSort(ListSortField.added),
        const ListSort(ListSortField.trigger, reversed: true),
      ]) {
        expect(ListSort.decode(sort.encode(), allowed: allowed), sort);
      }
    });

    test('an unknown, malformed or disallowed value decodes to null', () {
      expect(ListSort.decode(null, allowed: allowed), isNull);
      expect(ListSort.decode('nonsense', allowed: allowed), isNull);
      expect(ListSort.decode('trigger:backwards', allowed: allowed), isNull);
      expect(ListSort.decode('trigger:reversed:x', allowed: allowed), isNull);
      expect(ListSort.decode('result', allowed: allowed), isNull);
    });
  });

  group('sortListItems', () {
    final alpha = _Entry('a', title: 'alpha', sortCreatedAt: _day(1));
    final beta = _Entry(
      'b',
      title: 'beta',
      sortResult: 'zzz',
      sortCreatedAt: _day(2),
      changed: _day(9),
    );
    final gamma = _Entry(
      'c',
      title: 'gamma',
      sortResult: 'aaa',
      sortCreatedAt: _day(3),
      changed: _day(5),
    );
    final all = [beta, gamma, alpha];

    test('title sorts A–Z regardless of input order', () {
      expect(_ids(sortListItems(all, const ListSort(ListSortField.title))), [
        'a',
        'b',
        'c',
      ]);
    });

    test('result sorts A–Z on the result text', () {
      expect(
        _ids(sortListItems(all, const ListSort(ListSortField.result))),
        // alpha has no result (empty text sorts first), then aaa, then zzz.
        ['a', 'c', 'b'],
      );
    });

    test('added sorts newest first and reversing gives oldest first', () {
      expect(_ids(sortListItems(all, const ListSort(ListSortField.added))), [
        'c',
        'b',
        'a',
      ]);
      expect(
        _ids(
          sortListItems(
            all,
            const ListSort(ListSortField.added, reversed: true),
          ),
        ),
        ['a', 'b', 'c'],
      );
    });

    test('changed uses the last content change, not creation time', () {
      expect(_ids(sortListItems(all, const ListSort(ListSortField.changed))), [
        'b',
        'c',
        'a',
      ]);
    });

    test('reversing a text sort flips only the primary order', () {
      expect(
        _ids(
          sortListItems(
            all,
            const ListSort(ListSortField.title, reversed: true),
          ),
        ),
        ['c', 'b', 'a'],
      );
    });

    test('is independent of the input order', () {
      const sort = ListSort(ListSortField.changed);
      final forward = _ids(sortListItems(all, sort));
      final backward = _ids(sortListItems(all.reversed, sort));
      expect(backward, forward);
    });
  });

  group('tie rule', () {
    test('equal primary key falls back to A–Z on the text, then creation, '
        'then id', () {
      final sameDayB = _Entry('x1', title: 'Bravo', sortCreatedAt: _day(4));
      final sameDayA = _Entry('x2', title: 'Alpha', sortCreatedAt: _day(4));
      final sortedByAdded = sortListItems([
        sameDayB,
        sameDayA,
      ], const ListSort(ListSortField.added));
      expect(_ids(sortedByAdded), ['x2', 'x1']);

      final sameText1 = _Entry('k2', title: 'Same', sortCreatedAt: _day(7));
      final sameText0 = _Entry('k1', title: 'Same', sortCreatedAt: _day(6));
      final sameTextSorted = sortListItems([
        sameText1,
        sameText0,
      ], const ListSort(ListSortField.title));
      expect(_ids(sameTextSorted), ['k1', 'k2']);
    });

    test('equal creation time falls back to the id', () {
      final first = _Entry('a', title: 'Dup', sortCreatedAt: _day(1));
      final second = _Entry('b', title: 'Dup', sortCreatedAt: _day(1));
      expect(
        _ids(
          sortListItems([second, first], const ListSort(ListSortField.title)),
        ),
        ['a', 'b'],
      );
    });
  });

  group('sortedByText', () {
    test('orders by the given text, A–Z', () {
      final names = ['Zeta', 'alpha', 'Ärger'];
      expect(sortedByText(names, (n) => n), ['alpha', 'Ärger', 'Zeta']);
    });
  });
}

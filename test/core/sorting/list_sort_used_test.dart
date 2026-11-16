import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/search/search_ranker.dart';
import 'package:whispaste/core/sorting/list_sort.dart';

class _Used implements UsageSortable {
  _Used(this.sortId, this.sortUsedAt);

  @override
  final String sortId;
  @override
  final DateTime? sortUsedAt;
  @override
  String get sortTitle => sortId;
  @override
  String get sortResult => '';
  @override
  DateTime get sortCreatedAt => DateTime(2026);
  @override
  DateTime get sortChangedAt => DateTime(2026);
}

void main() {
  final items = [
    _Used('b-never', null),
    _Used('a-old', DateTime(2026, 1)),
    _Used('c-new', DateTime(2026, 5)),
    _Used('a-never', null),
  ];
  List<String> ids(ListSort s) => [
    for (final i in sortListItems(items, s)) i.sortId,
  ];

  test('used: most recent first, never used last in A-Z', () {
    expect(ids(const ListSort(ListSortField.used)), [
      'c-new',
      'a-old',
      'a-never',
      'b-never',
    ]);
  });

  test('used reversed: least recent first, never used first', () {
    expect(ids(const ListSort(ListSortField.used, reversed: true)), [
      'a-never',
      'b-never',
      'a-old',
      'c-new',
    ]);
  });

  test('used round-trips and is only decoded where allowed', () {
    const sort = ListSort(ListSortField.used, reversed: true);
    expect(sort.encode(), 'used:reversed');
    expect(ListSort.decode(sort.encode(), allowed: {ListSortField.used}), sort);
    expect(ListSort.decode('used', allowed: {ListSortField.title}), isNull);
  });

  test('search ranks a title hit before a body-only hit', () {
    final docs = [
      const SearchDoc('body', [
        SearchField('Other', SearchWeight.title),
        SearchField('mentions invoice here', SearchWeight.body),
      ]),
      const SearchDoc('title', [
        SearchField('Invoice', SearchWeight.title),
        SearchField('text', SearchWeight.body),
      ]),
    ];
    final hits = rankSearch(docs, 'invoice');
    expect([for (final h in hits) docs[h.index].id], ['title', 'body']);
  });
}

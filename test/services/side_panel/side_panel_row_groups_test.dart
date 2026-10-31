import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:whispaste/services/side_panel/side_panel_row_groups.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';

SidePanelRow _row(String id, DateTime? createdAt) =>
    SidePanelRow(id: id, title: id, createdAt: createdAt);

List<String> _describe(List<SidePanelListItem> items) => [
  for (final item in items)
    switch (item) {
      SidePanelDateHeader(:final label) => '# $label',
      SidePanelRowItem(:final row) => row.id,
    },
];

void main() {
  final now = DateTime(2026, 10, 18, 15, 30);

  List<SidePanelListItem> group(List<SidePanelRow> rows) => groupSidePanelRows(
    rows,
    now: now,
    todayLabel: 'Today',
    yesterdayLabel: 'Yesterday',
    locale: 'en_US',
  );

  test('adds a header whenever the calendar day changes', () {
    final items = group([
      _row('a', DateTime(2026, 10, 18, 9)),
      _row('b', DateTime(2026, 10, 18, 8)),
      _row('c', DateTime(2026, 10, 17, 23, 59)),
      _row('d', DateTime(2026, 10, 14, 12)),
    ]);
    expect(_describe(items), [
      '# Today',
      'a',
      'b',
      '# Yesterday',
      'c',
      '# Oct 14, 2026',
      'd',
    ]);
  });

  test('rows without a date appear without a header', () {
    final items = group([_row('x', null), _row('y', DateTime(2026, 10, 18))]);
    expect(_describe(items), ['x', '# Today', 'y']);
  });

  test('an empty list yields no items', () {
    expect(group(const []), isEmpty);
  });

  test('the day boundary uses the calendar day, not 24-hour offsets', () {
    // 00:05 is still today, although it is 15 h before `now` (15:30).
    final items = group([_row('early', DateTime(2026, 10, 18, 0, 5))]);
    expect(_describe(items), ['# Today', 'early']);
  });

  test(
    'day headers use the month names of he and ru once locale data loads',
    () async {
      await initializeDateFormatting();
      String headerFor(String locale) => _describe(
        groupSidePanelRows(
          [_row('old', DateTime(2026, 1, 2))],
          now: now,
          todayLabel: 'Today',
          yesterdayLabel: 'Yesterday',
          locale: locale,
        ),
      ).first;
      // Each locale formats the same day with its own month name.
      expect(headerFor('ru'), contains('янв'));
      expect(headerFor('he'), isNot(contains('Jan')));
      expect(headerFor('he'), isNot(headerFor('en_US')));
    },
  );

  test('an unknown locale falls back to the default date format', () {
    final items = groupSidePanelRows(
      [_row('old', DateTime(2026, 1, 2))],
      now: now,
      todayLabel: 'Today',
      yesterdayLabel: 'Yesterday',
      locale: 'xx_NOPE',
    );
    expect(_describe(items).first, startsWith('# '));
    expect(_describe(items).first, isNot('# Today'));
  });

  test('a corrupted field drops only that value, not the whole row', () {
    final restored = SidePanelRow.fromMap({
      'id': 'bad',
      'title': 'still here',
      'createdAt': 'yesterday',
      'colorSlot': {'oops': true},
    });
    expect(restored.id, 'bad');
    expect(restored.title, 'still here');
    expect(restored.createdAt, isNull);
    expect(restored.colorSlot, isNull);
  });

  test('snapshot round-trip keeps createdAt', () {
    final created = DateTime(2026, 10, 18, 9, 41);
    final restored = SidePanelRow.fromMap(_row('r', created).toMap());
    expect(restored.createdAt, created);
    expect(SidePanelRow.fromMap({'id': 'z'}).createdAt, isNull);
  });
}

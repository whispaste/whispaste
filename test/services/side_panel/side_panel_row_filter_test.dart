import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_row_filter.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';

const _rows = [
  SidePanelRow(id: 'a', title: 'Meeting notes', subtitle: '09:15'),
  SidePanelRow(id: 'b', title: 'Grocery list', subtitle: '08:02'),
  SidePanelRow(id: 'c', title: 'Standup summary', subtitle: 'Yesterday'),
];

void main() {
  group('filterSidePanelRows', () {
    test('empty query returns every row, unchanged order', () {
      expect(filterSidePanelRows(_rows, ''), _rows);
    });

    test('whitespace-only query is treated as empty', () {
      expect(filterSidePanelRows(_rows, '   '), _rows);
    });

    test('matches against the title', () {
      final result = filterSidePanelRows(_rows, 'grocery');
      expect(result.map((r) => r.id), ['b']);
    });

    test('matches against the subtitle', () {
      final result = filterSidePanelRows(_rows, 'yesterday');
      expect(result.map((r) => r.id), ['c']);
    });

    test('match is case-insensitive', () {
      final result = filterSidePanelRows(_rows, 'MEETING');
      expect(result.map((r) => r.id), ['a']);
    });

    test('no matches returns an empty list', () {
      expect(filterSidePanelRows(_rows, 'nonexistent'), isEmpty);
    });

    test('query matching multiple rows preserves original order', () {
      const rows = [
        SidePanelRow(id: 'x', title: 'apple pie'),
        SidePanelRow(id: 'y', title: 'banana split'),
        SidePanelRow(id: 'z', title: 'apple juice'),
      ];
      final result = filterSidePanelRows(rows, 'apple');
      expect(result.map((r) => r.id), ['x', 'z']);
    });
  });
}

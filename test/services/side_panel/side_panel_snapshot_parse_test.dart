import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';

void main() {
  group('SidePanelRow.fromMap tolerates bad values', () {
    test('NaN and infinite numbers drop only that field', () {
      final row = SidePanelRow.fromMap({
        'id': 'a',
        'title': 'Hello',
        'colorSlot': double.nan,
        'createdAt': double.infinity,
      });
      expect(row.id, 'a');
      expect(row.title, 'Hello');
      expect(row.colorSlot, isNull);
      expect(row.createdAt, isNull);
    });

    test('timestamps outside the DateTime range become null', () {
      expect(
        SidePanelRow.fromMap({'id': 'a', 'createdAt': 1e300}).createdAt,
        isNull,
      );
      expect(
        SidePanelRow.fromMap({'id': 'a', 'createdAt': -1e300}).createdAt,
        isNull,
      );
    });

    test('a valid timestamp is kept, whole or fractional', () {
      final whole = SidePanelRow.fromMap({
        'id': 'a',
        'createdAt': 1700000000000,
      });
      final fraction = SidePanelRow.fromMap({'id': 'a', 'createdAt': 1.5e12});
      expect(
        whole.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(
        fraction.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1500000000000),
      );
    });

    test('wrong types fall back to the empty value', () {
      final row = SidePanelRow.fromMap({
        'id': 5,
        'title': ['x'],
        'subtitle': {'a': 1},
        'content': true,
        'kind': 3,
        'colorSlot': 'red',
        'createdAt': 'yesterday',
      });
      expect(row.id, '');
      expect(row.title, '');
      expect(row.subtitle, '');
      expect(row.content, '');
      expect(row.kind, SidePanelRowKind.text);
      expect(row.colorSlot, isNull);
      expect(row.createdAt, isNull);
    });

    test('an image with any non-byte element is dropped, not cast', () {
      expect(
        SidePanelRow.fromMap({
          'id': 'a',
          'imageBytes': [1, 'x', 3],
        }).imageBytes,
        isNull,
      );
      expect(
        SidePanelRow.fromMap({
          'id': 'a',
          'imageBytes': [1, 2, 255],
        }).imageBytes,
        [1, 2, 255],
      );
      expect(
        SidePanelRow.fromMap({
          'id': 'a',
          'imageBytes': [1, 256],
        }).imageBytes,
        isNull,
      );
    });
  });

  group('SidePanelSnapshot.fromMap keeps the good rows', () {
    test('a broken row is dropped and its neighbours still render', () {
      final snapshot = SidePanelSnapshot.fromMap({
        'transcriptions': [
          {'id': 'ok-1', 'title': 'First'},
          'not a map',
          {'id': 'bad-time', 'title': 'Second', 'createdAt': double.nan},
          null,
          {'id': 'ok-2', 'title': 'Third'},
        ],
        'snippets': 'not a list',
        'visible': 'yes',
        'edge': 42,
      });
      expect(snapshot.transcriptions.map((r) => r.id), [
        'ok-1',
        'bad-time',
        'ok-2',
      ]);
      expect(snapshot.transcriptions[1].createdAt, isNull);
      expect(snapshot.snippets, isEmpty);
      expect(snapshot.visible, isFalse);
      expect(snapshot.edge, 'left');
    });

    test('a valid edge and visible flag are read', () {
      final snapshot = SidePanelSnapshot.fromMap({
        'visible': true,
        'edge': 'right',
      });
      expect(snapshot.visible, isTrue);
      expect(snapshot.edge, 'right');
    });
  });
}

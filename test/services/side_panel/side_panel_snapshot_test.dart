import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';

void main() {
  group('SidePanelRow', () {
    test('round-trips through toMap/fromMap', () {
      const row = SidePanelRow(
        id: 'abc',
        title: 'Hello',
        subtitle: '2 min ago',
        content: 'Hello, this is the full unabridged body text.',
        kind: SidePanelRowKind.image,
        imageBytes: [1, 2, 3],
        colorSlot: 3,
      );
      final restored = SidePanelRow.fromMap(row.toMap());
      expect(restored.id, 'abc');
      expect(restored.title, 'Hello');
      expect(restored.subtitle, '2 min ago');
      expect(restored.content, 'Hello, this is the full unabridged body text.');
      expect(restored.kind, SidePanelRowKind.image);
      expect(restored.imageBytes, [1, 2, 3]);
      expect(restored.colorSlot, 3);
    });

    test(
      'fromMap defaults kind to text, content to empty and colorSlot to null '
      'on a missing value',
      () {
        final row = SidePanelRow.fromMap({'id': 'x', 'title': 'y'});
        expect(row.kind, SidePanelRowKind.text);
        expect(row.subtitle, '');
        expect(row.content, '');
        expect(row.imageBytes, isNull);
        expect(row.colorSlot, isNull);
      },
    );
  });

  group('SidePanelSnapshot', () {
    test('round-trips through toMap/fromMap', () {
      const snapshot = SidePanelSnapshot(
        visible: true,
        transcriptions: [SidePanelRow(id: 't1', title: 'Transcript')],
        snippets: [SidePanelRow(id: 's1', title: 'Snippet')],
        clipboardHistory: [SidePanelRow(id: 'c1', title: 'Clipboard')],
      );
      final restored = SidePanelSnapshot.fromMap(snapshot.toMap());
      expect(restored.visible, isTrue);
      expect(restored.transcriptions.single.id, 't1');
      expect(restored.snippets.single.id, 's1');
      expect(restored.clipboardHistory.single.id, 'c1');
    });

    test('fromMap defaults to invisible with empty lists', () {
      final snapshot = SidePanelSnapshot.fromMap(const {});
      expect(snapshot.visible, isFalse);
      expect(snapshot.transcriptions, isEmpty);
      expect(snapshot.snippets, isEmpty);
      expect(snapshot.clipboardHistory, isEmpty);
    });
  });
}

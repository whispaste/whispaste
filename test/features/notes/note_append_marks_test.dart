import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_append_marks.dart';

void main() {
  final t1 = DateTime(2026, 11, 6, 14, 32);
  final t2 = DateTime(2026, 11, 6, 15, 10);
  final t3 = DateTime(2026, 11, 6, 16);

  group('placeAppendMarks (#803)', () {
    test('places each mark at the start of its dictation', () {
      const text = 'Earlier thought\n\nBuy oat milk\n\nCall the bank';
      final placed = placeAppendMarks(text, [
        (anchor: 'Buy oat milk', appendedAt: t1),
        (anchor: 'Call the bank', appendedAt: t2),
      ]);
      expect(placed, [
        PlacedAppendMark(offset: text.indexOf('Buy'), appendedAt: t1),
        PlacedAppendMark(offset: text.indexOf('Call'), appendedAt: t2),
      ]);
    });

    test('two dictations with the same first line land on their own '
        'lines', () {
      const text = 'Note\n\nTodo\n\nTodo';
      final placed = placeAppendMarks(text, [
        (anchor: 'Todo', appendedAt: t1),
        (anchor: 'Todo', appendedAt: t2),
      ]);
      expect(placed.map((m) => m.offset), [6, 12]);
    });

    test('a dictation the user removed loses its mark, the next one '
        'still finds its line', () {
      const text = 'Buy oat milk\n\nCall the bank';
      final placed = placeAppendMarks(text, [
        (anchor: 'Buy oat milk', appendedAt: t1),
        (anchor: 'Rewritten away', appendedAt: t2),
        (anchor: 'Call the bank', appendedAt: t3),
      ]);
      expect(placed.map((m) => m.appendedAt), [t1, t3]);
    });

    test('an empty anchor is never placed', () {
      expect(placeAppendMarks('Text', [(anchor: '', appendedAt: t1)]), isEmpty);
    });
  });
}

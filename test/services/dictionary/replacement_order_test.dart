import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/replacement_order.dart';

void main() {
  const ids = ['a', 'b', 'c'];

  group('movedReplacementIds', () {
    test('moves one place up or down', () {
      expect(movedReplacementIds(ids, 'b', -1), ['b', 'a', 'c']);
      expect(movedReplacementIds(ids, 'b', 1), ['a', 'c', 'b']);
    });

    test('ends and unknown ids leave the order unchanged', () {
      expect(movedReplacementIds(ids, 'a', -1), ids);
      expect(movedReplacementIds(ids, 'c', 1), ids);
      expect(movedReplacementIds(ids, 'x', 1), ids);
    });
  });

  test('reorderedReplacementIds applies a drag', () {
    expect(reorderedReplacementIds(ids, 0, 2), ['b', 'c', 'a']);
    expect(reorderedReplacementIds(ids, 2, 0), ['c', 'a', 'b']);
    expect(reorderedReplacementIds(ids, 5, 0), ids);
  });
}

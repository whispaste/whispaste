import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/level_history/level_history_bars.dart';

void main() {
  group('WpLevelHistory', () {
    test('starts silent with one entry per bar', () {
      expect(WpLevelHistory.zeros(3), [0.0, 0.0, 0.0]);
    });

    test('a push drops the oldest value and appends the newest', () {
      final once = WpLevelHistory.push([0.1, 0.2, 0.3], 0.9);
      expect(once, [0.2, 0.3, 0.9]);
      expect(once, hasLength(3));
    });

    test('levels are clamped to 0..1 and NaN counts as silence', () {
      expect(WpLevelHistory.push([0.0, 0.0], 1.7), [0.0, 1.0]);
      expect(WpLevelHistory.push([0.0, 0.0], -0.4), [0.0, 0.0]);
      expect(WpLevelHistory.push([0.5, 0.5], double.nan), [0.5, 0.0]);
    });

    test('the newest bar is the last index', () {
      final history = WpLevelHistory.zeros(22);
      expect(WpLevelHistory.newestIndex(history), 21);
      expect(WpLevelHistory.newestIndex(WpLevelHistory.push(history, 0.4)), 21);
    });

    test('an empty history has no newest bar and stays empty', () {
      expect(WpLevelHistory.newestIndex(const []), -1);
      expect(WpLevelHistory.push(const [], 0.5), isEmpty);
    });
  });
}

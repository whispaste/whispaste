import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/overview_logic.dart';

void main() {
  group('blocks on or off by default', () {
    test('the system card is off until it is switched on', () {
      expect(OverviewBlock.system.shownByDefault, isFalse);
      expect(
        overviewBlockShown(
          OverviewBlock.system,
          hidden: const {},
          shown: const {},
        ),
        isFalse,
      );
      expect(
        overviewBlockShown(
          OverviewBlock.system,
          hidden: const {},
          shown: const {OverviewBlock.system},
        ),
        isTrue,
      );
    });

    test('the other blocks stay on until they are hidden', () {
      expect(OverviewBlock.storage.shownByDefault, isTrue);
      expect(
        overviewBlockShown(
          OverviewBlock.storage,
          hidden: const {},
          shown: const {},
        ),
        isTrue,
      );
      expect(
        overviewBlockShown(
          OverviewBlock.storage,
          hidden: const {OverviewBlock.storage},
          shown: const {},
        ),
        isFalse,
      );
    });

    test('an install without the new key keeps every existing block', () {
      expect(overviewShownBlocksFromStored(null), isEmpty);
      expect(overviewHiddenBlocksFromStored(null), isEmpty);
    });

    test('shown ids round-trip and unknown ids are dropped', () {
      const shown = {OverviewBlock.system};
      final stored = overviewShownBlocksToStored(shown);
      expect(stored, 'system');
      expect(overviewShownBlocksFromStored('$stored, retired'), shown);
    });
  });
}

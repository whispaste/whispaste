// Fixture checks for the store screenshot demo data (store_demo_data.dart).
//
// The history column of the store shots must not show near-identical avatars,
// so the seeded entries cover the categorical colour slots and never repeat one
// on two consecutive rows. This is a plain unit test, so it runs in every suite.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart' show WpCategorySlot;

import 'store_demo_data.dart';

void main() {
  const categorySlotCount = 8; // WpCategorySlot.categories.length

  test('WpCategorySlot.categories has not drifted from 8', () {
    expect(
      WpCategorySlot.categories.length,
      categorySlotCount,
      reason:
          'this fixture assumes 8 rotation-eligible slots; if that moved, '
          'the coverage assertions below need to move with it',
    );
  });

  for (final (localeName, entries) in [
    ('en', demoEntriesEn),
    ('de', demoEntriesDe),
    ('ru', demoEntriesRu),
  ]) {
    test('$localeName: at least 6 of 8 categorical slots are represented', () {
      final distinctSlots = entries.map((e) => e.colorSlot).toSet();
      expect(
        distinctSlots.length,
        greaterThanOrEqualTo(6),
        reason:
            '$localeName demo entries cover only $distinctSlots '
            '(${distinctSlots.length}/$categorySlotCount): the store '
            'screenshots would show a near-identical column of avatars',
      );
    });

    test('$localeName: no two consecutive entries share a color slot', () {
      for (var i = 1; i < entries.length; i++) {
        expect(
          entries[i].colorSlot,
          isNot(entries[i - 1].colorSlot),
          reason:
              '$localeName entries ${entries[i - 1].id} and ${entries[i].id} '
              'both draw slot ${entries[i].colorSlot}',
        );
      }
    });
  }
}

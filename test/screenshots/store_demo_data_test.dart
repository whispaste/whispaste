// Fixture guard for the store screenshot demo data: the slot count the
// seeded avatars rotate through must not drift without the fixture noticing.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart' show WpCategorySlot;

void main() {
  test('WpCategorySlot.categories has not drifted from 8', () {
    expect(
      WpCategorySlot.categories.length,
      8,
      reason:
          'the store demo data (test/screenshots/store_demo_data.dart) assumes '
          '8 rotation-eligible slots; if that moved, its colour assignment '
          'needs to move with it',
    );
  });
}

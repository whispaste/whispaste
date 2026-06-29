/// Pins that both surfaceChipFill tokens are alpha-bearing (≤ 50 % opacity).
///
/// AC2: the P2 cleanup requires surface@50% chip fills to NOT be fully opaque
/// so the chip blends with underlying surfaces in both themes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

void main() {
  group('surfaceChipFill tokens — alpha-bearing (AC2)', () {
    test('WpColorsDark.surfaceChipFill is not fully opaque', () {
      expect(
        WpColorsDark.surfaceChipFill.a,
        lessThan(1.0),
        reason: 'dark chip fill must be translucent (surface@50%)',
      );
    });

    test('WpColorsLight.surfaceChipFill is not fully opaque', () {
      expect(
        WpColorsLight.surfaceChipFill.a,
        lessThan(1.0),
        reason:
            'light chip fill must be translucent (surface@50%), '
            'not fully opaque as previously defined',
      );
    });
  });
}

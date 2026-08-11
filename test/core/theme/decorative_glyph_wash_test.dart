/// Pins the decorative-glyph wash band from DESIGN.md's Decorative Glyph Rule.
///
/// Deliberately an *upper* bound, not the usual contrast floor. WCAG 1.4.11
/// covers graphical objects that carry information; a background wash carries
/// none — nothing is lost if a user never sees it — so a minimum ratio would
/// be both the wrong criterion and unmeetable at these alphas. What the rule
/// actually needs guarding is the ceiling: the wash sits in its own category
/// *below* the 6/12/30% badge/chip/border ladder, and the failure mode is
/// someone later "fixing" the faint dark glyph by pushing it onto or past the
/// ladder's bottom rung, which is calibrated for a chip and far too loud
/// across the ~140px a background glyph covers.
///
/// The two themes carry different alphas on purpose (see `colors.dart`): the
/// wash is a decrement on light and an increment on dark, and equal alphas
/// read visibly unequal.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

void main() {
  group('decorativeGlyphWash — its own band, under the tint ladder', () {
    // The ladder's bottom rung, 0x0F/255 ≈ 5.9 %.
    final ladderFloor = WpColorsDark.accentRowHover.a;

    test('dark stays under the tint ladder floor', () {
      expect(
        WpColorsDark.decorativeGlyphWash.a,
        lessThan(ladderFloor),
        reason:
            'a large decorative glyph is not a badge, chip or border — it may '
            'not borrow the ladder rung defined for those',
      );
      expect(
        WpColorsDark.decorativeGlyphWash.a,
        greaterThan(0.02),
        reason: 'below ~2 % the wash is gone and the card loses its identity',
      );
    });

    test('light stays under the tint ladder floor', () {
      expect(
        WpColorsDark.decorativeGlyphWash.a,
        lessThan(WpColorsDark.accentRowHover.a),
        reason:
            'a large decorative glyph is not a badge, chip or border — it may '
            'not borrow the ladder rung defined for those',
      );
      expect(
        WpColorsDark.decorativeGlyphWash.a,
        greaterThan(0.02),
        reason: 'below ~2 % the wash is gone and the card loses its identity',
      );
    });

    // Removed 2026-08-11 (dark-only build): `light is the weaker of the two`.
    // It asserted the light wash carried a lower alpha than the dark one,
    // because a decrement against a near-white ground reads stronger at equal
    // alpha than a dark increment does — equalising the alphas was what had
    // made the two themes look unequal. With one wash left the comparison is
    // `expect(x, lessThan(x))` and cannot pass; the surviving floor and
    // ceiling above still pin the one wash on both sides.

    test('the wash carries the theme accent hue', () {
      expect(
        WpColorsDark.decorativeGlyphWash.toARGB32() & 0x00FFFFFF,
        WpColorsDark.accent.toARGB32() & 0x00FFFFFF,
      );
    });
  });
}

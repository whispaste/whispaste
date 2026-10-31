// The history avatar's *material*, as opposed to its hue.
//
// `history_avatar_category_color_test.dart` owns the colour question — which
// slot an entry wears and that the glyph never claims a category. This file
// owns the other half: what the disc is made of. The two are deliberately
// apart because they fail for unrelated reasons and a reader chasing one
// should not have to read the other.
//
// Three things are pinned here, all of them ported from the nav rail's icon
// chips (`lib/widgets/sidebar.dart`) when the maintainer asked for that look on
// the entry avatars:
//
//   1. the disc is a **three-stop vertical gradient** whose first tenth is a
//      precomposited gloss — one gradient, not a fill with a highlight painted
//      over it;
//   2. depth has **one source per theme** (*The Depth-Source Rule*): the offset
//      shadow exists on light and is absent on dark, where the disc's own
//      brightness delta against the plane is the whole depth source;
//   3. the shape stays a **circle**. The chip's material moved onto the disc;
//      the disc's geometry did not move onto the chip.
//
// The contrast numbers those choices have to clear live in
// `test/core/theme/wcag_contrast_test.dart` — this file only pins the
// structure, because a decoration can be perfectly legible and still be the
// wrong material.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';

import '../../fixtures/test_helpers.dart';

Future<BoxDecoration> _pumpAvatar(
  WidgetTester tester, {
  WpCategorySlot slot = WpCategorySlot.iris,
}) async {
  await tester.pumpWidget(
    makeTestable(
      Center(
        child: HistoryEntryAvatar(
          color: slot.color(),
          icon: historyAvatarIcon,
          isPinned: false,
        ),
      ),
    ),
  );
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(HistoryEntryAvatar),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  group('The disc is the nav chip\'s material on a circle', () {
    testWidgets('dark: three stops on one vertical axis', (tester) async {
      final d = await _pumpAvatar(tester);
      final gradient = d.gradient! as LinearGradient;

      expect(
        (gradient.colors.length, gradient.stops, gradient.begin),
        (3, const [0.0, WpAvatarTint.glossStop, 1.0], Alignment.topCenter),
        reason:
            'dark: the disc is not the nav chip\'s three-stop vertical '
            'shape. The gloss is a *stop*, not a second painted layer — a '
            'two-stop diagonal fill is the flat disc this replaced, and a '
            'highlight drawn on top of it would be the second element the '
            'chip\'s own gate forbids',
      );
    });

    testWidgets('dark: the gloss is a lit crown, not a shaded one', (
      tester,
    ) async {
      final d = await _pumpAvatar(tester);
      final gradient = d.gradient! as LinearGradient;

      expect(
        gradient.colors[0].a,
        greaterThan(gradient.colors[1].a),
        reason:
            'dark: the first stop is thinner than the fill under it, so '
            'the crown was not precomposited *over* the lit stop — the '
            'source-over of a highlight can only ever raise the alpha it '
            'lands on',
      );
    });

    testWidgets('dark: it is still a circle', (tester) async {
      final d = await _pumpAvatar(tester);
      expect(
        d.shape,
        BoxShape.circle,
        reason:
            'dark: the disc grew a rounded rectangle. Only the chip\'s '
            '*material* was ported; its geometry stays in the rail',
      );
      expect(
        d.borderRadius,
        isNull,
        reason:
            'dark: a borderRadius on a circle is dead weight at best and '
            'a Flutter assertion at worst',
      );
    });

    testWidgets('dark buys depth with light, not with a shadow', (
      tester,
    ) async {
      final d = await _pumpAvatar(tester);
      expect(
        d.boxShadow,
        isNull,
        reason:
            'the dark disc carries a shadow. *The Depth-Source Rule* gives '
            'dark exactly one source — the brightness delta between the disc '
            'and the plane under it — and a black shadow on a near-black '
            'ground is the mud the rule exists to keep out. This is the same '
            'fix the nav chip already carries (`isDark ? null : subtleLight`)',
      );
    });

    // Removed 2026-08-11 (dark-only build): `light keeps the offset shadow the
    // rule gives it`. It asserted the light disc carried `WpShadows.subtleLight`
    // — pearl has almost no room above the plane, so the offset shadow was
    // most of what made the disc an object there, the same argument
    // `navChipGradient`'s light twin made. Both the token and the theme it
    // served are gone; the dark case above is now the only case.

    testWidgets('every slot gets the same recipe, only a different hue', (
      tester,
    ) async {
      // The hue means nothing, so nothing about the material may vary with
      // it — a slot that got a thicker gloss or a different stop layout would
      // be the material quietly saying something the colour is not allowed to.
      final shapes = <(int, List<double>?, BoxShape, bool)>{};
      for (final slot in WpCategorySlot.categories) {
        final d = await _pumpAvatar(tester, slot: slot);
        final g = d.gradient! as LinearGradient;
        shapes.add((g.colors.length, g.stops, d.shape, d.boxShadow == null));
      }
      expect(
        shapes,
        hasLength(1),
        reason:
            'the eight slots do not all render the same material. The hue is '
            'decoration and means nothing; a per-slot difference in the '
            'material would be a claim the rotation is not allowed to make',
      );
    });
  });
}

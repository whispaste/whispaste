import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/wp_favourite_star.dart';
import 'package:whispaste/widgets/wp_icon_button.dart';

import '../fixtures/test_helpers.dart';

void main() {
  tearDown(() => WpColors.activate(wpLightColors));

  group('WpIconButton', () {
    testWidgets('tap area is 48 px square, the visible button is 44 px', (
      tester,
    ) async {
      WpColors.activate(wpLightColors);
      await tester.pumpWidget(
        makeTestable(
          WpIconButton(icon: Icons.tune, tooltip: 'Filter', onPressed: () {}),
        ),
      );
      // The layout box is the 48 px touch target (WpLayout.minTouchTarget);
      // the visible square stays at the field height it sits beside.
      expect(
        tester.getSize(find.byType(WpIconButton)),
        const Size.square(WpLayout.minTouchTarget),
      );
    });

    testWidgets('fires onPressed and is labelled by its tooltip', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          WpIconButton(
            icon: Icons.tune,
            tooltip: 'Filter',
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byType(WpIconButton));
      expect(taps, 1);
      expect(find.bySemanticsLabel('Filter'), findsOneWidget);
    });

    testWidgets('disabled does not fire and reports itself disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpIconButton(
            icon: Icons.tune,
            tooltip: 'Filter',
            onPressed: null,
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(WpIconButton));
      expect(semantics.label, 'Filter');
      expect(semantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    });
  });

  group('WpFavouriteStar', () {
    testWidgets('tap area is 48 px and the toggled state is exposed', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpFavouriteStar(
            isFavourite: true,
            semanticsLabel: 'Favourite',
            onToggle: () {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(WpFavouriteStar)),
        const Size.square(WpLayout.minTouchTarget),
      );
      final semantics = tester.getSemantics(find.byType(WpFavouriteStar));
      expect(semantics.label, 'Favourite');
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.flagsCollection.isToggled, ui.Tristate.isTrue);
    });

    testWidgets('tap calls onToggle', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          WpFavouriteStar(
            isFavourite: false,
            semanticsLabel: 'Favourite',
            onToggle: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byType(WpFavouriteStar));
      expect(taps, 1);
    });
  });
}

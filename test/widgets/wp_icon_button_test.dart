import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_favourite_star.dart';
import 'package:whispaste/widgets/wp_icon_button.dart';

import '../fixtures/test_helpers.dart';

void main() {
  tearDown(() => WpColors.activate(wpLightColors));

  group('WpIconButton', () {
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

    testWidgets('semanticsLabel replaces the tooltip as the spoken name', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpIconButton.ghost(
            icon: Icons.close,
            tooltip: 'Remove from log',
            semanticsLabel: 'Remove “teh → the” from log',
            onPressed: () {},
          ),
        ),
      );
      // The short tooltip stays out of the semantics tree, so a row's button
      // is announced once, with the name that says which row it belongs to.
      expect(
        find.bySemanticsLabel('Remove “teh → the” from log'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Remove from log'), findsNothing);
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
    testWidgets('the toggled state and the remove name are exposed', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        makeTestable(
          WpFavouriteStar(isFavourite: true, onToggle: () {}),
          locale: const Locale('en'),
        ),
      );
      final semantics = tester.getSemantics(find.byType(WpFavouriteStar));
      expect(semantics.label, l10n.historyUnpin);
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.flagsCollection.isToggled, ui.Tristate.isTrue);
    });

    testWidgets('tap calls onToggle', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          WpFavouriteStar(isFavourite: false, onToggle: () => taps++),
        ),
      );
      await tester.tap(find.byType(WpFavouriteStar));
      expect(taps, 1);
    });
  });
}

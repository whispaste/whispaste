/// Spec values for the WP-14 base components (design spec §3 and §4).
///
/// These pin the numbers the restyled components must paint with: token
/// values, the switch and checkbox themes, and that a button re-reads the
/// active colour set on every build instead of freezing the first one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../fixtures/test_helpers.dart';

void main() {
  tearDown(() => WpColors.activate(wpLightColors));

  group('spec tokens', () {
    test('field height is 44 px and the dropdown trigger 40 px', () {
      expect(WpShellTokens.fieldHeight, 44.0);
      expect(WpShellTokens.controlHeight, 40.0);
    });

    test('radius steps: checkbox 4, fields and buttons 8, controls 8', () {
      expect(WpRadiusTokens.xs, 4.0);
      expect(WpRadiusTokens.sm, 8.0);
      expect(WpRadiusTokens.control, 8.0);
    });
  });

  group('switch and checkbox themes', () {
    test(
      'switch track is accent when selected, its own off colour otherwise',
      () {
        for (final c in [wpLightColors, wpDarkColors, wpNavyColors]) {
          final theme = wpThemeFor(c);
          final track = theme.switchTheme.trackColor!;
          expect(track.resolve({WidgetState.selected}), c.accent);
          expect(track.resolve(<WidgetState>{}), c.switchTrackOff);
        }
      },
    );

    test('off track mirrors the switch-track-off token per surface', () {
      expect(wpLightColors.switchTrackOff, wpJournalPalette.switchTrackOff);
      expect(wpNavyColors.switchTrackOff, wpJournalPalette.switchTrackOff);
      expect(wpLightColors.selectionBorder, wpJournalPalette.selectionBorder);
      expect(wpDarkColors.selectionBorder, wpStagePalette.selectionBorder);
      expect(wpNavyColors.selectionBorder, wpJournalPalette.selectionBorder);
      expect(wpDarkColors.switchTrackOff, wpStagePalette.switchTrackOff);
    });

    test('switch thumb is white in every appearance', () {
      for (final c in [wpLightColors, wpDarkColors, wpNavyColors]) {
        final thumb = wpThemeFor(c).switchTheme.thumbColor!;
        expect(thumb.resolve({WidgetState.selected}), WpPalette.white);
      }
    });

    test('checkbox corners use the xs radius', () {
      final shape =
          wpThemeFor(wpLightColors).checkboxTheme.shape!
              as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(WpRadiusTokens.xs));
    });

    test('checkmark is white on light and navy on dark', () {
      expect(
        wpThemeFor(
          wpLightColors,
        ).checkboxTheme.checkColor!.resolve({WidgetState.selected}),
        WpPalette.white,
      );
      expect(
        wpThemeFor(
          wpDarkColors,
        ).checkboxTheme.checkColor!.resolve({WidgetState.selected}),
        wpDarkColors.onAction,
      );
    });
  });

  group('WpButton', () {
    testWidgets('primary label reads the active set on every build', (
      tester,
    ) async {
      WpColors.activate(wpLightColors);
      await tester.pumpWidget(
        makeTestable(
          WpButton(
            label: 'Save',
            variant: WpButtonVariant.primary,
            onPressed: () {},
          ),
        ),
      );
      expect(_labelColor(tester, 'Save'), wpLightColors.onAction);

      WpColors.activate(wpDarkColors);
      await tester.pumpWidget(
        makeTestable(
          WpButton(
            label: 'Save',
            variant: WpButtonVariant.primary,
            onPressed: () {},
          ),
        ),
      );
      expect(_labelColor(tester, 'Save'), wpDarkColors.onAction);
    });
  });
}

Color? _labelColor(WidgetTester tester, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
  return paragraph.text.style?.color;
}

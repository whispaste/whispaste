/// Tests for [WpGlassChrome] — the shared painted glass chrome surface.
///
/// AC1 — the chrome renders through a [CustomPaint] driven by its own painter
/// AC2 — the accent edge tint resolves to the theme-paired token per Brightness
/// AC3 — child content stays hit-testable through the chrome
/// AC4 — the chrome is static at rest (no ticker, no scheduled frame)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/wp_glass_chrome.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Finder _glassPaint() => find.descendant(
  of: find.byType(WpGlassChrome),
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is WpGlassChromePainter,
  ),
);

WpGlassChromePainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_glassPaint()).painter! as WpGlassChromePainter;

void main() {
  // -------------------------------------------------------------------------
  // AC1 — painted surface
  // -------------------------------------------------------------------------
  group('AC1 — painted surface', () {
    testWidgets('renders its child through a CustomPaint', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpGlassChrome(
            child: SizedBox(width: 240, height: 160, child: Text('Inhalt')),
          ),
        ),
      );

      expect(_glassPaint(), findsOneWidget);
      expect(find.text('Inhalt'), findsOneWidget);
    });

    testWidgets('defaults to a flat radius token and accepts an override', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const WpGlassChrome(child: SizedBox(width: 100))),
      );
      expect(_painter(tester).radius, WpRadius.lg);

      await tester.pumpWidget(
        makeTestable(
          const WpGlassChrome(radius: WpRadius.sm, child: SizedBox(width: 100)),
        ),
      );
      expect(_painter(tester).radius, WpRadius.sm);
    });
  });

  // -------------------------------------------------------------------------
  // AC2 — theme-paired accent tint
  // -------------------------------------------------------------------------
  group('AC2 — accent tint per Brightness', () {
    testWidgets('dark theme resolves the dark edge tokens', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpGlassChrome(child: SizedBox(width: 100)),
          brightness: Brightness.dark,
        ),
      );

      final colors = _painter(tester).colors;
      expect(colors.edgeTop, WpColorsDark.glassChromeEdgeTop);
      expect(colors.edgeBottom, WpColorsDark.glassChromeEdgeBottom);
      expect(colors.fillStart, WpColorsDark.glassChromeFillStart);
    });

    testWidgets('light theme resolves the light edge tokens', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpGlassChrome(child: SizedBox(width: 100)),
          brightness: Brightness.light,
        ),
      );

      final colors = _painter(tester).colors;
      expect(colors.edgeTop, WpColorsLight.glassChromeEdgeTop);
      expect(colors.edgeBottom, WpColorsLight.glassChromeEdgeBottom);
      expect(colors.fillStart, WpColorsLight.glassChromeFillStart);
    });

    test('the two themes are genuinely different tints', () {
      final dark = WpGlassChromeColors.of(Brightness.dark);
      final light = WpGlassChromeColors.of(Brightness.light);

      expect(dark.edgeTop, isNot(light.edgeTop));
      expect(dark.fillStart, isNot(light.fillStart));
    });

    test('the edge carries the brand accent, the fill stays neutral', () {
      for (final (colors, accent) in [
        (WpGlassChromeColors.of(Brightness.dark), WpColorsDark.accent),
        (WpGlassChromeColors.of(Brightness.light), WpColorsLight.accent),
      ]) {
        // Single-Accent-Rule: the accent hue lives on the rim only — the
        // surface fill must stay an achromatic (r == g == b) translucency.
        expect(colors.edgeTop.r, accent.r);
        expect(colors.edgeTop.g, accent.g);
        expect(colors.edgeTop.b, accent.b);
        expect(colors.fillStart.r, colors.fillStart.g);
        expect(colors.fillStart.g, colors.fillStart.b);
        expect(colors.fillEnd.r, colors.fillEnd.g);
        expect(colors.fillEnd.g, colors.fillEnd.b);
      }
    });
  });

  // -------------------------------------------------------------------------
  // AC3 — hit-testable child
  // -------------------------------------------------------------------------
  group('AC3 — hit-testable child', () {
    testWidgets('taps reach a button inside the chrome', (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        makeTestable(
          WpGlassChrome(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Drücken'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Drücken'));
      await tester.pump();

      expect(taps, 1);
    });
  });

  // -------------------------------------------------------------------------
  // AC4 — static at rest
  // -------------------------------------------------------------------------
  group('AC4 — static at rest', () {
    testWidgets('schedules no frames and drives no ticker', (tester) async {
      await tester.pumpWidget(
        makeTestable(const WpGlassChrome(child: SizedBox(width: 240))),
      );
      await tester.pump(WpMotion.dramatic);

      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}

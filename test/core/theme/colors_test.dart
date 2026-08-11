import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

void main() {
  group('WpColorsDark', () {
    test('background is a deep, tinted navy (opaque, dark)', () {
      expect(WpColorsDark.background.a, 1.0);
      // Dark, but *chromatic* dark. The blue channel deliberately no longer
      // fits under the old flat 0.15 ceiling: that ceiling described the
      // pre-Ticket-04 ground, and holding it would have re-imposed exactly the
      // near-neutral slate the "coloured glass" work exists to replace. What
      // has to stay true is that the ground reads as dark and as blue.
      expect(WpColorsDark.background.r, lessThan(0.15));
      expect(WpColorsDark.background.g, lessThan(0.15));
      expect(WpColorsDark.background.b, lessThan(0.35));
      expect(WpColorsDark.background.b, greaterThan(WpColorsDark.background.g));
      expect(WpColorsDark.background.g, greaterThan(WpColorsDark.background.r));
    });

    test('key surface colors are defined and non-null', () {
      expect(WpColorsDark.surface, isNotNull);
      expect(WpColorsDark.surfaceElevated, isNotNull);
      expect(WpColorsDark.surfaceVariant, isNotNull);
    });

    test('text hierarchy has three distinct levels', () {
      expect(WpColorsDark.textPrimary, isNot(WpColorsDark.textSecondary));
      expect(WpColorsDark.textSecondary, isNot(WpColorsDark.textMuted));
      expect(WpColorsDark.textPrimary, isNot(WpColorsDark.textMuted));
    });

    test('accent color is cyan', () {
      // ~~The generic interaction accent is a light violet.~~ *Retracted with
      // ADR 0013* — Ticket 04's violet is gone and the generic accent is back
      // in the brand's cyan, where it sat for the app's whole life before that
      // ticket. Cyan reads as green ≈ blue, both high, red trailing.
      expect(WpColorsDark.accent.g, greaterThan(0.7));
      expect(WpColorsDark.accent.b, greaterThan(0.7));
      expect(WpColorsDark.accent.g, greaterThan(WpColorsDark.accent.r));
    });

    test('the recording accent is the same family, separated by weight', () {
      expect(WpColorsDark.recordingAccent.g, greaterThan(0.7));
      expect(WpColorsDark.recordingAccent.b, greaterThan(0.7));

      // Still two tokens, and still never the same value — but the separation
      // is no longer a hue gap (ADR 0013 retracted that clause). They are one
      // cyan family that differs in *weight*; the measured gate for that lives
      // in `wcag_contrast_test.dart` ("Two accents, one family, separated by
      // weight"), which has the luminance and hue helpers.
      expect(WpColorsDark.recordingAccent, isNot(WpColorsDark.accent));
    });

    test('semantic colors (success, warning, error) are distinct', () {
      expect(WpColorsDark.success, isNot(WpColorsDark.warning));
      expect(WpColorsDark.warning, isNot(WpColorsDark.error));
      expect(WpColorsDark.success, isNot(WpColorsDark.error));
    });

    test('card material tokens exist and are translucent', () {
      expect(WpColorsDark.cardFill.a, lessThan(1.0));
      expect(WpColorsDark.cardFillElevated.a, lessThan(1.0));
      expect(WpColorsDark.cardEdgeHighlight.a, lessThan(1.0));
      // The elevated rung is the heavier one — that difference is the dark
      // theme's entire depth source.
      expect(
        WpColorsDark.cardFillElevated.a,
        greaterThan(WpColorsDark.cardFill.a),
      );
    });

    test('surfaceGradient returns a valid two-stop gradient', () {
      expect(WpColorsDark.surfaceGradient.colors.length, 2);
      expect(WpColorsDark.surfaceGradient, isA<LinearGradient>());
    });

    test('warmSurfaceGradient returns a valid three-stop gradient', () {
      expect(WpColorsDark.warmSurfaceGradient.colors.length, 3);
      expect(WpColorsDark.warmSurfaceGradient.stops, isNotNull);
      expect(WpColorsDark.warmSurfaceGradient.stops!.length, 3);
    });

    test('accentGradient and accentWarmGradient are defined', () {
      expect(WpColorsDark.accentGradient.colors, isNotEmpty);
      expect(WpColorsDark.accentWarmGradient.colors, isNotEmpty);
    });

    test('border colors have increasing opacity: subtle < default', () {
      expect(
        WpColorsDark.borderSubtle.a,
        lessThan(WpColorsDark.borderDefault.a),
      );
    });
  });

  // Removed 2026-08-11 (dark-only build): `group('WpColorsLight')` and
  // `group('Dark vs Light theme contrast')`.
  //
  // The first mirrored the dark group above assertion for assertion against
  // `WpColorsLight` — a background above 0.9 in every channel, a deep-violet
  // accent darkened for AA on pearl, the light card shadow. Its subject is
  // gone, so it has no tokens left to describe.
  //
  // The second existed only to prove the two palettes were actually two:
  // background, surface, textPrimary and accent each asserted `isNot` its
  // opposite number. With one palette those four assertions read
  // `expect(x, isNot(x))` and can never pass again — they are not coverage
  // that regressed, they are a question that stopped being askable.
  //
  // Nothing here is re-derived against dark: every property those groups
  // pinned on the dark palette is already pinned by the `WpColorsDark` group
  // above, and the contrast floors they gestured at live in
  // `test/core/theme/wcag_contrast_test.dart`, which measures them.
}

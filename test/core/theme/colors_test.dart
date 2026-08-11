import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

void main() {
  group('WpColorsDark', () {
    test('background is warm slate-blue (opaque, dark)', () {
      expect(WpColorsDark.background.a, 1.0);
      // Dark background should be dark (low RGB values)
      expect(WpColorsDark.background.r, lessThan(0.15));
      expect(WpColorsDark.background.g, lessThan(0.15));
      expect(WpColorsDark.background.b, lessThan(0.15));
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

    test('accent color is violet', () {
      // The generic interaction accent is a light violet: blue leads, red
      // follows, green trails. Cyan (green ≈ blue, both high) would fail here,
      // which is the point — cyan means `recordingAccent` now.
      expect(WpColorsDark.accent.b, greaterThan(WpColorsDark.accent.r));
      expect(WpColorsDark.accent.r, greaterThan(WpColorsDark.accent.g));
      expect(WpColorsDark.accent.b, greaterThan(0.7));
    });

    test('the recording accent is still cyan and no longer the accent', () {
      expect(WpColorsDark.recordingAccent.g, greaterThan(0.7));
      expect(WpColorsDark.recordingAccent.b, greaterThan(0.7));
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

  group('WpColorsLight', () {
    test('background is light (high RGB values)', () {
      expect(WpColorsLight.background.a, 1.0);
      expect(WpColorsLight.background.r, greaterThan(0.9));
      expect(WpColorsLight.background.g, greaterThan(0.9));
      expect(WpColorsLight.background.b, greaterThan(0.9));
    });

    test('key surface colors are defined and non-null', () {
      expect(WpColorsLight.surface, isNotNull);
      expect(WpColorsLight.surfaceElevated, isNotNull);
      expect(WpColorsLight.surfaceVariant, isNotNull);
    });

    test('text hierarchy has three distinct levels', () {
      expect(WpColorsLight.textPrimary, isNot(WpColorsLight.textSecondary));
      expect(WpColorsLight.textSecondary, isNot(WpColorsLight.textMuted));
      expect(WpColorsLight.textPrimary, isNot(WpColorsLight.textMuted));
    });

    test('accent color is a deep violet', () {
      // Same hue family as dark, darkened for AA on pearl.
      expect(WpColorsLight.accent.a, 1.0);
      expect(WpColorsLight.accent.b, greaterThan(WpColorsLight.accent.r));
      expect(WpColorsLight.accent.r, greaterThan(WpColorsLight.accent.g));
      expect(WpColorsLight.accent, isNot(WpColorsDark.accent));
    });

    test('semantic colors (success, warning, error) are distinct', () {
      expect(WpColorsLight.success, isNot(WpColorsLight.warning));
      expect(WpColorsLight.warning, isNot(WpColorsLight.error));
      expect(WpColorsLight.success, isNot(WpColorsLight.error));
    });

    test('card material tokens exist, including the light-only shadow', () {
      expect(WpColorsLight.cardFill.a, lessThan(1.0));
      expect(WpColorsLight.cardFillElevated.a, lessThan(1.0));
      expect(WpColorsLight.cardEdgeHighlight.a, lessThan(1.0));
      expect(WpColorsLight.cardShadowLight.a, lessThan(1.0));
    });

    test('surfaceGradient returns a valid two-stop gradient', () {
      expect(WpColorsLight.surfaceGradient.colors.length, 2);
    });

    test('warmSurfaceGradient returns a valid three-stop gradient', () {
      expect(WpColorsLight.warmSurfaceGradient.colors.length, 3);
      expect(WpColorsLight.warmSurfaceGradient.stops!.length, 3);
    });
  });

  group('Dark vs Light theme contrast', () {
    test('background colors differ between themes', () {
      expect(WpColorsDark.background, isNot(WpColorsLight.background));
    });

    test('surface colors differ between themes', () {
      expect(WpColorsDark.surface, isNot(WpColorsLight.surface));
    });

    test('text primary colors differ between themes', () {
      expect(WpColorsDark.textPrimary, isNot(WpColorsLight.textPrimary));
    });

    test('accent colors differ between dark and light', () {
      // Dark uses a light violet, light a deeper one at the same hue.
      expect(WpColorsDark.accent, isNot(WpColorsLight.accent));
    });
  });
}

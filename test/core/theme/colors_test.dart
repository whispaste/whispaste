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

    test('accent color is cyan', () {
      // Accent should be bright cyan — high green+blue, low red
      expect(WpColorsDark.accent.g, greaterThan(0.7));
      expect(WpColorsDark.accent.b, greaterThan(0.7));
    });

    test('semantic colors (success, warning, error) are distinct', () {
      expect(WpColorsDark.success, isNot(WpColorsDark.warning));
      expect(WpColorsDark.warning, isNot(WpColorsDark.error));
      expect(WpColorsDark.success, isNot(WpColorsDark.error));
    });

    test('glass tokens exist for frosted UI', () {
      expect(WpColorsDark.glassTint, isNotNull);
      expect(WpColorsDark.glassBorder, isNotNull);
      // Glass tint should be semi-transparent
      expect(WpColorsDark.glassTint.a, lessThan(1.0));
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

    test('accent color is teal', () {
      // Light accent is a deeper teal — lower RGB than dark accent
      expect(WpColorsLight.accent.a, 1.0);
      expect(WpColorsLight.accent, isNot(WpColorsDark.accent));
    });

    test('semantic colors (success, warning, error) are distinct', () {
      expect(WpColorsLight.success, isNot(WpColorsLight.warning));
      expect(WpColorsLight.warning, isNot(WpColorsLight.error));
      expect(WpColorsLight.success, isNot(WpColorsLight.error));
    });

    test('glass tokens exist for frosted UI', () {
      expect(WpColorsLight.glassTint, isNotNull);
      expect(WpColorsLight.glassBorder, isNotNull);
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
      // Dark uses bright cyan, light uses deeper teal
      expect(WpColorsDark.accent, isNot(WpColorsLight.accent));
    });
  });

  group('wpGlassDecoration', () {
    test('dark variant returns a BoxDecoration with glass tint', () {
      final decoration = wpGlassDecoration(isDark: true);
      expect(decoration, isA<BoxDecoration>());
      expect(decoration.color, WpColorsDark.glassTint);
      expect(decoration.border, isNotNull);
      expect(decoration.borderRadius, isNotNull);
    });

    test('light variant returns a BoxDecoration with glass tint', () {
      final decoration = wpGlassDecoration(isDark: false);
      expect(decoration, isA<BoxDecoration>());
      expect(decoration.color, WpColorsLight.glassTint);
    });

    test('respects custom borderRadius', () {
      final br = BorderRadius.circular(20);
      final decoration = wpGlassDecoration(isDark: true, borderRadius: br);
      expect(decoration.borderRadius, br);
    });

    test('default borderRadius is 10', () {
      final decoration = wpGlassDecoration(isDark: true);
      expect(decoration.borderRadius, BorderRadius.circular(10));
    });
  });
}

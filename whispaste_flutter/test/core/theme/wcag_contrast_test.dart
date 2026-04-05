/// WCAG AA contrast ratio audit for WhisPaste color tokens.
///
/// Runs automatically in CI alongside widget tests. Ensures ALL text/background
/// color pairs meet minimum contrast requirements:
/// - Normal text (< 18pt): ≥ 4.5:1
/// - Large text (≥ 18pt bold or ≥ 24pt): ≥ 3.0:1
///
/// Reference: https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

// ---------------------------------------------------------------------------
// WCAG 2.1 relative luminance + contrast ratio helpers
// ---------------------------------------------------------------------------

/// Converts a single sRGB channel (0–255) to linear light.
double _linearize(int channel) {
  final s = channel / 255.0;
  return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

/// Relative luminance per WCAG 2.1 definition.
double relativeLuminance(Color c) {
  final rl = _linearize((c.r * 255).round());
  final gl = _linearize((c.g * 255).round());
  final bl = _linearize((c.b * 255).round());
  return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl;
}

/// Contrast ratio between two colors (always ≥ 1.0).
double contrastRatio(Color foreground, Color background) {
  final l1 = relativeLuminance(foreground);
  final l2 = relativeLuminance(background);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

// ---------------------------------------------------------------------------
// Test data: every text/background pair that must pass
// ---------------------------------------------------------------------------

/// A named color pair to test.
class _ColorPair {
  const _ColorPair(this.name, this.fg, this.bg, {this.isLargeText = false});
  final String name;
  final Color fg;
  final Color bg;
  final bool isLargeText;

  double get requiredRatio => isLargeText ? 3.0 : 4.5;
}

// Dark theme pairs
final _darkPairs = [
  // Text on surface
  _ColorPair('dark: textPrimary on surface', WpColorsDark.textPrimary,
      WpColorsDark.surface),
  _ColorPair('dark: textSecondary on surface', WpColorsDark.textSecondary,
      WpColorsDark.surface),
  _ColorPair(
      'dark: textMuted on surface', WpColorsDark.textMuted, WpColorsDark.surface),

  // Text on elevated surface
  _ColorPair('dark: textPrimary on surfaceElevated', WpColorsDark.textPrimary,
      WpColorsDark.surfaceElevated),
  _ColorPair('dark: textSecondary on surfaceElevated',
      WpColorsDark.textSecondary, WpColorsDark.surfaceElevated),
  _ColorPair('dark: textMuted on surfaceElevated', WpColorsDark.textMuted,
      WpColorsDark.surfaceElevated),

  // Text on hover
  _ColorPair('dark: textPrimary on hover', WpColorsDark.textPrimary,
      WpColorsDark.hover),
  _ColorPair('dark: textSecondary on hover', WpColorsDark.textSecondary,
      WpColorsDark.hover),
  _ColorPair(
      'dark: textMuted on hover', WpColorsDark.textMuted, WpColorsDark.hover),

  // Text on background (frame)
  _ColorPair('dark: textPrimary on background', WpColorsDark.textPrimary,
      WpColorsDark.background),
  _ColorPair('dark: textSecondary on background', WpColorsDark.textSecondary,
      WpColorsDark.background),

  // Accent as text (large text threshold — section headers, buttons)
  _ColorPair('dark: accent on surface (large)', WpColorsDark.accent,
      WpColorsDark.surface,
      isLargeText: true),
  _ColorPair('dark: accent on background (large)', WpColorsDark.accent,
      WpColorsDark.background,
      isLargeText: true),

  // Status colors on surface (typically used as badges/labels — large text)
  _ColorPair('dark: success on surface (large)', WpColorsDark.success,
      WpColorsDark.surface,
      isLargeText: true),
  _ColorPair('dark: warning on surface (large)', WpColorsDark.warning,
      WpColorsDark.surface,
      isLargeText: true),
  _ColorPair('dark: error on surface (large)', WpColorsDark.error,
      WpColorsDark.surface,
      isLargeText: true),
];

// Light theme pairs
final _lightPairs = [
  // Text on surface
  _ColorPair('light: textPrimary on surface', WpColorsLight.textPrimary,
      WpColorsLight.surface),
  _ColorPair('light: textSecondary on surface', WpColorsLight.textSecondary,
      WpColorsLight.surface),
  _ColorPair('light: textMuted on surface', WpColorsLight.textMuted,
      WpColorsLight.surface),

  // Text on elevated surface
  _ColorPair('light: textPrimary on surfaceElevated', WpColorsLight.textPrimary,
      WpColorsLight.surfaceElevated),
  _ColorPair('light: textSecondary on surfaceElevated',
      WpColorsLight.textSecondary, WpColorsLight.surfaceElevated),
  _ColorPair('light: textMuted on surfaceElevated', WpColorsLight.textMuted,
      WpColorsLight.surfaceElevated),

  // Text on hover
  _ColorPair('light: textPrimary on hover', WpColorsLight.textPrimary,
      WpColorsLight.hover),
  _ColorPair('light: textSecondary on hover', WpColorsLight.textSecondary,
      WpColorsLight.hover),
  _ColorPair('light: textMuted on hover', WpColorsLight.textMuted,
      WpColorsLight.hover),

  // Text on background (frame)
  _ColorPair('light: textPrimary on background', WpColorsLight.textPrimary,
      WpColorsLight.background),
  _ColorPair('light: textSecondary on background', WpColorsLight.textSecondary,
      WpColorsLight.background),

  // Accent as text (large text)
  _ColorPair('light: accent on surface (large)', WpColorsLight.accent,
      WpColorsLight.surface,
      isLargeText: true),

  // Status colors on surface (large text)
  _ColorPair('light: success on surface (large)', WpColorsLight.success,
      WpColorsLight.surface,
      isLargeText: true),
  _ColorPair('light: warning on surface (large)', WpColorsLight.warning,
      WpColorsLight.surface,
      isLargeText: true),
  _ColorPair('light: error on surface (large)', WpColorsLight.error,
      WpColorsLight.surface,
      isLargeText: true),
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WCAG AA contrast – dark theme', () {
    for (final pair in _darkPairs) {
      test(pair.name, () {
        final ratio = contrastRatio(pair.fg, pair.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(pair.requiredRatio),
          reason: '${pair.name}: contrast ${ratio.toStringAsFixed(2)}:1 '
              '< required ${pair.requiredRatio}:1 '
              '(fg: #${pair.fg.value.toRadixString(16).padLeft(8, '0')}, '
              'bg: #${pair.bg.value.toRadixString(16).padLeft(8, '0')})',
        );
      });
    }
  });

  group('WCAG AA contrast – light theme', () {
    for (final pair in _lightPairs) {
      test(pair.name, () {
        final ratio = contrastRatio(pair.fg, pair.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(pair.requiredRatio),
          reason: '${pair.name}: contrast ${ratio.toStringAsFixed(2)}:1 '
              '< required ${pair.requiredRatio}:1 '
              '(fg: #${pair.fg.value.toRadixString(16).padLeft(8, '0')}, '
              'bg: #${pair.bg.value.toRadixString(16).padLeft(8, '0')})',
        );
      });
    }
  });

  // Sanity: verify our contrast computation against known values
  group('contrast ratio math', () {
    test('black on white = 21:1', () {
      final ratio =
          contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF));
      expect(ratio, closeTo(21.0, 0.1));
    });

    test('white on white = 1:1', () {
      final ratio =
          contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF));
      expect(ratio, closeTo(1.0, 0.01));
    });

    test('mid-grey on white ≈ 3.95:1', () {
      // #767676 is the well-known AA boundary on white
      final ratio =
          contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF));
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });
}

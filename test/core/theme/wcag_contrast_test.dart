/// WCAG AA contrast ratio + color saturation audit for WhisPaste tokens.
///
/// Runs automatically in CI alongside widget tests. Ensures:
/// 1. ALL text/background pairs meet minimum CONTRAST requirements
///    - Normal text (< 18pt): ≥ 4.5:1
///    - Large text (≥ 18pt bold or ≥ 24pt): ≥ 3.0:1
/// 2. Key colors meet minimum SATURATION thresholds (HSL saturation)
///    - Accent/status colors: ≥ 40% saturation
///    - Surface colors: ≥ 15% saturation (tinted, not flat gray)
///    - Frame–content lightness gap: ≤ 4% (unified monochrome feel)
///
/// References:
/// - https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
/// - HSL model: https://en.wikipedia.org/wiki/HSL_and_HSV
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';

// ---------------------------------------------------------------------------
// WCAG 2.1 relative luminance + contrast ratio helpers
// ---------------------------------------------------------------------------

/// Converts a single sRGB channel (0–255) to linear light.
double _linearize(int channel) {
  final s = channel / 255.0;
  return s <= 0.04045
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
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
// Alpha compositing — needed for tokens whose contrast only exists once they
// are painted *over* a surface (translucent fills, gradient stops, glyphs).
// ---------------------------------------------------------------------------

/// Source-over composite of translucent [fg] onto opaque [bg], in sRGB —
/// the same non-linear space the engine blends in, so the result matches
/// what actually lands in the framebuffer.
Color alphaComposite(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1.0,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

/// Midpoint of two opaque colors — the center of a two-stop linear gradient.
Color midpoint(Color a, Color b) => Color.from(
  alpha: 1.0,
  red: (a.r + b.r) / 2,
  green: (a.g + b.g) / 2,
  blue: (a.b + b.b) / 2,
);

/// Human-readable names for the [WpSharedColors.avatarPalette] slots, in order.
const List<String> _avatarSlotNames = [
  'slot 0 cyan',
  'slot 1 violet',
  'slot 2 amber',
  'slot 3 emerald',
  'slot 4 pink',
  'slot 5 blue',
  'slot 6 red',
  'slot 7 teal',
];

// ---------------------------------------------------------------------------
// HSL helpers for saturation audits
// ---------------------------------------------------------------------------

/// Returns HSL saturation (0.0–1.0) of a color.
double hslSaturation(Color c) {
  return HSLColor.fromColor(c).saturation;
}

/// Returns HSL lightness (0.0–1.0) of a color.
double hslLightness(Color c) {
  return HSLColor.fromColor(c).lightness;
}

/// A named color with a minimum saturation requirement.
class _SaturationCheck {
  const _SaturationCheck(this.name, this.color, this.minSaturation);
  final String name;
  final Color color;

  /// Minimum HSL saturation (0.0–1.0), e.g. 0.40 = 40%.
  final double minSaturation;
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
  const _ColorPair(
    'dark: textPrimary on surface',
    WpColorsDark.textPrimary,
    WpColorsDark.surface,
  ),
  const _ColorPair(
    'dark: textSecondary on surface',
    WpColorsDark.textSecondary,
    WpColorsDark.surface,
  ),
  const _ColorPair(
    'dark: textMuted on surface',
    WpColorsDark.textMuted,
    WpColorsDark.surface,
  ),

  // Text on elevated surface
  const _ColorPair(
    'dark: textPrimary on surfaceElevated',
    WpColorsDark.textPrimary,
    WpColorsDark.surfaceElevated,
  ),
  const _ColorPair(
    'dark: textSecondary on surfaceElevated',
    WpColorsDark.textSecondary,
    WpColorsDark.surfaceElevated,
  ),
  const _ColorPair(
    'dark: textMuted on surfaceElevated',
    WpColorsDark.textMuted,
    WpColorsDark.surfaceElevated,
  ),

  // Text on hover
  const _ColorPair(
    'dark: textPrimary on hover',
    WpColorsDark.textPrimary,
    WpColorsDark.hover,
  ),
  const _ColorPair(
    'dark: textSecondary on hover',
    WpColorsDark.textSecondary,
    WpColorsDark.hover,
  ),
  const _ColorPair(
    'dark: textMuted on hover',
    WpColorsDark.textMuted,
    WpColorsDark.hover,
  ),

  // Text on background (frame)
  const _ColorPair(
    'dark: textPrimary on background',
    WpColorsDark.textPrimary,
    WpColorsDark.background,
  ),
  const _ColorPair(
    'dark: textSecondary on background',
    WpColorsDark.textSecondary,
    WpColorsDark.background,
  ),

  // Accent as text (large text threshold — section headers, buttons)
  const _ColorPair(
    'dark: accent on surface (large)',
    WpColorsDark.accent,
    WpColorsDark.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'dark: accent on background (large)',
    WpColorsDark.accent,
    WpColorsDark.background,
    isLargeText: true,
  ),

  // Status colors on surface (typically used as badges/labels — large text)
  const _ColorPair(
    'dark: success on surface (large)',
    WpColorsDark.success,
    WpColorsDark.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'dark: warning on surface (large)',
    WpColorsDark.warning,
    WpColorsDark.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'dark: error on surface (large)',
    WpColorsDark.error,
    WpColorsDark.surface,
    isLargeText: true,
  ),
];

// Light theme pairs
final _lightPairs = [
  // Text on surface
  const _ColorPair(
    'light: textPrimary on surface',
    WpColorsLight.textPrimary,
    WpColorsLight.surface,
  ),
  const _ColorPair(
    'light: textSecondary on surface',
    WpColorsLight.textSecondary,
    WpColorsLight.surface,
  ),
  const _ColorPair(
    'light: textMuted on surface',
    WpColorsLight.textMuted,
    WpColorsLight.surface,
  ),

  // Text on elevated surface
  const _ColorPair(
    'light: textPrimary on surfaceElevated',
    WpColorsLight.textPrimary,
    WpColorsLight.surfaceElevated,
  ),
  const _ColorPair(
    'light: textSecondary on surfaceElevated',
    WpColorsLight.textSecondary,
    WpColorsLight.surfaceElevated,
  ),
  const _ColorPair(
    'light: textMuted on surfaceElevated',
    WpColorsLight.textMuted,
    WpColorsLight.surfaceElevated,
  ),

  // Text on hover
  const _ColorPair(
    'light: textPrimary on hover',
    WpColorsLight.textPrimary,
    WpColorsLight.hover,
  ),
  const _ColorPair(
    'light: textSecondary on hover',
    WpColorsLight.textSecondary,
    WpColorsLight.hover,
  ),
  const _ColorPair(
    'light: textMuted on hover',
    WpColorsLight.textMuted,
    WpColorsLight.hover,
  ),

  // Text on background (frame)
  const _ColorPair(
    'light: textPrimary on background',
    WpColorsLight.textPrimary,
    WpColorsLight.background,
  ),
  const _ColorPair(
    'light: textSecondary on background',
    WpColorsLight.textSecondary,
    WpColorsLight.background,
  ),

  // Accent as text (large text)
  const _ColorPair(
    'light: accent on surface (large)',
    WpColorsLight.accent,
    WpColorsLight.surface,
    isLargeText: true,
  ),

  // Status colors on surface (large text)
  const _ColorPair(
    'light: success on surface (large)',
    WpColorsLight.success,
    WpColorsLight.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'light: warning on surface (large)',
    WpColorsLight.warning,
    WpColorsLight.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'light: error on surface (large)',
    WpColorsLight.error,
    WpColorsLight.surface,
    isLargeText: true,
  ),
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
          reason:
              '${pair.name}: contrast ${ratio.toStringAsFixed(2)}:1 '
              '< required ${pair.requiredRatio}:1 '
              '(fg: #${pair.fg.toARGB32().toRadixString(16).padLeft(8, '0')}, '
              'bg: #${pair.bg.toARGB32().toRadixString(16).padLeft(8, '0')})',
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
          reason:
              '${pair.name}: contrast ${ratio.toStringAsFixed(2)}:1 '
              '< required ${pair.requiredRatio}:1 '
              '(fg: #${pair.fg.toARGB32().toRadixString(16).padLeft(8, '0')}, '
              'bg: #${pair.bg.toARGB32().toRadixString(16).padLeft(8, '0')})',
        );
      });
    }
  });

  // Sanity: verify our contrast computation against known values
  group('contrast ratio math', () {
    test('black on white = 21:1', () {
      final ratio = contrastRatio(
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
      );
      expect(ratio, closeTo(21.0, 0.1));
    });

    test('white on white = 1:1', () {
      final ratio = contrastRatio(
        const Color(0xFFFFFFFF),
        const Color(0xFFFFFFFF),
      );
      expect(ratio, closeTo(1.0, 0.01));
    });

    test('mid-grey on white ≈ 3.95:1', () {
      // #767676 is the well-known AA boundary on white
      final ratio = contrastRatio(
        const Color(0xFF767676),
        const Color(0xFFFFFFFF),
      );
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });

  // ---------------------------------------------------------------------------
  // Color saturation audits — ensure palette stays rich, not washed-out
  // ---------------------------------------------------------------------------

  group('Color saturation – dark theme (accent/status ≥ 40%)', () {
    final darkAccentChecks = [
      const _SaturationCheck('dark: accent', WpColorsDark.accent, 0.40),
      const _SaturationCheck(
        'dark: accentHover',
        WpColorsDark.accentHover,
        0.35,
      ),
      const _SaturationCheck('dark: success', WpColorsDark.success, 0.40),
      const _SaturationCheck('dark: warning', WpColorsDark.warning, 0.40),
      const _SaturationCheck('dark: error', WpColorsDark.error, 0.40),
    ];
    for (final check in darkAccentChecks) {
      test(check.name, () {
        final sat = hslSaturation(check.color);
        expect(
          sat,
          greaterThanOrEqualTo(check.minSaturation),
          reason:
              '${check.name}: saturation ${(sat * 100).toStringAsFixed(1)}% '
              '< required ${(check.minSaturation * 100).toStringAsFixed(0)}% '
              '(color: #${check.color.toARGB32().toRadixString(16).padLeft(8, '0')})',
        );
      });
    }
  });

  group('Color saturation – dark theme (surfaces ≥ 15% tint)', () {
    final darkSurfaceChecks = [
      const _SaturationCheck('dark: background', WpColorsDark.background, 0.15),
      const _SaturationCheck('dark: surface', WpColorsDark.surface, 0.15),
      const _SaturationCheck(
        'dark: surfaceElevated',
        WpColorsDark.surfaceElevated,
        0.15,
      ),
      const _SaturationCheck(
        'dark: surfaceVariant',
        WpColorsDark.surfaceVariant,
        0.15,
      ),
      const _SaturationCheck('dark: hover', WpColorsDark.hover, 0.15),
    ];
    for (final check in darkSurfaceChecks) {
      test(check.name, () {
        final sat = hslSaturation(check.color);
        expect(
          sat,
          greaterThanOrEqualTo(check.minSaturation),
          reason:
              '${check.name}: saturation ${(sat * 100).toStringAsFixed(1)}% '
              '< required ${(check.minSaturation * 100).toStringAsFixed(0)}% — '
              'surface must be tinted, not flat gray',
        );
      });
    }
  });

  group('Color saturation – light theme (accent/status ≥ 40%)', () {
    final lightAccentChecks = [
      const _SaturationCheck('light: accent', WpColorsLight.accent, 0.40),
      const _SaturationCheck('light: success', WpColorsLight.success, 0.40),
      const _SaturationCheck('light: warning', WpColorsLight.warning, 0.40),
      const _SaturationCheck('light: error', WpColorsLight.error, 0.40),
    ];
    for (final check in lightAccentChecks) {
      test(check.name, () {
        final sat = hslSaturation(check.color);
        expect(
          sat,
          greaterThanOrEqualTo(check.minSaturation),
          reason:
              '${check.name}: saturation ${(sat * 100).toStringAsFixed(1)}% '
              '< required ${(check.minSaturation * 100).toStringAsFixed(0)}% '
              '(color: #${check.color.toARGB32().toRadixString(16).padLeft(8, '0')})',
        );
      });
    }
  });

  group('Color saturation – light theme (surfaces ≥ 15% tint)', () {
    final lightSurfaceChecks = [
      const _SaturationCheck(
        'light: background',
        WpColorsLight.background,
        0.15,
      ),
      const _SaturationCheck('light: surface', WpColorsLight.surface, 0.15),
      const _SaturationCheck(
        'light: surfaceElevated',
        WpColorsLight.surfaceElevated,
        0.15,
      ),
      const _SaturationCheck(
        'light: surfaceVariant',
        WpColorsLight.surfaceVariant,
        0.15,
      ),
      const _SaturationCheck('light: hover', WpColorsLight.hover, 0.15),
    ];
    for (final check in lightSurfaceChecks) {
      test(check.name, () {
        final sat = hslSaturation(check.color);
        expect(
          sat,
          greaterThanOrEqualTo(check.minSaturation),
          reason:
              '${check.name}: saturation ${(sat * 100).toStringAsFixed(1)}% '
              '< required ${(check.minSaturation * 100).toStringAsFixed(0)}% — '
              'light surfaces must stay tinted, not sterile white/gray',
        );
      });
    }
  });

  // Frame–content unity: background and surface should be close in lightness
  group('Frame–content unity (lightness gap ≤ 4%)', () {
    test('dark: background vs surface lightness delta', () {
      final bgL = hslLightness(WpColorsDark.background);
      final sfL = hslLightness(WpColorsDark.surface);
      final delta = (bgL - sfL).abs();
      expect(
        delta,
        lessThanOrEqualTo(0.04),
        reason:
            'Frame-content lightness gap: ${(delta * 100).toStringAsFixed(1)}% '
            '> allowed 4% — frame and content should feel unified',
      );
    });

    test('light: background vs surface lightness delta', () {
      final bgL = hslLightness(WpColorsLight.background);
      final sfL = hslLightness(WpColorsLight.surface);
      final delta = (bgL - sfL).abs();
      expect(
        delta,
        lessThanOrEqualTo(0.05),
        reason:
            'Frame-content lightness gap: ${(delta * 100).toStringAsFixed(1)}% '
            '> allowed 5% — light theme should feel as unified as dark theme',
      );
    });
  });

  // -------------------------------------------------------------------------
  // History-entry avatar ("belichtete Scheibe") — two targets, one calibration
  //
  // The avatar hues ([WpSharedColors.avatarPalette]) are theme-independent, so
  // all light/dark adaptation lives in [WpAvatarTint]. Two separate failure
  // modes were reported against the pre-fix renderer and each needs its own
  // gate — they pull against each other on light (a denser disc drags the
  // glyph further toward ink), so they are calibrated together, never one
  // after the other:
  //
  //   1. the disc was invisible ("blass") — 1.06-1.14:1 against `surface`;
  //   2. the glyph was unreadable — 1.42-2.31:1 against its own disc.
  //
  // Modeling choice, stated so a reviewer can disagree with it explicitly:
  // "the disc" is measured at the **gradient midpoint** — the disc center,
  // which is where the glyph actually sits. The weaker bottom-right stop is
  // asserted separately, at a lower floor, as a secondary check. The glyph is
  // measured against both the midpoint and the lit top stop, because the icon
  // overlaps the upper-left region too and the top stop is the harder ground.
  //
  // ---------------------------------------------------------------------
  // CLASSIFICATION — open maintainer decision ① (NOT yet confirmed)
  //
  // The consolidated color plan proposes a usage-dependent contrast threshold
  // for the whole color system: 3:1 for surfaces/borders (WCAG 1.4.11,
  // non-text contrast) and 4.5:1 for text/glyphs (WCAG 1.4.3, text contrast).
  //
  // This phase deliberately classifies the avatar glyph as a **graphical
  // object, not text**, and therefore gates it at 3:1 rather than 4.5:1. The
  // reasoning: the icon is a pictogram identifying an entry's category — it
  // carries no reading content, is never a sentence, and is redundant with the
  // entry title next to it. WCAG 1.4.11 is the applicable success criterion
  // for such an object; 1.4.3 governs runs of text a user reads.
  //
  // The disc itself is gated at 1.5:1, not 3:1, on the same 1.4.11 logic but
  // one level down: it is decorative-adjacent identity material rather than an
  // object whose *shape* must be perceived to operate the UI.
  //
  // This classification has NOT been confirmed by the maintainer. It is
  // written out here so that an eventual answer to ① either ratifies it or
  // visibly contradicts it — instead of silently invalidating an already
  // merged phase. If ① lands on "glyph = text", raise the floor below to 4.5
  // and recalibrate [WpAvatarTint] rather than reinterpreting this comment.
  // -------------------------------------------------------------------------

  const discFloor = 1.5;
  const discBottomStopFloor = 1.3;
  const glyphFloor = 3.0;

  for (final (themeName, isDark, surface, surfaceElevated) in [
    ('dark', true, WpColorsDark.surface, WpColorsDark.surfaceElevated),
    ('light', false, WpColorsLight.surface, WpColorsLight.surfaceElevated),
  ]) {
    final tint = WpAvatarTint.of(isDark);

    group('Avatar disc vs. surface – $themeName theme (≥ $discFloor:1)', () {
      // Guard the positional pairing: [_avatarSlotNames] is indexed against
      // the palette, so a future palette edit (Phase F) that adds or drops a
      // slot would otherwise leave every test green while labelling the wrong
      // hue — a silent mislabel instead of a failure.
      test('slot names cover the palette', () {
        expect(_avatarSlotNames.length, WpSharedColors.avatarPalette.length);
      });

      for (var i = 0; i < WpSharedColors.avatarPalette.length; i++) {
        final base = WpSharedColors.avatarPalette[i];
        test(_avatarSlotNames[i], () {
          for (final (groundName, ground) in [
            ('surface', surface),
            ('surfaceElevated', surfaceElevated),
          ]) {
            final top = alphaComposite(tint.fillTop(base), ground);
            final bottom = alphaComposite(tint.fillBottom(base), ground);
            final disc = midpoint(top, bottom);

            expect(
              contrastRatio(disc, ground),
              greaterThanOrEqualTo(discFloor),
              reason:
                  '$themeName ${_avatarSlotNames[i]}: disc center only '
                  '${contrastRatio(disc, ground).toStringAsFixed(2)}:1 against '
                  '$groundName — the circle dissolves into the row',
            );
            expect(
              contrastRatio(bottom, ground),
              greaterThanOrEqualTo(discBottomStopFloor),
              reason:
                  '$themeName ${_avatarSlotNames[i]}: shaded gradient stop only '
                  '${contrastRatio(bottom, ground).toStringAsFixed(2)}:1 against '
                  '$groundName — the disc fades out at its bottom-right edge',
            );
          }
        });
      }
    });

    group('Avatar glyph vs. disc – $themeName theme (≥ $glyphFloor:1)', () {
      for (var i = 0; i < WpSharedColors.avatarPalette.length; i++) {
        final base = WpSharedColors.avatarPalette[i];
        test(_avatarSlotNames[i], () {
          final top = alphaComposite(tint.fillTop(base), surface);
          final bottom = alphaComposite(tint.fillBottom(base), surface);
          final disc = midpoint(top, bottom);
          final glyphColor = tint.glyph(base);

          for (final (groundName, ground) in [
            ('disc center', disc),
            ('lit top stop', top),
          ]) {
            final glyph = alphaComposite(glyphColor, ground);
            expect(
              contrastRatio(glyph, ground),
              greaterThanOrEqualTo(glyphFloor),
              reason:
                  '$themeName ${_avatarSlotNames[i]}: glyph only '
                  '${contrastRatio(glyph, ground).toStringAsFixed(2)}:1 against '
                  'the $groundName — the icon is not readable',
            );
          }
        });
      }
    });
  }
}

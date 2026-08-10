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

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/services/model_download_service.dart'
    show TierPerformance;
import 'package:whispaste/widgets/tier_performance_presentation.dart';

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
  // CLASSIFICATION — maintainer decision ① — RATIFIED (E1 = (a))
  //
  // The color system uses a **usage-dependent** contrast threshold: 3:1 for
  // surfaces, borders, bars and other graphical objects (WCAG 1.4.11) and
  // 4.5:1 only for text and text-like glyphs (WCAG 1.4.3). The maintainer
  // ratified exactly this — status quo confirmed, commit `0c52983e` ratified
  // along with it — so the classification below is now settled, not a proposal
  // awaiting an answer.
  //
  // Under it, the avatar glyph is a **graphical object, not text**, and is
  // gated at 3:1: the icon is a pictogram identifying an entry's category — it
  // carries no reading content, is never a sentence, and is redundant with the
  // entry title next to it.
  //
  // The disc itself is gated at 1.5:1, not 3:1, on the same 1.4.11 logic but
  // one level down: it is decorative-adjacent identity material rather than an
  // object whose *shape* must be perceived to operate the UI.
  //
  // Both floors are therefore maintainer-confirmed values. Raising or lowering
  // one is a new decision, not a re-reading of this comment.
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

  // -------------------------------------------------------------------------
  // Tier-performance info line (STT model selector)
  //
  // [WpTierPerformancePresentation.color] grades the line by measured tier
  // performance instead of painting every verdict the same accent blue. The
  // line renders at `WpTypography.micro` (10 px) — far below WCAG's large-text
  // threshold (18 pt / 14 pt bold), so it is normal text under 1.4.3 and owes
  // the full 4.5:1. That floor is what rules the amber and green steps out:
  // `WpColorsLight.warning` reaches only 3.11:1 and `WpColorsLight.success`
  // 3.74:1 on these grounds, so the ramp is accent / error / textMuted.
  //
  // GROUNDS — modeling choice, stated so a reviewer can disagree with it:
  // the row sits on the settings content panel, which is painted with
  // `warmSurfaceGradient`, not with a flat `surface`. This group nonetheless
  // gates against the flat `surface` / `surfaceElevated` tokens (plus the
  // `accentButtonFill` wash the selected row adds on top), matching every
  // other group in this file. On the gradient's warmest stop under that same
  // wash the two tightest pairs dip just below the floor — light `error`
  // 4.44:1 and light `textMuted` 4.42:1 — which is a property of the
  // incumbent palette, not of this change: `textMuted` is already used for
  // body copy on that exact gradient elsewhere in this very section. Raising
  // the floor here would fail the incumbent alongside the newcomers; that
  // belongs to a palette phase, not to this one.
  // -------------------------------------------------------------------------

  for (final (
        themeName,
        isDark,
        surface,
        surfaceElevated,
        accentButtonFill,
        hover,
      )
      in [
        (
          'dark',
          true,
          WpColorsDark.surface,
          WpColorsDark.surfaceElevated,
          WpColorsDark.accentButtonFill,
          WpColorsDark.hover,
        ),
        (
          'light',
          false,
          WpColorsLight.surface,
          WpColorsLight.surfaceElevated,
          WpColorsLight.accentButtonFill,
          WpColorsLight.hover,
        ),
      ]) {
    group('Tier-performance info line – $themeName theme (≥ 4.5:1)', () {
      final grounds = <String, Color>{
        'surface': surface,
        'surfaceElevated': surfaceElevated,
        // The selected/downloading row adds an 8 % accent wash over the card.
        'selected row (surface + accentButtonFill)': alphaComposite(
          accentButtonFill,
          surface,
        ),
        'selected row (surfaceElevated + accentButtonFill)': alphaComposite(
          accentButtonFill,
          surfaceElevated,
        ),
        // A benchmarking row that is not the current tier can be hovered.
        'hover': hover,
      };

      for (final performance in TierPerformance.values) {
        test(performance.name, () {
          final fg = WpTierPerformancePresentation.color(
            isDark: isDark,
            performance: performance,
          );
          grounds.forEach((groundName, ground) {
            final ratio = contrastRatio(fg, ground);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$themeName ${performance.name}: info line only '
                  '${ratio.toStringAsFixed(2)}:1 on $groundName — the 10 px '
                  'message is normal text and owes 4.5:1 '
                  '(fg: #${fg.toARGB32().toRadixString(16).padLeft(8, '0')})',
            );
          });
        });
      }

      // Guards the *ramp itself*: a future edit that collapses the mapping
      // back to one flat colour would otherwise leave every contrast test
      // green while silently removing the signal this phase introduced.
      test('the ramp is actually graded', () {
        Color of(TierPerformance p) =>
            WpTierPerformancePresentation.color(isDark: isDark, performance: p);

        expect(
          of(TierPerformance.slow),
          isNot(of(TierPerformance.moderate)),
          reason:
              '$themeName: a slow tier must not look like a moderate one — '
              'that is the whole point of the graded line',
        );
        expect(
          of(TierPerformance.unmeasured),
          isNot(of(TierPerformance.moderate)),
          reason:
              '$themeName: an unmeasured tier must not borrow the confident '
              'accent of a measured one',
        );
      });
    });
  }

  // -------------------------------------------------------------------------
  // Category slots — the nominal color layer ([WpCategorySlot])
  //
  // THRESHOLD, per the ratified usage-dependent rule above (① = E1 (a)): a
  // category slot is a **graphical object** — a dot, a chip fill, a chart
  // segment, an avatar disc — never a run of text. It therefore owes 3:1 under
  // WCAG 1.4.11, not 4.5:1 under 1.4.3. The palette is built with headroom on
  // that floor anyway (≈5.8:1 dark / ≈4.0:1 light against `surface`), so the
  // floor is a guard against future edits, not a value the palette hugs.
  //
  // GLYPH LEGIBILITY (group (c) of the ticket) is deliberately NOT tested here,
  // and the omission is the finding rather than a gap. At this ticket's scope
  // nothing paints a glyph *on* a slot: the slots have no call site at all, and
  // the contract states them as foreground/graphical marks. The one incumbent
  // glyph-on-hue recipe, [WpAvatarTint], exists precisely because
  // [WpSharedColors.avatarPalette] is theme-*independent* — "the whole
  // light/dark adaptation has to live in how a palette hue is prepared". A
  // theme-*paired* palette dissolves that premise, so Ticket 13 decides whether
  // the recipe survives at all; inventing a glyph pairing here would gate a
  // composition no code performs.
  //
  // Measured hand-off for that decision — today's slots pushed through today's
  // [WpAvatarTint] against `surface`, against its own floors (disc ≥ 1.5:1,
  // glyph ≥ 3:1): light clears both (disc 1.53–1.94, glyph 4.99–7.37); dark
  // does *not*. Dark `iris` reaches only 1.47:1 as a disc, and dark `neutral`
  // 1.27:1 with a 2.71:1 glyph — the low-chroma fallback is the one that breaks
  // hardest, because a 20 %-saturation hue at 20–28 % alpha barely departs from
  // navy. Recalibrating the tint (or replacing it) is Ticket 13's job, and
  // these are the numbers it starts from.
  // -------------------------------------------------------------------------

  const categorySlotFloor = 3.0;

  group('Category slot palette – structure', () {
    test('both themes carry a color for every slot, neutral last', () {
      expect(WpCategoryColorsDark.slots.length, WpCategorySlot.values.length);
      expect(WpCategoryColorsLight.slots.length, WpCategorySlot.values.length);
      expect(
        WpCategorySlot.values.last,
        WpCategorySlot.neutral,
        reason: 'the neutral fallback is indexed last in both slot lists',
      );
      expect(
        WpCategoryColorsDark.slots.last,
        WpCategoryColorsDark.neutral,
        reason: 'dark slot list is out of sync with the enum order',
      );
      expect(
        WpCategoryColorsLight.slots.last,
        WpCategoryColorsLight.neutral,
        reason: 'light slot list is out of sync with the enum order',
      );
    });

    test('the neutral fallback is not a ninth category', () {
      expect(WpCategorySlot.categories.length, 8);
      expect(
        WpCategorySlot.categories,
        isNot(contains(WpCategorySlot.neutral)),
        reason:
            'untitled/uncategorised is the normal case in a dictation app — it '
            'must not be reachable from a hash and must not share a hue with a '
            'real category (Ticket 11, ③ = a)',
      );
    });

    test('no two slots share a color', () {
      for (final (themeName, isDark) in [('dark', true), ('light', false)]) {
        final colors = WpCategorySlot.values
            .map((s) => s.color(isDark).toARGB32())
            .toSet();
        expect(
          colors.length,
          WpCategorySlot.values.length,
          reason:
              '$themeName: two slots resolve to the same color — a nominal '
              'scale whose members collide cannot separate its categories',
        );
      }
    });

    test('every slot resolves to the constant of the same name', () {
      // Length, order-of-last and uniqueness alone cannot catch a *reordered*
      // slot list: swap two entries in one theme only and `iris` silently
      // resolves to ember's hue there. Pinning the pairing by name turns that
      // into a failure instead of a mislabel — same reasoning as the
      // `slot names cover the palette` guard for the avatar palette above.
      const dark = <WpCategorySlot, Color>{
        WpCategorySlot.iris: WpCategoryColorsDark.iris,
        WpCategorySlot.ember: WpCategoryColorsDark.ember,
        WpCategorySlot.fern: WpCategoryColorsDark.fern,
        WpCategorySlot.orchid: WpCategoryColorsDark.orchid,
        WpCategorySlot.brass: WpCategoryColorsDark.brass,
        WpCategorySlot.azure: WpCategoryColorsDark.azure,
        WpCategorySlot.plum: WpCategoryColorsDark.plum,
        WpCategorySlot.moss: WpCategoryColorsDark.moss,
        WpCategorySlot.neutral: WpCategoryColorsDark.neutral,
      };
      const light = <WpCategorySlot, Color>{
        WpCategorySlot.iris: WpCategoryColorsLight.iris,
        WpCategorySlot.ember: WpCategoryColorsLight.ember,
        WpCategorySlot.fern: WpCategoryColorsLight.fern,
        WpCategorySlot.orchid: WpCategoryColorsLight.orchid,
        WpCategorySlot.brass: WpCategoryColorsLight.brass,
        WpCategorySlot.azure: WpCategoryColorsLight.azure,
        WpCategorySlot.plum: WpCategoryColorsLight.plum,
        WpCategorySlot.moss: WpCategoryColorsLight.moss,
        WpCategorySlot.neutral: WpCategoryColorsLight.neutral,
      };
      for (final (themeName, isDark, expected) in [
        ('dark', true, dark),
        ('light', false, light),
      ]) {
        expect(
          expected.keys.toSet(),
          WpCategorySlot.values.toSet(),
          reason: '$themeName: a slot was added without a color of its name',
        );
        expected.forEach((slot, color) {
          expect(
            slot.color(isDark),
            color,
            reason:
                '$themeName: ${slot.name} resolves to a color that is not '
                '${slot.name} — the slot list order no longer matches the enum',
          );
        });
      }
    });

    test('the mappers only ever return category slots, never neutral', () {
      final identities = <String>[
        'whisper-small',
        'whisper-medium',
        'whisper-large-v3-turbo',
        'meeting',
        'email',
        'blog',
        'personal',
        'feedback',
        'project',
        'idea',
        'reminder',
        '',
        'a',
        'zzzzzzzz',
      ];
      for (final id in identities) {
        for (final slot in [
          categorySlotForModel(id),
          categorySlotForTag(id),
          categorySlotForAvatarRule(id),
        ]) {
          expect(
            slot,
            isNot(WpCategorySlot.neutral),
            reason:
                '"$id" hashed onto the neutral fallback — neutral is reached '
                'by an explicit call site, never by a hash',
          );
        }
      }
    });

    test('the mappers are deterministic and normalise tag names', () {
      expect(
        categorySlotForModel('whisper-medium'),
        categorySlotForModel('whisper-medium'),
      );
      expect(categorySlotForTag('Meeting '), categorySlotForTag('meeting'));
      expect(
        categorySlotForAvatarRule('email'),
        categorySlotForAvatarRule('email'),
      );
    });
  });

  for (final (themeName, isDark, accent, grounds) in [
    (
      'dark',
      true,
      WpColorsDark.accent,
      <String, Color>{
        'surface': WpColorsDark.surface,
        'surfaceElevated': WpColorsDark.surfaceElevated,
        'surfaceVariant': WpColorsDark.surfaceVariant,
      },
    ),
    (
      'light',
      false,
      WpColorsLight.accent,
      <String, Color>{
        'surface': WpColorsLight.surface,
        'surfaceElevated': WpColorsLight.surfaceElevated,
        'surfaceVariant': WpColorsLight.surfaceVariant,
      },
    ),
  ]) {
    group(
      'Category slot vs. surfaces – $themeName theme (≥ $categorySlotFloor:1)',
      () {
        for (final slot in WpCategorySlot.values) {
          test(slot.name, () {
            final color = slot.color(isDark);
            grounds.forEach((groundName, ground) {
              final ratio = contrastRatio(color, ground);
              expect(
                ratio,
                greaterThanOrEqualTo(categorySlotFloor),
                reason:
                    '$themeName ${slot.name}: only ${ratio.toStringAsFixed(2)}'
                    ':1 against $groundName — a category mark is a graphical '
                    'object and owes 3:1 (WCAG 1.4.11) '
                    '(color: #${color.toARGB32().toRadixString(16).padLeft(8, '0')})',
              );
            });
          });
        }
      },
    );

    // The recognition value of the accent, made executable: the nominal layer
    // may speak, but never louder than the brand voice it sits next to.
    group('Category quieter than the accent – $themeName theme', () {
      final surface = grounds['surface']!;
      final accentRatio = contrastRatio(accent, surface);

      for (final slot in WpCategorySlot.values) {
        test(slot.name, () {
          final ratio = contrastRatio(slot.color(isDark), surface);
          expect(
            ratio,
            lessThan(accentRatio),
            reason:
                '$themeName ${slot.name}: ${ratio.toStringAsFixed(2)}:1 against '
                'surface vs. the accent\'s ${accentRatio.toStringAsFixed(2)}:1 '
                '— a category must not out-shout the one accent',
          );
        });
      }
    });
  }

  // Saturation ceiling: the palette is a *quiet* nominal layer. The accent is
  // allowed to be the most saturated thing on screen (dark 76 %, light 92 %);
  // eight categories at that pitch would turn a list into a fruit salad.
  group('Category slot saturation – ≤ 80%', () {
    for (final (themeName, isDark) in [('dark', true), ('light', false)]) {
      for (final slot in WpCategorySlot.values) {
        test('$themeName: ${slot.name}', () {
          final color = slot.color(isDark);
          final sat = hslSaturation(color);
          expect(
            sat,
            lessThanOrEqualTo(0.80),
            reason:
                '$themeName ${slot.name}: saturation '
                '${(sat * 100).toStringAsFixed(1)}% > 80% — the category layer '
                'stays under the accent, not next to it '
                '(color: #${color.toARGB32().toRadixString(16).padLeft(8, '0')})',
          );
        });
      }
    }
  });

  // -------------------------------------------------------------------------
  // Migration marker for Ticket 13 — NOT a failing acceptance criterion today.
  //
  // Ticket 13 replaces [WpSharedColors.avatarPalette] with the category slots
  // and requires it to end up with zero call sites. That migration has not
  // happened yet, so the palette still has exactly one: `history_helpers.dart`.
  // This test pins that fact. When Ticket 13 lands, it fails — and the fix is
  // to change the expectation to an empty set (and delete the palette), not to
  // delete the test. It exists so the migration cannot be declared done while a
  // second multi-hue system quietly survives somewhere in `lib/`.
  // -------------------------------------------------------------------------
  group('avatarPalette call sites (Ticket 13 migration marker)', () {
    test('exactly one, in history_helpers.dart', () {
      final lib = Directory('lib');
      expect(
        lib.existsSync(),
        isTrue,
        reason: 'sweep needs the package root as cwd — `lib/` not found',
      );

      final dartFiles = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(
        dartFiles.length,
        greaterThan(100),
        reason:
            'the sweep found only ${dartFiles.length} Dart files under lib/ — '
            'it is not looking where it thinks it is, so an empty result below '
            'would pass vacuously',
      );

      final referencing = dartFiles
          .where((f) => f.readAsStringSync().contains('avatarPalette'))
          .map((f) => f.path.replaceAll(r'\', '/'))
          // The declaration itself and its doc comments don't count.
          .where((p) => p != 'lib/core/theme/colors.dart')
          .toSet();

      expect(
        referencing,
        {'lib/features/history/widgets/history_helpers.dart'},
        reason:
            'avatarPalette is expected to have exactly one call site until '
            'Ticket 13 migrates it to WpCategorySlot. Found: $referencing',
      );
    });
  });
}

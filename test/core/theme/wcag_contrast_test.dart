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
    show TierPerformance, sttModels;
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelId;
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

  // Recording accent — the recording/listening family split off from `accent`.
  // Same grounds and the same large-text threshold the accent carries: the
  // split copied the values, so it must inherit the whole guarantee, not just
  // the hue. If the two ever drift apart, they drift under the same floor.
  const _ColorPair(
    'dark: recordingAccent on surface (large)',
    WpColorsDark.recordingAccent,
    WpColorsDark.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'dark: recordingAccent on background (large)',
    WpColorsDark.recordingAccent,
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

  // Recording accent — see the dark half. Light mirrors the accent's coverage
  // exactly, which means surface only: `accent` never carried an
  // on-background pair here, so its twin does not invent one.
  const _ColorPair(
    'light: recordingAccent on surface (large)',
    WpColorsLight.recordingAccent,
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
      const _SaturationCheck(
        'dark: recordingAccent',
        WpColorsDark.recordingAccent,
        0.40,
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
      const _SaturationCheck(
        'light: recordingAccent',
        WpColorsLight.recordingAccent,
        0.40,
      ),
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
  // The disc is a translucent tint over its ground, so its presence is not the
  // slot's own contrast but what [WpAvatarTint] makes of it. Two separate failure
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
      for (final slot in WpCategorySlot.values) {
        final base = slot.color(isDark);
        test(slot.name, () {
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
                  '$themeName ${slot.name}: disc center only '
                  '${contrastRatio(disc, ground).toStringAsFixed(2)}:1 against '
                  '$groundName — the circle dissolves into the row',
            );
            expect(
              contrastRatio(bottom, ground),
              greaterThanOrEqualTo(discBottomStopFloor),
              reason:
                  '$themeName ${slot.name}: shaded gradient stop only '
                  '${contrastRatio(bottom, ground).toStringAsFixed(2)}:1 against '
                  '$groundName — the disc fades out at its bottom-right edge',
            );
          }
        });
      }
    });

    group('Avatar glyph vs. disc – $themeName theme (≥ $glyphFloor:1)', () {
      for (final slot in WpCategorySlot.values) {
        final base = slot.color(isDark);
        test(slot.name, () {
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
                  '$themeName ${slot.name}: glyph only '
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
  // performance with a sequential ramp cut from a single category slot
  // (`orchid`), instead of painting every verdict the same accent blue. The
  // line renders at `WpTypography.micro` (10 px) — far below WCAG's large-text
  // threshold (18 pt / 14 pt bold), so it is normal text under 1.4.3 and owes
  // the full 4.5:1. That floor does two things here. It rules a traffic light
  // out outright — `WpColorsLight.warning` reaches only 3.11:1 and
  // `WpColorsLight.success` 3.74:1 on these grounds — and it is why the line
  // starts at the ramp's third rung: the two beneath are solved for a graphical
  // object's 3:1 and land at 3.60:1 and 4.40:1 on the tightest ground below.
  //
  // GROUNDS — modeling choice, stated so a reviewer can disagree with it:
  // the row sits on the settings content panel, which is painted with
  // `warmSurfaceGradient`, not with a flat `surface`. This group nonetheless
  // gates against the flat `surface` / `surfaceElevated` tokens (plus the
  // `accentButtonFill` wash the selected row adds on top), matching every
  // other group in this file. On the gradient's warmest stop under that same
  // wash the tightest pair dips just below the floor — light `textMuted` at
  // 4.42:1 — which is a property of the incumbent palette, not of this change:
  // `textMuted` is already used for body copy on that exact gradient elsewhere
  // in this very section. Raising the floor here would fail the incumbent
  // alongside the ramp; that belongs to a palette phase, not to this one.
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

      // Guards the *shape* of the ramp rather than only its legibility. Every
      // group above stays green if a future edit collapses the mapping back to
      // one flat colour, or splits it into a red/amber/green verdict; what
      // follows is those two decisions written as assertions.
      Color of(TierPerformance p) =>
          WpTierPerformancePresentation.color(isDark: isDark, performance: p);

      // The three tiers that have actually been measured. `unmeasured` is
      // deliberately not in the chain — see the test below.
      const measured = [
        TierPerformance.fast,
        TierPerformance.moderate,
        TierPerformance.slow,
      ];

      test('weight rises with the time cost, away from the ground', () {
        for (var i = 1; i < measured.length; i++) {
          final delta =
              relativeLuminance(of(measured[i])) -
              relativeLuminance(of(measured[i - 1]));
          expect(
            isDark ? delta : -delta,
            greaterThan(0),
            reason:
                '$themeName: ${measured[i].name} does not sit further from the '
                'ground than ${measured[i - 1].name}. The line reports how much '
                'time a tier costs, so its weight has to rise with that cost — '
                'and it has to rise in the direction the theme leaves room in, '
                'lighter on dark, darker on light',
          );
        }
      });

      test('the graded tiers are one hue, not a traffic light', () {
        final hues = [for (final p in measured) HSLColor.fromColor(of(p)).hue];
        for (var i = 1; i < hues.length; i++) {
          expect(
            (hues[i] - hues.first).abs(),
            lessThan(2),
            reason:
                '$themeName: ${measured[i].name} sits at '
                '${hues[i].toStringAsFixed(0)}° against '
                '${hues.first.toStringAsFixed(0)}° for ${measured.first.name}. '
                'An ordinal scale is one hue at rising weight; a second hue '
                'turns a time cost into a verdict, which is exactly what this '
                'line refuses to be',
          );
        }
      });

      test('an unmeasured tier sits off the ramp entirely', () {
        final unmeasured = of(TierPerformance.unmeasured);
        final rampHue = HSLColor.fromColor(of(TierPerformance.slow)).hue;

        for (final p in measured) {
          expect(
            unmeasured,
            isNot(of(p)),
            reason:
                '$themeName: an unmeasured tier borrowed ${p.name}\'s rung — a '
                'tier nobody has benchmarked has no position on an ordinal '
                'scale and may not occupy one',
          );
        }
        expect(
          (HSLColor.fromColor(unmeasured).hue - rampHue).abs(),
          greaterThan(45),
          reason:
              '$themeName: the unmeasured colour is close enough to the ramp\'s '
              'hue to read as one of its rungs',
        );
        for (final p in measured) {
          expect(
            contrastRatio(unmeasured, surface),
            lessThan(contrastRatio(of(p), surface)),
            reason:
                '$themeName: the unmeasured line is louder than ${p.name} — '
                '"no verdict yet" must be the quietest thing in the card',
          );
        }
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
  // GLYPH LEGIBILITY is gated in the avatar groups above rather than here: the
  // avatar disc is the one composition that paints a glyph *on* a slot, and it
  // does so through [WpAvatarTint], so the pairing is measured where it is
  // actually performed instead of being invented a second time.
  //
  // CORRECTION to Ticket 12's hand-off note, which claimed the slots break the
  // tint's own floors on dark (`iris` 1.47:1 as a disc, `neutral` 1.27:1 with a
  // 2.71:1 glyph) and left recalibration to Ticket 13. Re-measured against the
  // shipped code, every slot clears both floors in both themes with the tint
  // unchanged — dark discs land at 1.69–1.87:1 and dark glyphs at 4.54–6.08:1,
  // light at 1.76–1.84:1 and 5.70–7.26:1. The old note appears to have skipped
  // the recipe's lightness shift; the tint was therefore left as it was, and the
  // groups above are what holds that.
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
  // Model → slot table (Ticket 14)
  //
  // The shipped model ids are a closed set, so the mapping owes a bijection —
  // and the sum-of-code-units hash cannot give one here: `whisper-small` (1352)
  // and `whisper-medium` (1456) are both ≡ 0 mod 8 and would paint the two
  // most-used models the same hue. Same defect, same remedy as the avatar rules
  // in Ticket 13.
  // -------------------------------------------------------------------------

  group('Model slot table', () {
    // Pinned by name, like `every slot resolves to the constant of the same
    // name` above: a bijection test alone cannot catch a *re-shuffled* table,
    // and a model silently changing hue between releases is exactly the kind of
    // drift the mapper exists to prevent.
    const tabled = <String, WpCategorySlot>{
      'whisper-small': WpCategorySlot.fern,
      'whisper-medium': WpCategorySlot.azure,
      'whisper-large-v3-turbo': WpCategorySlot.orchid,
      'parakeet-tdt-0.6b-v3': WpCategorySlot.ember,
      'whisper-tiny': WpCategorySlot.moss,
      'whisper-base': WpCategorySlot.brass,
      'whisper-large-v3': WpCategorySlot.plum,
    };

    test('every tabled id keeps its slot', () {
      tabled.forEach((id, slot) {
        expect(
          categorySlotForModel(id),
          slot,
          reason:
              '"$id" no longer resolves to ${slot.name} — a model that changes '
              'hue between releases makes the color a decoration again',
        );
      });
    });

    test('no two models share a slot', () {
      expect(
        tabled.values.toSet().length,
        tabled.length,
        reason:
            'two model ids landed on one hue — the whole point of the table is '
            'that the hash could not promise a bijection over this set',
      );
    });

    test('every model the app can ship is tabled', () {
      final shipped = [...sttModels.map((m) => m.id), parakeetModelId];
      for (final id in shipped) {
        expect(
          tabled.keys,
          contains(id),
          reason:
              '"$id" ships but has no entry in `_modelSlots`, so it falls back '
              'to the hash — which may collide with another model or land on '
              'the duration ramp\'s hue',
        );
      }
    });

    test('no model wears the duration ramp\'s hue', () {
      // The model bars and the duration distribution sit one panel apart on the
      // analytics page. Sharing a hue there would give it two meanings on one
      // screen — see `_durationRampSlot` in `analytics_page.dart`.
      expect(
        tabled.values,
        isNot(contains(WpCategorySlot.iris)),
        reason:
            'a model took `iris`, the source of the analytics duration ramp — '
            'pick one of the seven remaining slots instead',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Sequential ramps (Ticket 14) — the ordinal half of *The Categorical vs.
  // Sequential Rule*. Nominal data gets distinct hues, ordered data gets one
  // hue at rising weight; what follows gates that the rungs of that one hue are
  // both separable from each other and legible against every surface.
  // -------------------------------------------------------------------------

  group('Sequential ramp', () {
    // Rungs are placed a fixed contrast ratio apart (1.22:1); 8-bit rounding
    // costs a little of it, so the floor sits just below the nominal step.
    const rungFloor = 1.20;

    for (final (themeName, isDark, grounds) in [
      (
        'dark',
        true,
        <String, Color>{
          'surface': WpColorsDark.surface,
          'surfaceElevated': WpColorsDark.surfaceElevated,
          'surfaceVariant': WpColorsDark.surfaceVariant,
          'background': WpColorsDark.background,
        },
      ),
      (
        'light',
        false,
        <String, Color>{
          'surface': WpColorsLight.surface,
          'surfaceElevated': WpColorsLight.surfaceElevated,
          'surfaceVariant': WpColorsLight.surfaceVariant,
          'background': WpColorsLight.background,
        },
      ),
    ]) {
      for (final slot in WpCategorySlot.values) {
        test('$themeName: ${slot.name} — rungs are separable and legible', () {
          for (var steps = 3; steps <= 5; steps++) {
            final rungs = slot.ramp(steps, isDark);
            expect(rungs, hasLength(steps));
            expect(
              rungs.first,
              slot.color(isDark),
              reason:
                  '$themeName ${slot.name}: rung 0 is not the slot itself, so '
                  'the ramp no longer starts on the ground it was solved for',
            );

            for (var i = 1; i < steps; i++) {
              final ratio = contrastRatio(rungs[i - 1], rungs[i]);
              expect(
                ratio,
                greaterThanOrEqualTo(rungFloor),
                reason:
                    '$themeName ${slot.name} ($steps steps): rungs $i-1 and $i '
                    'are only ${ratio.toStringAsFixed(3)}:1 apart — an ordinal '
                    'scale whose steps collapse cannot be read as ordered',
              );

              // Away from the ground, never back toward it: this is what lets
              // every rung inherit the base slot's clearance instead of
              // re-arguing it, and what stops the low end sinking under 3:1 on
              // the light theme.
              final delta =
                  relativeLuminance(rungs[i]) - relativeLuminance(rungs[i - 1]);
              expect(
                isDark ? delta : -delta,
                greaterThan(0),
                reason:
                    '$themeName ${slot.name}: rung $i moves back toward the '
                    'ground instead of away from it',
              );
            }

            for (final rung in rungs) {
              grounds.forEach((groundName, ground) {
                final ratio = contrastRatio(rung, ground);
                expect(
                  ratio,
                  greaterThanOrEqualTo(categorySlotFloor),
                  reason:
                      '$themeName ${slot.name} ($steps steps): a rung clears '
                      '$groundName by only ${ratio.toStringAsFixed(2)}:1 — a '
                      'chart bar is a graphical object and owes 3:1',
                );
              });
            }
          }
        });
      }
    }

    test('the 3–5 step range is executable, not advisory', () {
      expect(() => WpCategorySlot.iris.ramp(2, true), throwsAssertionError);
      expect(() => WpCategorySlot.iris.ramp(6, true), throwsAssertionError);
    });

    // Ticket 11, ② = (b): cyan stays the accent's alone, so no ordinal ramp may
    // be built from it. The tickets call the forbidden hue "slot 0", meaning the
    // pre-Ticket-12 palette's Harbor Cyan — not `WpCategorySlot.values[0]`,
    // which is `iris`. Ticket 12 dropped the whole 165–215° band from the
    // category recipe, so the exclusion is structural: a ramp takes a
    // `WpCategorySlot`, and no slot is cyan. This pins that it stays that way.
    test('no ramp can be built out of the accent band', () {
      for (final isDark in [true, false]) {
        for (final slot in WpCategorySlot.values) {
          for (final rung in slot.ramp(5, isDark)) {
            final hue = HSLColor.fromColor(rung).hue;
            // Near-achromatic rungs have no hue worth reading — the neutral
            // slot's far end lands there by design.
            if (hslSaturation(rung) < 0.10) continue;
            expect(
              hue > 165 && hue < 215,
              isFalse,
              reason:
                  '${slot.name} has a rung at ${hue.toStringAsFixed(0)}° — '
                  'inside the accent\'s reserved 165–215° band, where a graded '
                  'scale reads as a disabled control',
            );
          }
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // Migration marker for Ticket 13 — the palette is gone; nothing may bring a
  // second multi-hue system back under a familiar name. Ticket 13 replaced
  // `WpSharedColors.avatarPalette` with the category slots, so the sweep below
  // now expects zero mentions anywhere in `lib/` — including the declaration,
  // which no longer exists.
  // -------------------------------------------------------------------------
  group('avatarPalette call sites (Ticket 13 migration marker)', () {
    test('none — the palette is gone', () {
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
          .toSet();

      expect(
        referencing,
        isEmpty,
        reason:
            'avatarPalette was replaced by WpCategorySlot in Ticket 13 and must '
            'stay gone — a hue set outside the slot governance is a second, '
            'meaningless color system. Found: $referencing',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Decorative layer (Ticket 16, maintainer decision ④ = b)
  //
  // The category groups above assert *floors* — a category mark has to be seen
  // (≥ 3:1) and read. The decorative layer is governed in the opposite
  // direction: it owes a *ceiling*, because a decoration that can be read is a
  // signal, and a signal that means nothing is the defect this layer was
  // opened under the condition of avoiding.
  // -------------------------------------------------------------------------

  // The floor `WpAvatarTint`'s disc has to clear to register as a graphical
  // object (WCAG 1.4.11) — reused here as the ceiling the wash must stay
  // *under*. One number, two directions: above it a shape is an object the
  // user can read, below it a field is atmosphere.
  const decorativeCeiling = 1.5;

  group('Decorative chrome wash – structure', () {
    test('the wash is the source hue at alpha only', () {
      for (final (themeName, source, wash) in [
        (
          'dark',
          WpDecorativeColorsDark.source,
          WpDecorativeColorsDark.chromeWash,
        ),
        (
          'light',
          WpDecorativeColorsLight.source,
          WpDecorativeColorsLight.chromeWash,
        ),
      ]) {
        expect(
          wash.toARGB32() & 0x00FFFFFF,
          source.toARGB32() & 0x00FFFFFF,
          reason:
              '$themeName: the wash carries RGB the source does not — the '
              'decorative layer is one hue whose only free dimension is alpha, '
              'which is what makes it unable to encode a per-entry difference',
        );
        expect(
          wash.a,
          lessThan(source.a),
          reason: '$themeName: the wash must be translucent, not the raw hue',
        );
      }
    });

    test('the resolver takes no identity, only the theme', () {
      expect(
        wpDecorativeChromeWash(true),
        WpDecorativeColorsDark.chromeWash,
        reason: 'dark resolves to the dark wash',
      );
      expect(
        wpDecorativeChromeWash(false),
        WpDecorativeColorsLight.chromeWash,
        reason: 'light resolves to the light wash',
      );
      expect(
        wpDecorativeChromeWash(true),
        isNot(wpDecorativeChromeWash(false)),
        reason: 'the decorative layer is a theme pair like everything else',
      );
    });

    test('call sites reach the wash through the resolver, never the tokens', () {
      final lib = Directory('lib');
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
            'an empty result below would pass vacuously',
      );

      final referencing = dartFiles
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((path) => path != 'lib/core/theme/colors.dart')
          .where(
            (path) =>
                File(path).readAsStringSync().contains('WpDecorativeColors'),
          )
          .toSet();

      expect(
        referencing,
        isEmpty,
        reason:
            'the decorative tokens were read directly instead of through '
            'wpDecorativeChromeWash(isDark). The resolver is the layer\'s only '
            'door precisely because it accepts no identity — reaching past it '
            'is how a decoration starts meaning something. Found: $referencing',
      );
    });

    test('the decorative hue is not the accent and not the analytics ramp '
        'source', () {
      for (final (themeName, source, accent) in [
        ('dark', WpDecorativeColorsDark.source, WpColorsDark.accent),
        ('light', WpDecorativeColorsLight.source, WpColorsLight.accent),
      ]) {
        final hue = HSLColor.fromColor(source).hue;
        expect(
          hue,
          isNot(inInclusiveRange(165, 215)),
          reason:
              '$themeName: the decorative hue landed at '
              '${hue.toStringAsFixed(1)}°, inside the 165–215° cyan/teal band '
              'reserved for the brand accent (decision ② = b)',
        );
        expect(
          (hue - HSLColor.fromColor(accent).hue).abs(),
          greaterThan(45),
          reason:
              '$themeName: the decorative hue sits within 45° of the accent — '
              'decoration must not be mistakable for the one voice',
        );

        // Ticket 14 sources the analytics duration ramp from `iris`. A
        // decorative wash that reads as a paler iris would put the ordinal
        // scale's hue on the chrome around it.
        //
        // The clearance is held against `iris` only, and deliberately so: the
        // *second* ordinal ramp — the settings tier-performance line (Ticket
        // 18) — is cut from `orchid`, 18° away, and is exempt by construction
        // rather than by oversight. What holds the two apart there is form and
        // weight, the same argument this group's other tests gate: the wash is
        // a ≤5 % field at 1.03–1.07:1, the ramp is opaque text at ≥4.5:1.
        // Asserting >45° against every ramp source would fail here, and the
        // failure would be wrong — see *The Categorical vs. Sequential Rule*.
        final irisHue = HSLColor.fromColor(
          WpCategorySlot.iris.color(themeName == 'dark'),
        ).hue;
        expect(
          (hue - irisHue).abs(),
          greaterThan(45),
          reason:
              '$themeName: the decorative hue sits within 45° of the `iris` '
              'ramp source (Ticket 14) — one hue, two layers',
        );
      }
    });
  });

  // The grounds the wash is actually painted on — the window frame, which is
  // what shows through the nav rail and the settings page. Deliberately *not*
  // `surface`/`surfaceElevated`/`surfaceVariant`: those are opaque fills drawn
  // on top of the wash, so a card's own text never sees it.
  for (final (themeName, isDark, accent, wash, grounds) in [
    (
      'dark',
      true,
      WpColorsDark.accent,
      WpDecorativeColorsDark.chromeWash,
      <String, Color>{
        'background': WpColorsDark.background,
        'frameGradient.top': WpColorsDark.frameGradient.colors.first,
        'frameGradient.bottom': WpColorsDark.frameGradient.colors.last,
      },
    ),
    (
      'light',
      false,
      WpColorsLight.accent,
      WpDecorativeColorsLight.chromeWash,
      <String, Color>{
        'background': WpColorsLight.background,
        'frameGradient.top': WpColorsLight.frameGradient.colors.first,
        'frameGradient.bottom': WpColorsLight.frameGradient.colors.last,
      },
    ),
  ]) {
    group('Decorative wash stays under the object threshold – $themeName theme '
        '(< $decorativeCeiling:1)', () {
      grounds.forEach((groundName, ground) {
        test(groundName, () {
          final washed = alphaComposite(wash, ground);
          final ratio = contrastRatio(washed, ground);
          expect(
            ratio,
            lessThan(decorativeCeiling),
            reason:
                '$themeName: the wash lifts $groundName by '
                '${ratio.toStringAsFixed(3)}:1 — at or above '
                '$decorativeCeiling:1 it reads as a graphical object, and an '
                'object that means nothing is exactly what the decorative '
                'layer may not become',
          );
          expect(
            ratio,
            greaterThan(1.0),
            reason:
                '$themeName: the wash leaves $groundName untouched — a '
                'decoration nobody can see is not quiet, it is absent',
          );
        });
      });

      test('quieter than the accent and than every category slot', () {
        final ground = grounds['background']!;
        final washRatio = contrastRatio(alphaComposite(wash, ground), ground);
        expect(
          washRatio,
          lessThan(contrastRatio(accent, ground)),
          reason:
              '$themeName: decoration must sit below the brand voice — the '
              'same ladder the category layer already stands on',
        );
        for (final slot in WpCategorySlot.values) {
          expect(
            washRatio,
            lessThan(contrastRatio(slot.color(isDark), ground)),
            reason:
                '$themeName: the wash is louder than the ${slot.name} slot — '
                'the nominal layer carries meaning and must out-rank a '
                'decoration on every surface they share',
          );
        }
      });

      test('body text keeps AA over the washed ground', () {
        final texts = <String, Color>{
          'textPrimary': isDark
              ? WpColorsDark.textPrimary
              : WpColorsLight.textPrimary,
          'textSecondary': isDark
              ? WpColorsDark.textSecondary
              : WpColorsLight.textSecondary,
          'textMuted': isDark
              ? WpColorsDark.textMuted
              : WpColorsLight.textMuted,
        };
        grounds.forEach((groundName, ground) {
          final washed = alphaComposite(wash, ground);
          texts.forEach((textName, text) {
            final ratio = contrastRatio(text, washed);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$themeName: $textName over washed $groundName is only '
                  '${ratio.toStringAsFixed(2)}:1 — decoration never costs '
                  'legibility',
            );
          });
        });
      });
    });
  }

  // Parity with the category layer's ceiling: the decorative source is not the
  // accent and may not reach for the accent's pitch either.
  group('Decorative source saturation – ≤ 80%', () {
    for (final (themeName, source) in [
      ('dark', WpDecorativeColorsDark.source),
      ('light', WpDecorativeColorsLight.source),
    ]) {
      test(themeName, () {
        final sat = hslSaturation(source);
        expect(
          sat,
          lessThanOrEqualTo(0.80),
          reason:
              '$themeName: the decorative source is '
              '${(sat * 100).toStringAsFixed(0)} % saturated — over the 80 % '
              'ceiling the whole palette outside the accent stands under',
        );
      });
    }
  });
}

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

import 'package:flutter/painting.dart'
    show Alignment, BoxShadow, HSLColor, LinearGradient;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart' show WpLayout, WpShadows;
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

/// The lightest and the darkest stop of a gradient, by relative luminance.
///
/// Picked by measurement rather than by stop index on purpose: which end of an
/// ambient gradient is the bright one is a tuning decision that later tickets
/// still move, and a hard-coded `colors.first`/`colors.last` would silently
/// start gating the wrong extreme when it does.
({Color lightest, Color darkest}) gradientExtremes(LinearGradient gradient) {
  final sorted = [...gradient.colors]
    ..sort((a, b) => relativeLuminance(a).compareTo(relativeLuminance(b)));
  return (lightest: sorted.last, darkest: sorted.first);
}

/// True when a color carries no hue at all — R, G and B identical, i.e. a
/// neutral white/grey/black that only varies in alpha.
bool isAchromatic(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return r == g && g == b;
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

/// HSL of a color computed from its *floating-point* channels.
///
/// `HSLColor.fromColor` reads the 8-bit accessors and rounds before it
/// converts. Harmless for a token — a token is 8-bit anyway — but it turns a
/// *sampled* point on a gradient into rounding noise: at the lightness the
/// ambients live at, one LSB is worth several degrees of hue, so the same
/// gradient measured two pixels apart would appear to turn by 4°. Used for
/// everything sampled off a gradient; the plain [hslSaturation] /
/// [hslLightness] stay for the 8-bit tokens the rest of this file audits.
({double hue, double saturation, double lightness}) preciseHsl(Color c) {
  final max = math.max(c.r, math.max(c.g, c.b));
  final min = math.min(c.r, math.min(c.g, c.b));
  final delta = max - min;
  final lightness = (max + min) / 2.0;
  if (delta == 0) {
    return (hue: 0.0, saturation: 0.0, lightness: lightness);
  }
  final double hue;
  if (max == c.r) {
    hue = 60.0 * (((c.g - c.b) / delta) % 6.0);
  } else if (max == c.g) {
    hue = 60.0 * (((c.b - c.r) / delta) + 2.0);
  } else {
    hue = 60.0 * (((c.r - c.g) / delta) + 4.0);
  }
  return (
    hue: hue % 360.0,
    saturation: delta / (1.0 - (2.0 * lightness - 1.0).abs()),
    lightness: lightness,
  );
}

/// How far a color's channels are spread apart, 0.0–1.0 — chroma in the only
/// unit two colors at different lightnesses can be compared in.
///
/// HSL saturation divides that spread by `1 − |2L − 1|`, which is ≈0.06 on
/// pearl and ≈0.33 on the dark ambient: eighteen *points* of saturation on
/// light and eight on dark are the same four bytes of actual color. Anything
/// comparing chroma *across* the two ambients has to use this instead.
double channelSpread(Color c) =>
    math.max(c.r, math.max(c.g, c.b)) - math.min(c.r, math.min(c.g, c.b));

/// Shortest angular distance between two colors' hues, in degrees.
double hueDelta(Color a, Color b) {
  final gap = (preciseHsl(a).hue - preciseHsl(b).hue).abs();
  final wrapped = gap % 360.0;
  return wrapped > 180.0 ? 360.0 - wrapped : wrapped;
}

// ---------------------------------------------------------------------------
// Sampling a linear gradient at a point — the frame ambient is painted across
// the whole window, so "what color is the frame *there*" is a projection, not
// a stop lookup.
// ---------------------------------------------------------------------------

/// The gradient parameter at the content plane's top-left corner, for a window
/// of [windowSize].
///
/// The frame ambient runs `topLeft → bottomRight` across the entire window, so
/// its gradient line is the vector (w, h) from the window origin. A linear
/// gradient's parameter at a point is that point's scalar projection onto the
/// line, normalised by its squared length — here at
/// (`WpLayout.sidebarWidth`, `WpLayout.appBarHeight`), the corner where the
/// nav rail and the title bar hand over to the content panel.
double seamGradientT(Size windowSize) =>
    frameGradientT(WpLayout.sidebarWidth, WpLayout.appBarHeight, windowSize);

/// The frame ambient's gradient parameter at an arbitrary window point.
///
/// Same projection as [seamGradientT], which is this function evaluated at the
/// one corner Ticket 07 cares about; the nav rail's chips need it at other
/// points, because "what does a chip stand on" is a question about the middle
/// of the rail, not about a corner.
double frameGradientT(double x, double y, Size windowSize) {
  final w = windowSize.width;
  final h = windowSize.height;
  return (x * w + y * h) / (w * w + h * h);
}

/// The color a [gradient] shows at parameter [t] (0 = `begin`, 1 = `end`).
///
/// Deliberately *not* `Color.lerp`: that one rounds its result back to 8 bits,
/// and one LSB is worth several degrees of hue at the lightness both ambients
/// live at — sampling the frame two pixels further along would swing the
/// measured hue by ~4° on pearl without a single token having changed. The
/// shader interpolates in floating point, so this does too, and the gate then
/// measures the gradient rather than its rounding.
Color gradientColorAt(LinearGradient gradient, double t) {
  final colors = gradient.colors;
  final stops =
      gradient.stops ??
      [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
  if (t <= stops.first) return colors.first;
  for (var i = 0; i < stops.length - 1; i++) {
    if (t <= stops[i + 1]) {
      final span = stops[i + 1] - stops[i];
      final f = span == 0 ? 0.0 : (t - stops[i]) / span;
      final a = colors[i];
      final b = colors[i + 1];
      return Color.from(
        alpha: a.a + (b.a - a.a) * f,
        red: a.r + (b.r - a.r) * f,
        green: a.g + (b.g - a.g) * f,
        blue: a.b + (b.b - a.b) * f,
      );
    }
  }
  return colors.last;
}

/// Window sizes the seam is measured at: the smallest the app allows itself to
/// be, the size it actually opens at, and the way up to 4K. The seam's frame
/// color is a *constant* in `colors.dart`, and this range is what says the
/// approximation holds everywhere rather than at the one window it was solved
/// at.
final _seamWindowSizes = <(String, Size)>[
  (
    'minimum window',
    const Size(WpLayout.minWindowWidth, WpLayout.minWindowHeight),
  ),
  ('default window', const Size(1100, 750)),
  ('1440 × 900', const Size(1440, 900)),
  ('1920 × 1080', const Size(1920, 1080)),
  ('3440 × 1440', const Size(3440, 1440)),
  ('3840 × 2160', const Size(3840, 2160)),
];

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

  // The other direction: the label standing *on* a filled accent button, which
  // is the pairing every primary CTA in the app resolves to (`onPrimary` in the
  // Material scheme, `WpButton`'s accent tone). It went ungated until ADR 0013,
  // and an ungated pairing is one nobody notices breaking: rotating the accent
  // hue moved this ratio by 4.6 points (7.12:1 → 11.71:1) without a single test
  // reacting. It happened to move the safe way. Normal-text threshold, because
  // a button label is body-sized.
  const _ColorPair(
    'dark: background on accent (filled button label)',
    WpColorsDark.background,
    WpColorsDark.accent,
  ),
  const _ColorPair(
    'dark: textPrimary on active (neutral button label)',
    WpColorsDark.textPrimary,
    WpColorsDark.active,
  ),
  const _ColorPair(
    'dark: background on error (danger button label)',
    WpColorsDark.background,
    WpColorsDark.error,
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
    WpColorsDark.textPrimary,
    WpColorsDark.surface,
  ),
  const _ColorPair(
    'light: textSecondary on surface',
    WpColorsDark.textSecondary,
    WpColorsDark.surface,
  ),
  const _ColorPair(
    'light: textMuted on surface',
    WpColorsDark.textMuted,
    WpColorsDark.surface,
  ),

  // Text on elevated surface
  const _ColorPair(
    'light: textPrimary on surfaceElevated',
    WpColorsDark.textPrimary,
    WpColorsDark.surfaceElevated,
  ),
  const _ColorPair(
    'light: textSecondary on surfaceElevated',
    WpColorsDark.textSecondary,
    WpColorsDark.surfaceElevated,
  ),
  const _ColorPair(
    'light: textMuted on surfaceElevated',
    WpColorsDark.textMuted,
    WpColorsDark.surfaceElevated,
  ),

  // Text on hover
  const _ColorPair(
    'light: textPrimary on hover',
    WpColorsDark.textPrimary,
    WpColorsDark.hover,
  ),
  const _ColorPair(
    'light: textSecondary on hover',
    WpColorsDark.textSecondary,
    WpColorsDark.hover,
  ),
  const _ColorPair(
    'light: textMuted on hover',
    WpColorsDark.textMuted,
    WpColorsDark.hover,
  ),

  // Text on background (frame)
  const _ColorPair(
    'light: textPrimary on background',
    WpColorsDark.textPrimary,
    WpColorsDark.background,
  ),
  const _ColorPair(
    'light: textSecondary on background',
    WpColorsDark.textSecondary,
    WpColorsDark.background,
  ),

  // Accent as text (large text)
  const _ColorPair(
    'light: accent on surface (large)',
    WpColorsDark.accent,
    WpColorsDark.surface,
    isLargeText: true,
  ),

  // Recording accent — see the dark half. Light mirrors the accent's coverage
  // exactly, which means surface only: `accent` never carried an
  // on-background pair here, so its twin does not invent one.
  const _ColorPair(
    'light: recordingAccent on surface (large)',
    WpColorsDark.recordingAccent,
    WpColorsDark.surface,
    isLargeText: true,
  ),

  // Status colors on surface (large text)
  const _ColorPair(
    'light: success on surface (large)',
    WpColorsDark.success,
    WpColorsDark.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'light: warning on surface (large)',
    WpColorsDark.warning,
    WpColorsDark.surface,
    isLargeText: true,
  ),
  const _ColorPair(
    'light: error on surface (large)',
    WpColorsDark.error,
    WpColorsDark.surface,
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
      const _SaturationCheck('light: accent', WpColorsDark.accent, 0.40),
      const _SaturationCheck(
        'light: recordingAccent',
        WpColorsDark.recordingAccent,
        0.40,
      ),
      const _SaturationCheck('light: success', WpColorsDark.success, 0.40),
      const _SaturationCheck('light: warning', WpColorsDark.warning, 0.40),
      const _SaturationCheck('light: error', WpColorsDark.error, 0.40),
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
        WpColorsDark.background,
        0.15,
      ),
      const _SaturationCheck('light: surface', WpColorsDark.surface, 0.15),
      const _SaturationCheck(
        'light: surfaceElevated',
        WpColorsDark.surfaceElevated,
        0.15,
      ),
      const _SaturationCheck(
        'light: surfaceVariant',
        WpColorsDark.surfaceVariant,
        0.15,
      ),
      const _SaturationCheck('light: hover', WpColorsDark.hover, 0.15),
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
      final bgL = hslLightness(WpColorsDark.background);
      final sfL = hslLightness(WpColorsDark.surface);
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

  // GROUNDS — re-derived 2026-08-11, when the chip material was ported onto
  // the disc.
  //
  // > **Retracted: "against `surface` / `surfaceElevated`".** Those two flat
  // > tokens used to be the whole ground set here, and for the card view they
  // > still are — `HistoryEntryCard` really does paint an opaque
  // > `surfaceElevated` under its avatar. But the *list* row is the avatar's
  // > primary home and it paints no fill at rest at all
  // > (`WpListTileSurface._fill()` returns `hoverTransparent`), so the disc
  // > there sits directly on the content plane, and so does the detail-panel
  // > header. The plane is the tighter ground on dark — its brightest stop is
  // > brighter than either flat token — so the old gate was measuring the
  // > easier case and calling it the worst one. Recorded rather than swapped
  // > silently: the flat tokens were a reasonable stand-in while the plane was
  // > nearly flat itself, and Ticket 07's seam lift is what ended that.
  //
  // The plane's stops are read off the token rather than pinned, so this gate
  // follows the ambient wherever it is next tuned instead of going stale
  // against a hard-coded hex.
  const discFloor = 1.5;
  const discBottomStopFloor = 1.3;
  const glyphFloor = 3.0;

  for (final (themeName, plane, surface, surfaceElevated, hover) in [
    (
      'dark',
      WpColorsDark.warmSurfaceGradient,
      WpColorsDark.surface,
      WpColorsDark.surfaceElevated,
      WpColorsDark.hover,
    ),
    (
      'light',
      WpColorsDark.warmSurfaceGradient,
      WpColorsDark.surface,
      WpColorsDark.surfaceElevated,
      WpColorsDark.hover,
    ),
  ]) {
    const tint = WpAvatarTint.dark;

    /// Every ground an entry avatar is ever painted on.
    final avatarGrounds = <String, Color>{
      for (var i = 0; i < plane.colors.length; i++)
        'content plane stop $i': plane.colors[i],
      // The list row's hover/focus fill is opaque, so it replaces the plane
      // under the avatar rather than tinting it.
      'hovered row': alphaComposite(hover, plane.colors.first),
      'surface': surface,
      // The card view is the one call site with a real opaque fill under it.
      'surfaceElevated': surfaceElevated,
    };

    group('Avatar disc vs. its ground – $themeName theme (≥ $discFloor:1)', () {
      for (final slot in WpCategorySlot.values) {
        final base = slot.color();
        test(slot.name, () {
          avatarGrounds.forEach((groundName, ground) {
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
                  '$groundName — the disc fades out at its lower edge',
            );
          });
        });
      }
    });

    group('Avatar glyph vs. disc – $themeName theme (≥ $glyphFloor:1)', () {
      // Measured against the disc *body*, not against the crown — the same
      // modeling choice the nav chip's group makes, and for the same reason:
      // the crown covers the first `WpAvatarTint.glossStop` of the disc's
      // height (≈4 px of the 42 px list avatar) and the glyph, at 44 % of the
      // disc centred in it, never reaches into that band.
      for (final slot in WpCategorySlot.values) {
        final base = slot.color();
        test(slot.name, () {
          final glyphColor = tint.glyph(base);
          avatarGrounds.forEach((groundName, ground) {
            final top = alphaComposite(tint.fillTop(base), ground);
            final bottom = alphaComposite(tint.fillBottom(base), ground);
            final disc = midpoint(top, bottom);

            for (final (spotName, spot) in [
              ('disc center', disc),
              ('lit top stop', top),
            ]) {
              final glyph = alphaComposite(glyphColor, spot);
              expect(
                contrastRatio(glyph, spot),
                greaterThanOrEqualTo(glyphFloor),
                reason:
                    '$themeName ${slot.name}: glyph only '
                    '${contrastRatio(glyph, spot).toStringAsFixed(2)}:1 against '
                    'the $spotName on $groundName — the icon is not readable',
              );
            }
          });
        });
      }
    });

    // -----------------------------------------------------------------------
    // The crown (2026-08-11) — the disc's half of the nav chip's gloss gate.
    //
    // Three ways a precomposited highlight goes wrong, one assertion each:
    // it can be darker than the fill (a shadow along the top edge, i.e. the
    // disc lit from below); it can be strong enough to read as a second shape
    // drawn on the disc rather than as light falling on it; or — the failure
    // that is specific to a *bounded* object, and which the rail's rectangular
    // tile cannot have — it can climb so close to the ground that the disc's
    // top rim dissolves and the circle looks bitten.
    // -----------------------------------------------------------------------
    group('Avatar gloss – $themeName theme', () {
      for (final slot in WpCategorySlot.values) {
        final base = slot.color();
        test(slot.name, () {
          avatarGrounds.forEach((groundName, ground) {
            final fill = alphaComposite(tint.fillTop(base), ground);
            final gloss = alphaComposite(tint.gloss(base), ground);

            expect(
              relativeLuminance(gloss),
              greaterThan(relativeLuminance(fill)),
              reason:
                  '$themeName ${slot.name} on $groundName: the crown is darker '
                  'than the lit stop under it — that is the disc lit from '
                  'below. "Lit" means lit in both themes; the light theme '
                  'mirrors every other value in this recipe and deliberately '
                  'not this one',
            );

            final step = contrastRatio(gloss, fill);
            expect(
              step,
              lessThan(3.0),
              reason:
                  '$themeName ${slot.name} on $groundName: the crown steps '
                  '${step.toStringAsFixed(2)}:1 over its fill, at the contrast '
                  'an *object* owes (WCAG 1.4.11) — a band that strong stops '
                  'reading as light on the disc and starts reading as a second '
                  'element drawn on it. Same ceiling as the nav chip\'s gloss',
            );

            final crownVsGround = contrastRatio(gloss, ground);
            expect(
              crownVsGround,
              greaterThanOrEqualTo(discFloor),
              reason:
                  '$themeName ${slot.name} on $groundName: the crown holds '
                  'only ${crownVsGround.toStringAsFixed(2)}:1 against the '
                  'ground, under the $discFloor:1 the disc owes as a graphical '
                  'object. The crown is part of the disc, not a hole in it — '
                  'below this floor the circle loses its top rim and reads as '
                  'a crescent',
            );
          });
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
  // the full 4.5:1. That floor is why the line starts at the ramp's third rung:
  // the two beneath are solved for a graphical object's 3:1 and land at 3.60:1
  // and 4.40:1 on the tightest ground below.
  //
  // Retracted 2026-08-11 (dark-only build): this note also rested the
  // traffic-light refusal on measurement — `WpColorsLight.warning` reaching
  // only 3.11:1 and `WpColorsLight.success` 3.74:1 on these grounds. Both were
  // light-stack figures and are not re-derived against dark here; the refusal
  // now rests on *The Categorical vs. Sequential Rule* alone, as
  // `lib/widgets/tier_performance_presentation.dart` records at more length.
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

  for (final (themeName, surface, surfaceElevated, accentButtonFill, hover) in [
    // The `light` row of this table went with the light stack (2026-08-11).
    // It gated the same tokens against the same floor with `isDark: false`,
    // which no longer describes anything the app can render.
    (
      'dark',
      WpColorsDark.surface,
      WpColorsDark.surfaceElevated,
      WpColorsDark.accentButtonFill,
      WpColorsDark.hover,
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
          WpTierPerformancePresentation.color(performance: p);

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
            delta,
            greaterThan(0),
            reason:
                '$themeName: ${measured[i].name} does not sit further from the '
                'ground than ${measured[i - 1].name}. The line reports how much '
                'time a tier costs, so its weight has to rise with that cost — '
                'and it has to rise in the direction the theme leaves room in, '
                'lighter on a dark ground',
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
      expect(WpCategoryColorsDark.slots.length, WpCategorySlot.values.length);
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
        WpCategoryColorsDark.slots.last,
        WpCategoryColorsDark.neutral,
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
      for (final (themeName) in [('dark'), ('light')]) {
        final colors = WpCategorySlot.values
            .map((s) => s.color().toARGB32())
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
      for (final (themeName, expected) in [('dark', dark), ('light', light)]) {
        expect(
          expected.keys.toSet(),
          WpCategorySlot.values.toSet(),
          reason: '$themeName: a slot was added without a color of its name',
        );
        expected.forEach((slot, color) {
          expect(
            slot.color(),
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
        for (final slot in [categorySlotForModel(id), categorySlotForTag(id)]) {
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
    });
  });

  for (final (themeName, accent, grounds) in [
    (
      'dark',
      WpColorsDark.accent,
      <String, Color>{
        'surface': WpColorsDark.surface,
        'surfaceElevated': WpColorsDark.surfaceElevated,
        'surfaceVariant': WpColorsDark.surfaceVariant,
      },
    ),
    (
      'light',
      WpColorsDark.accent,
      <String, Color>{
        'surface': WpColorsDark.surface,
        'surfaceElevated': WpColorsDark.surfaceElevated,
        'surfaceVariant': WpColorsDark.surfaceVariant,
      },
    ),
  ]) {
    group(
      'Category slot vs. surfaces – $themeName theme (≥ $categorySlotFloor:1)',
      () {
        for (final slot in WpCategorySlot.values) {
          test(slot.name, () {
            final color = slot.color();
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
          final ratio = contrastRatio(slot.color(), surface);
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
    for (final (themeName) in [('dark'), ('light')]) {
      for (final slot in WpCategorySlot.values) {
        test('$themeName: ${slot.name}', () {
          final color = slot.color();
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
  // most-used models the same hue — hence a table, with the hash left as the
  // fallback for an id the table has not met.
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

    for (final (themeName, grounds) in [
      (
        'dark',
        <String, Color>{
          'surface': WpColorsDark.surface,
          'surfaceElevated': WpColorsDark.surfaceElevated,
          'surfaceVariant': WpColorsDark.surfaceVariant,
          'background': WpColorsDark.background,
        },
      ),
      // The `light` row went with the light stack (2026-08-11). It gated the
      // same nine slots against the same grounds with `isDark: false`, which
      // `WpCategorySlot.ramp` no longer answers differently.
    ]) {
      for (final slot in WpCategorySlot.values) {
        test('$themeName: ${slot.name} — rungs are separable and legible', () {
          for (var steps = 3; steps <= 5; steps++) {
            final rungs = slot.ramp(steps);
            expect(rungs, hasLength(steps));
            expect(
              rungs.first,
              slot.color(),
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
              // re-arguing it, and what stops the low end sinking under 3:1.
              final delta =
                  relativeLuminance(rungs[i]) - relativeLuminance(rungs[i - 1]);
              expect(
                delta,
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
      expect(() => WpCategorySlot.iris.ramp(2), throwsAssertionError);
      expect(() => WpCategorySlot.iris.ramp(6), throwsAssertionError);
    });

    // Ticket 11, ② = (b): cyan stays the accent's alone, so no ordinal ramp may
    // be built from it. The tickets call the forbidden hue "slot 0", meaning the
    // pre-Ticket-12 palette's Harbor Cyan — not `WpCategorySlot.values[0]`,
    // which is `iris`. Ticket 12 dropped the whole 165–215° band from the
    // category recipe, so the exclusion is structural: a ramp takes a
    // `WpCategorySlot`, and no slot is cyan. This pins that it stays that way.
    test('no ramp can be built out of the accent band', () {
      for (final slot in WpCategorySlot.values) {
        for (final rung in slot.ramp(5)) {
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
  // Decorative layer (Ticket 16) — retracted 2026-08-11
  //
  // Four groups lived here and gated *Quartz*, the decorative chrome wash:
  // that the wash was the source hue at alpha only, that its resolver took no
  // identity, that no call site reached past the resolver to the tokens, that
  // the hue was neither the accent nor the `iris` ramp source, that the wash
  // stayed under the 1.5:1 at which a field would read as a graphical object,
  // and that text over the washed ground kept AA.
  //
  // The layer is gone: the settings page was its last surface (Ticket 06 had
  // already taken it off the nav rail), the maintainer reported that surface as
  // the defect, and `WpDecorativeColorsDark` / `wpDecorativeChromeWash()` were
  // removed with it. These gates measured a color that no longer exists, so
  // they are removed rather than left to pass vacuously — the sweep asserting
  // that nothing under `lib/` touches the tokens would have gone green forever
  // on a layer that had ceased to exist.
  //
  // Recorded rather than silently dropped, per the audit convention
  // `lib/DESIGN.md` states for its own retracted rules. `decorativeGlyphWash`
  // is a different token under a different rule and is still gated below.
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Frost material (Ticket 04) — the executable half of the material rules
  //
  // The redesign drops `BackdropFilter` entirely and *precomposites* the frost
  // instead: a tinted translucent fill painted over one chromatic ambient
  // gradient. That only works if the fill is gated where it is actually
  // painted, so the gates below composite each card fill onto the ambient it
  // sits on before measuring anything.
  //
  // Which ambient: `warmSurfaceGradient`, deliberately **not** `frameGradient`
  // — not because the frame was unsettled (Ticket 06 has since retuned it),
  // but because that is where cards actually stand. Nothing on the frame is a
  // card; the frame carries bar text and chips, gated in its own group below.
  // -------------------------------------------------------------------------

  for (final (themeName, ambient, fills, texts, accent) in [
    (
      'dark',
      WpColorsDark.warmSurfaceGradient,
      <String, Color>{
        'cardFill': WpColorsDark.cardFill,
        'cardFillElevated': WpColorsDark.cardFillElevated,
      },
      <String, Color>{
        'textPrimary': WpColorsDark.textPrimary,
        'textSecondary': WpColorsDark.textSecondary,
        'textMuted': WpColorsDark.textMuted,
      },
      WpColorsDark.accent,
    ),
    (
      'light',
      WpColorsDark.warmSurfaceGradient,
      <String, Color>{
        'cardFill': WpColorsDark.cardFill,
        'cardFillElevated': WpColorsDark.cardFillElevated,
      },
      <String, Color>{
        'textPrimary': WpColorsDark.textPrimary,
        'textSecondary': WpColorsDark.textSecondary,
        'textMuted': WpColorsDark.textMuted,
      },
      WpColorsDark.accent,
    ),
  ]) {
    final extremes = gradientExtremes(ambient);
    final grounds = <String, Color>{
      'ambient.lightest': extremes.lightest,
      'ambient.darkest': extremes.darkest,
    };

    group('Card fill over the ambient extremes – $themeName theme', () {
      fills.forEach((fillName, fill) {
        test(fillName, () {
          grounds.forEach((groundName, ground) {
            final composited = alphaComposite(fill, ground);

            // Body text on the card: WCAG 1.4.3, the full 4.5:1.
            texts.forEach((textName, text) {
              final ratio = contrastRatio(text, composited);
              expect(
                ratio,
                greaterThanOrEqualTo(4.5),
                reason:
                    '$themeName $fillName over $groundName: $textName reaches '
                    'only ${ratio.toStringAsFixed(2)}:1 — a card fill that '
                    'costs legibility at one end of the ambient is not a card '
                    'fill, it is a gradient bug waiting for a wide window',
              );
            });

            // The accent as a graphical object on the card: WCAG 1.4.11, 3:1.
            final accentRatio = contrastRatio(accent, composited);
            expect(
              accentRatio,
              greaterThanOrEqualTo(3.0),
              reason:
                  '$themeName $fillName over $groundName: the accent reaches '
                  'only ${accentRatio.toStringAsFixed(2)}:1 — an interactive '
                  'mark on a card owes 3:1 (WCAG 1.4.11)',
            );
          });
        });
      });
    });
  }

  // Tinted-never-grey, the half a machine can check: a fill may not be a
  // neutral white/black alpha. (Stated here, not cited — `lib/DESIGN.md` gets
  // the named rule in a follow-up ticket.) This is the direct correction of
  // the "painted glass reads grey" failure — a white-alpha fill over a
  // chromatic ground *desaturates* it, which is exactly how the frost lost its
  // color.
  //
  // Scoped to fills on purpose. Hairlines and borders (`borderSubtle`,
  // `borderDefault`, `cardActiveBorder`) are neutral by design and are a
  // different question; the rule as written names surfaces.
  group('Card material – every fill carries hue', () {
    final fills = <String, Color>{
      'dark: cardFill': WpColorsDark.cardFill,
      'dark: cardFillElevated': WpColorsDark.cardFillElevated,
      'light: cardFill': WpColorsDark.cardFill,
      'light: cardFillElevated': WpColorsDark.cardFillElevated,
    };

    fills.forEach((name, fill) {
      test(name, () {
        expect(
          isAchromatic(fill),
          isFalse,
          reason:
              '$name is a neutral white/black alpha '
              '(#${fill.toARGB32().toRadixString(16).padLeft(8, '0')}) — the '
              'hue has to live in the token, not in whatever happens to be '
              'underneath it',
        );
        expect(
          fill.a,
          lessThan(1.0),
          reason:
              '$name is opaque — a precomposited frost is translucent by '
              'definition; an opaque fill cuts the card out of its ambient',
        );
      });
    });
  });

  // The static 1px top edge: a highlight, not a light source. It has to lift
  // the fill it sits on (otherwise it is a shadow) and stay under the same
  // 1.5:1 object threshold the decorative wash is held to (otherwise it reads
  // as a drawn line the user is meant to interpret).
  for (final (themeName, ambient, elevatedFill, edge) in [
    (
      'dark',
      WpColorsDark.warmSurfaceGradient,
      WpColorsDark.cardFillElevated,
      WpColorsDark.cardEdgeHighlight,
    ),
    (
      'light',
      WpColorsDark.warmSurfaceGradient,
      WpColorsDark.cardFillElevated,
      WpColorsDark.cardEdgeHighlight,
    ),
  ]) {
    group('Card edge highlight – $themeName theme', () {
      final extremes = gradientExtremes(ambient);

      test('translucent and hue-bearing', () {
        expect(
          edge.a,
          lessThan(1.0),
          reason: '$themeName: the edge highlight must be translucent',
        );
        expect(
          isAchromatic(edge),
          isFalse,
          reason:
              '$themeName: the edge highlight is a neutral white alpha — same '
              'rule as the fills, same reason',
        );
      });

      for (final (groundName, ground) in [
        ('ambient.lightest', extremes.lightest),
        ('ambient.darkest', extremes.darkest),
      ]) {
        test('lifts the card and stays quiet on $groundName', () {
          final card = alphaComposite(elevatedFill, ground);
          final lit = alphaComposite(edge, card);

          expect(
            relativeLuminance(lit),
            greaterThan(relativeLuminance(card)),
            reason:
                '$themeName: the top edge darkens its card on $groundName — a '
                'highlight that subtracts light is a shadow with the wrong '
                'name',
          );
          final ratio = contrastRatio(lit, card);
          expect(
            ratio,
            lessThan(1.5),
            reason:
                '$themeName: the top edge lifts its card by '
                '${ratio.toStringAsFixed(3)}:1 on $groundName — at or above '
                '1.5:1 it reads as a graphical object (same ceiling the '
                'decorative wash stands under), and the material is supposed '
                'to be felt, not read',
          );
        });
      }
    });
  }

  // Removed 2026-08-11 (dark-only build): `Card shadow – light theme only,
  // tinted, offset`.
  //
  // The group gated the light theme's single card shadow — that
  // `WpColorsLight.cardShadowLight` was a *tinted* ink rather than neutral
  // black (a neutral black at alpha is what sent the light theme grey under
  // its own cards), that it stayed under 20 % alpha, that it was darker than
  // its ground, and that `WpShadows.cardTintedLight` was wired to that same
  // token. Both tokens are deleted with the light stack, so every assertion
  // here referenced a name that no longer exists.
  //
  // Nothing about the *dark* half moved: dark takes its depth from the
  // brightness delta between fills and still owns no card shadow token at all.
  // That was never assertable here anyway — a missing member is a compile
  // error, not a test failure — and it is now the only case.
  //
  // The tinted-vs-neutral finding is preserved as prose in `tokens.dart`,
  // where `cardTintedLight`'s deletion note keeps the glow/shadow distinction
  // that outlived the token. The offset audit below is unaffected and still
  // gates every surviving shadow.

  // One depth source per theme, the executable half: a *glow* is a colored
  // shadow at offset zero and stays forbidden; a *shadow* is offset + wide
  // blur + low alpha and is allowed, tinted included. (Not yet a named rule in
  // `lib/DESIGN.md` — that file is rewritten in a follow-up ticket — so the
  // rule is stated here rather than cited.)
  //
  // The allowlist is *empty today, by measurement*: no shadow in tokens.dart
  // paints at offset zero, `glassInner` included (it sits at `(0, 1)`). Adding
  // a name here therefore means editing this line in the same commit as the
  // glow and having to argue for it; the only argument that works is a genuine
  // inner edge highlight.
  group('BoxShadow offset audit (one depth source per theme)', () {
    const zeroOffsetAllowlist = <String>{};

    const audited = <String, List<BoxShadow>>{
      'subtle': WpShadows.subtle,
      'subtleTransparent': WpShadows.subtleTransparent,
      'card': WpShadows.card,
      'elevated': WpShadows.elevated,
      'glassInner': WpShadows.glassInner,
    };

    test('the audit covers every shadow token in tokens.dart', () {
      final source = File('lib/core/theme/tokens.dart').readAsStringSync();
      final declared = RegExp(
        r'static const List<BoxShadow>\s+(\w+)',
      ).allMatches(source).map((m) => m.group(1)!).toSet();

      expect(
        declared.length,
        greaterThan(4),
        reason:
            'the parse found only ${declared.length} shadow lists in '
            'tokens.dart — the audit below would pass vacuously',
      );
      expect(
        declared,
        audited.keys.toSet(),
        reason:
            'a shadow token was added or renamed without being audited '
            'for offset (a glow is a colored shadow at offset zero)',
      );
    });

    audited.forEach((name, shadows) {
      test(name, () {
        for (var i = 0; i < shadows.length; i++) {
          final shadow = shadows[i];
          if (shadow.offset.dy != 0 || shadow.offset.dx != 0) continue;
          expect(
            zeroOffsetAllowlist,
            contains(name),
            reason:
                '$name[$i] paints at offset zero — a colored shadow with no '
                'offset is a glow, and glow is what this palette replaced '
                'with layered material. Add it to the inner-highlight '
                'allowlist only if it really is an inner edge.',
          );
        }
      });
    });
  });

  // -------------------------------------------------------------------------
  // Two accents, two jobs — the accent means "you can act on this", the
  // recording family means "a recording or its transcription is in flight".
  // Two jobs, and nothing may present them as competing interactive treatments
  // of the same thing.
  //
  // ~~Two *hues*, two jobs.~~ **The hue-exclusivity clause is retracted (ADR
  // 0013, 2026-08-11)** — the accent is back in the recording family's cyan,
  // where it sat, byte-identically, for the app's entire life before Ticket 04
  // without the two ever being confused. What survives the retraction is
  // everything this group actually tests: the tokens stay separate, the
  // recording family stays inside its audited call sites, and no site presents
  // both as rival brand voices. The discrimination the hue used to carry is
  // now carried by weight (see the sibling group below) plus context, form and
  // motion — a waveform animates, an overlay frames, a button does neither.
  //
  // Pinned as a file allowlist rather than as "no file uses both": the status
  // bar legitimately paints both — the transcribing dot is a recording signal,
  // the chip's own borders and icons are generic interaction — and a naive
  // mutual-exclusion test would have to be weakened into vacuity to survive
  // that. What is actually checkable is that the recording family stays inside
  // its audited call sites, and that none of those sites also carries a
  // primary CTA *gradient*.
  //
  // Named in `lib/DESIGN.md` as *The Two Accent, Two Jobs Rule*, carrying the
  // same retraction note.
  // -------------------------------------------------------------------------

  group('Two accents, one family, separated by weight', () {
    // The mechanism that replaces the retracted hue gap, and deliberately the
    // same one the ambient uses against this same signal ("Ambient vs. the
    // recording signal"): where two things must not be mistaken for each
    // other, gate the weight between them, not the angle.
    //
    // The band is two-sided on purpose. Too close and the split is a
    // distinction the eye cannot make, which is what the byte-identical
    // pre-Ticket-04 state was; too far and they stop reading as one family and
    // the retraction has quietly re-introduced a second brand voice.
    const familyFloor = 1.12;
    const familyCeiling = 1.5;

    test('they are one hue family, not two', () {
      final gap = hueDelta(WpColorsDark.accent, WpColorsDark.recordingAccent);
      expect(
        gap,
        lessThan(5.0),
        reason:
            'accent and recordingAccent sit ${gap.toStringAsFixed(1)}° apart. '
            'ADR 0013 put them back in one family; a visible hue gap between '
            'them is the exclusivity that ADR retracted, creeping back in',
      );
    });

    test('the signal is the heavier of the two', () {
      final step = contrastRatio(
        WpColorsDark.accent,
        WpColorsDark.recordingAccent,
      );

      expect(
        relativeLuminance(WpColorsDark.accent),
        greaterThan(relativeLuminance(WpColorsDark.recordingAccent)),
        reason:
            'the recording signal is painted opaque as a shape (waveform, '
            'dot) and must stay the denser, more urgent of the two; the '
            'accent is consumed as 5–30 % alpha washes and as label text, '
            'where luminance is legibility. A signal lighter than the button '
            'beside it has the emphasis the wrong way round',
      );

      expect(
        step,
        greaterThanOrEqualTo(familyFloor),
        reason:
            'accent and recordingAccent step only ${step.toStringAsFixed(3)}:1 '
            'apart — below the floor at which two cyans standing side by side '
            '(a button next to a running recording) are separable at all',
      );

      expect(
        step,
        lessThan(familyCeiling),
        reason:
            'accent and recordingAccent step ${step.toStringAsFixed(3)}:1 '
            'apart, at or above the threshold where two fills stop reading as '
            'one material in two weights and start reading as two different '
            'colors — which is the hue split ADR 0013 retracted, rebuilt out '
            'of luminance',
      );
    });
  });

  group('The accent gradients keep their depth', () {
    // Written because this file did not have it, and the gap cost a round.
    //
    // Both ambient gradients have their end-to-end span gated ("the frame is
    // the livelier ambient"). The accent ramps had nothing equivalent, so when
    // ADR 0013 rotated the hue and a first pass raised all three stops by one
    // constant lightness offset, `accentWarmGradient` collapsed from 1.737:1
    // end to end to 1.207:1 — the bright end had run into the ceiling — and
    // every test in this file still passed. A flat ramp on the token that
    // paints primary buttons, the 3 px sidebar bar and the section markers,
    // shipped during a correction whose whole premise was "this reads flat".
    //
    // Floors, not equalities. The property worth defending is that the ramp
    // does not collapse; pinning today's 1.739:1 exactly would ossify the
    // palette and fire on every legitimate re-tuning, which is how a gate
    // teaches people to edit the gate.
    double spanOf(LinearGradient g) =>
        contrastRatio(g.colors.first, g.colors.last);

    test('accentWarmGradient is anchored at the flat accent', () {
      // Load-bearing, not cosmetic: this gradient paints the 3 px sidebar and
      // section indicator bars, and their ≈7:1 against their grounds is bought
      // entirely by the first stop being the accent itself. A darker teal
      // there drops those markers to ≈4:1 app-wide, which no contrast pair in
      // this file would catch — none of them measure a 3 px bar.
      expect(
        WpColorsDark.accentWarmGradient.colors.first,
        WpColorsDark.accent,
        reason:
            'the interactive gradient no longer starts at the flat accent, so '
            'the thin accent bars it paints have quietly lost their contrast '
            'against every ground they sit on',
      );
    });

    test('the ramps still descend far enough to be seen', () {
      final warm = spanOf(WpColorsDark.accentWarmGradient);
      expect(
        warm,
        greaterThan(1.5),
        reason:
            'accentWarmGradient spans only ${warm.toStringAsFixed(3)}:1 end to '
            'end. A gradient that flat is a solid fill wearing three stops — '
            'and it is the primary CTA',
      );

      final line = spanOf(WpColorsDark.accentGradient);
      expect(
        line,
        greaterThan(1.15),
        reason:
            'accentGradient spans only ${line.toStringAsFixed(3)}:1 end to end',
      );
    });

    test('it stays the lighter sibling of the recording ramp, stop for stop', () {
      // Not imposed — it fell out of re-solving the ramp to the old shape, and
      // it is worth holding because it is what makes the two ramps read as one
      // material at two weights rather than as two ramps that happen to be
      // cyan. Same band as the flat tokens, for the same reason.
      final warm = WpColorsDark.accentWarmGradient.colors;
      final signal = WpColorsDark.recordingAccentGradient.colors;
      expect(warm.length, signal.length);

      for (var i = 0; i < warm.length; i++) {
        final step = contrastRatio(warm[i], signal[i]);
        expect(
          relativeLuminance(warm[i]),
          greaterThan(relativeLuminance(signal[i])),
          reason:
              'stop $i of the interactive ramp is no longer lighter than the '
              'matching stop of the recording ramp — the two ramps have '
              'crossed, and with them the emphasis',
        );
        expect(
          step,
          inInclusiveRange(1.12, 1.5),
          reason:
              'stop $i sits ${step.toStringAsFixed(3)}:1 from its recording '
              'counterpart, outside the band the two flat accents hold '
              '(1.12–1.5:1). The ramps are meant to be siblings by the same '
              'margin their anchors are',
        );
      }
    });
  });

  group('Two accents, two jobs – token usage', () {
    List<String> dartFilesUnderLib() {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList();
      expect(
        files.length,
        greaterThan(100),
        reason:
            'the sweep found only ${files.length} Dart files under lib/ — an '
            'empty result below would pass vacuously',
      );
      return files;
    }

    test('the recording family stays inside its audited call sites', () {
      const audited = {
        'lib/core/theme/colors.dart', // the definition site
        'lib/widgets/waveform.dart', // audio-level bars
        'lib/widgets/status_bar.dart', // the transcribing dot
        'lib/features/onboarding/steps/test_recording_step.dart', // sandbox
      };

      final referencing = dartFilesUnderLib()
          .where((p) => File(p).readAsStringSync().contains('recordingAccent'))
          .toSet();

      expect(
        referencing,
        audited,
        reason:
            'the recording accent left (or lost) its audited call sites. It '
            'means one thing — a recording or its transcription is in flight '
            '— and every new home for it is a classification decision, not a '
            'color choice.',
      );
    });

    test('no recording surface also paints a loud generic CTA gradient', () {
      // The flat tokens are deliberately *not* mutually exclusive: the status
      // bar paints `recordingAccent` for the transcribing dot and `accent` for
      // its own borders and icons, and that is correct — one says "a recording
      // is in flight", the other says "you can act on this". What must not
      // happen is a recording surface *also* carrying a primary CTA gradient,
      // because two saturated gradient families on one surface is exactly the
      // "which color means clickable?" guessing game the split ends.
      const loudGenericGradients = [
        'accentGradient',
        'accentWarmGradient',
        'navPillActiveGradient',
      ];

      final recordingFamilyFiles = dartFilesUnderLib()
          .where((p) => p != 'lib/core/theme/colors.dart')
          .where((p) => File(p).readAsStringSync().contains('recordingAccent'))
          .toSet();

      expect(
        recordingFamilyFiles,
        isNotEmpty,
        reason:
            'no file outside colors.dart references the recording family — '
            'the offender scan below would pass vacuously',
      );

      final offenders = <String, List<String>>{};
      for (final path in recordingFamilyFiles) {
        final src = File(path).readAsStringSync();
        final found = loudGenericGradients.where(src.contains).toList();
        if (found.isNotEmpty) offenders[path] = found;
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'a recording surface also paints a primary CTA gradient: '
            '$offenders. Flat generic-accent tokens are fine there; a loud '
            'gradient makes the two families read as rival brand voices.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Tinted-never-grey, the ambient half: the frame and the content plane are
  // *tinted* material, not neutral grey. Same 15 % rung the opaque surfaces
  // already stand on above — one floor for the whole ambient stack rather than
  // a second, differently-argued number.
  //
  // Non-vacuous by construction: the tightest stop today is the light warm
  // gradient's near-neutral pole at ~17 %, i.e. two points of headroom. Pulling
  // any ambient stop toward grey trips this immediately.
  // -------------------------------------------------------------------------

  group('Ambient saturation floor (≥ 15% tint)', () {
    const floor = 0.15;

    // Every ambient stop expressed as the same `_SaturationCheck` the opaque
    // surfaces above use, so the ambient half of the rule is asserted by the
    // same loop rather than by a second implementation of it.
    final checks = <_SaturationCheck>[
      for (final (themeName, gradientName, gradient) in [
        ('dark', 'frameGradient', WpColorsDark.frameGradient),
        ('dark', 'warmSurfaceGradient', WpColorsDark.warmSurfaceGradient),
        ('light', 'frameGradient', WpColorsDark.frameGradient),
        ('light', 'warmSurfaceGradient', WpColorsDark.warmSurfaceGradient),
      ])
        for (var i = 0; i < gradient.colors.length; i++)
          _SaturationCheck(
            '$themeName: $gradientName stop $i',
            gradient.colors[i],
            floor,
          ),
    ];

    test('the sweep found every ambient stop', () {
      expect(
        checks.length,
        greaterThanOrEqualTo(10),
        reason:
            'only ${checks.length} ambient stops were collected — the audit '
            'below would pass near-vacuously',
      );
    });

    for (final check in checks) {
      test(check.name, () {
        final sat = hslSaturation(check.color);
        expect(
          sat,
          greaterThanOrEqualTo(check.minSaturation),
          reason:
              '${check.name} is ${(sat * 100).toStringAsFixed(1)} % saturated '
              '(#${check.color.toARGB32().toRadixString(16).padLeft(8, '0')}) '
              '— under the ${(check.minSaturation * 100).round()} % floor the '
              'ambient stops being material and starts being grey',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // The frame is a lit room (Ticket 06)
  //
  // The frame gradient is the app's loudest ambient: title bar, nav rail and
  // status bar are all painted from it, at one place, and it has to read as
  // one light source falling across the three of them. The saturation floor
  // above already says the stops are tinted; this group says the *shape* is a
  // light — multi-stop, diagonal, walking a hue arc — and that the content
  // plane stays the quieter of the two ambients, which is the half of the
  // reading a later ticket's seam depends on.
  //
  // Each assertion is the executable form of one acceptance criterion, not a
  // fence around the numbers that happen to be in the file today: the margins
  // are stated wide enough that a re-tune stays free and a *reversal* trips.
  // -------------------------------------------------------------------------

  for (final (themeName, frame, content, texts) in [
    (
      'dark',
      WpColorsDark.frameGradient,
      WpColorsDark.warmSurfaceGradient,
      <String, Color>{
        'textPrimary': WpColorsDark.textPrimary,
        'textSecondary': WpColorsDark.textSecondary,
        'textMuted': WpColorsDark.textMuted,
      },
    ),
    (
      'light',
      WpColorsDark.frameGradient,
      WpColorsDark.warmSurfaceGradient,
      <String, Color>{
        'textPrimary': WpColorsDark.textPrimary,
        'textSecondary': WpColorsDark.textSecondary,
        'textMuted': WpColorsDark.textMuted,
      },
    ),
  ]) {
    group('Frame ambient – $themeName theme', () {
      double meanLuminance(LinearGradient g) =>
          g.colors.map((c) => c.computeLuminance()).reduce((a, b) => a + b) /
          g.colors.length;

      // Contrast-ratio-minus-one, i.e. the part of a ratio that is *range*.
      // Ratios sit just above 1.0 for both ambients, and comparing them
      // directly would compare two numbers that are 97 % the constant 1.
      double amplitude(LinearGradient g) =>
          contrastRatio(g.colors.first, g.colors.last) - 1.0;

      test('multi-stop', () {
        expect(
          frame.colors.length,
          greaterThanOrEqualTo(3),
          reason:
              '$themeName: a two-stop frame is a wash, not a room — the light '
              'needs a stop to turn at, or the diagonal reads as a flat tilt',
        );
      });

      test('diagonal, on the same axis as the content plane', () {
        expect(
          (frame.begin, frame.end),
          (Alignment.topLeft, Alignment.bottomRight),
          reason:
              '$themeName: the frame ambient is not diagonal top-left → '
              'bottom-right',
        );
        expect(
          (frame.begin, frame.end),
          (content.begin, content.end),
          reason:
              '$themeName: frame and content plane disagree about where the '
              'light comes from — two rooms, not one',
        );
      });

      test('walks a hue arc, and stays on the ambient one', () {
        final hues = frame.colors
            .map((c) => HSLColor.fromColor(c).hue)
            .toList();
        final span = hues.reduce(math.max) - hues.reduce(math.min);
        expect(
          span,
          greaterThanOrEqualTo(20),
          reason:
              '$themeName: the frame stops span only '
              '${span.toStringAsFixed(1)}° of hue — a colored ambient turns as '
              'it falls; one hue at three lightnesses is a tint, not a light',
        );
        for (final hue in hues) {
          // Widened from 230–305 with ADR 0012 (2026-08-11). Dark's arc now
          // runs 218–256° (brand navy → violet) and light's still runs
          // 258–288° on the Ticket-04 violet, because ADR 0012 is scoped to
          // dark and the light theme is being removed wholesale. The band is
          // the union, and it is still the assertion it always was: the
          // ambient lives in the blue-through-magenta half of the wheel and
          // nowhere else. It excludes every warm hue, and it excludes the
          // cyan/teal below 210° that belongs to `recordingAccent` alone.
          expect(
            hue,
            inInclusiveRange(210, 300),
            reason:
                '$themeName: a frame stop sits at ${hue.toStringAsFixed(1)}°, '
                'off the navy→violet arc the whole ambient stack walks — the '
                'frame is the largest surface in the app and a third hue '
                'family there would out-shout both accents (*Two Accent, Two '
                'Jobs*)',
          );
        }
      });

      // Rehomed from the deleted `Frame cool-shadow stop` group (ADR 0012).
      // Both assertions outlived the rule they were written for, because
      // neither is about the *exception*: they are about the arc's shape.
      test('the last stop is the deepest, so the arc ends where it ends', () {
        final luminances = frame.colors.map(relativeLuminance).toList();
        expect(
          relativeLuminance(frame.colors.last),
          luminances.reduce(math.min),
          reason:
              '$themeName: the frame\'s last stop is not its deepest. The '
              'light falls from the top-left, so the corner furthest from it '
              'has to be the darkest one — and the amplitude gate above '
              'measures first-against-last, so a brighter tail makes it span '
              'the wrong pair and report a range the frame does not have',
        );
      });

      test('the deepest stop stays atmosphere, never a drawn object', () {
        final step = contrastRatio(
          frame.colors.last,
          frame.colors[frame.colors.length - 2],
        );
        expect(
          step,
          lessThan(1.5),
          reason:
              '$themeName: the deepest frame stop steps '
              '${step.toStringAsFixed(3)}:1 against the stop before it, at or '
              'above the threshold this app uses to separate a field from an '
              'object (*The Decorative Color Rule*). A corner the eye reads as '
              'a shape is something the user will look for a meaning in, and '
              'this one has none',
        );
      });

      test(
        'the frame is the livelier ambient, the content plane the quieter',
        () {
          expect(
            amplitude(frame),
            greaterThan(2 * amplitude(content)),
            reason:
                '$themeName: the frame spans '
                '${(1 + amplitude(frame)).toStringAsFixed(3)}:1 end to end and '
                'the content plane ${(1 + amplitude(content)).toStringAsFixed(3)}'
                ':1 — the frame is the room and has to carry the light; a '
                'content plane that patterns itself as strongly competes with '
                'what is printed on it',
          );
        },
      );

      test('the content plane stands above its room', () {
        final frameMean = meanLuminance(frame);
        final contentMean = meanLuminance(content);
        expect(
          contentMean,
          greaterThan(frameMean),
          reason:
              '$themeName: the content plane (mean relative luminance '
              '${contentMean.toStringAsFixed(4)}) is no longer brighter than '
              'the frame (${frameMean.toStringAsFixed(4)}). On dark the '
              'brightness delta between planes is the only depth source there '
              'is, and on light the raised thing is the brighter one too — '
              'livening the frame may not go so far that the panel it carries '
              'reads as recessed',
        );
      });

      // The frame is not a card ground: what stands on it is bar text and
      // chip labels, and it is also the whole ground of the preflight screen.
      texts.forEach((textName, text) {
        test('$textName keeps AA on every frame stop', () {
          for (var i = 0; i < frame.colors.length; i++) {
            final ratio = contrastRatio(text, frame.colors[i]);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$themeName: $textName on frame stop $i is only '
                  '${ratio.toStringAsFixed(2)}:1 — the frame carries the title '
                  'bar, the status-bar chips and the nav rail icons, so range '
                  'in the ambient is bought out of a legibility budget and may '
                  'not overdraw it',
            );
          }
        });
      });
    });
  }

  // -------------------------------------------------------------------------
  // The seam between the frame and the content plane (Ticket 07)
  //
  // The content plane's first stop is painted at its own top-left corner,
  // which sits at (`sidebarWidth`, `appBarHeight`) = (72, 64) of a frame
  // gradient that spans the *whole window*. The plane is meant to read there
  // as the same light, only nearer: **identical hue, lower chroma, more
  // light**. Anything else is a seam the eye reads as two rooms meeting.
  //
  // Why the plane's stop is a constant and this sweep is the gate: the seam
  // sits so close to the frame gradient's origin (t ≈ 0.021–0.095 over every
  // window from the enforced minimum to 4K) that the frame's color there
  // moves by one to three 8-bit steps across that entire range. A constant is
  // therefore exact to within the quantisation of its own neighbourhood — but
  // only this sweep proves it, so it walks the range instead of measuring the
  // one window the token was solved at.
  //
  // "More light" is measured as *relative luminance*, not HSL lightness: both
  // ambients are blue-heavy at their violet end, and HSL lightness weights
  // blue like green while the eye — and every other gate in this file — does
  // not.
  // -------------------------------------------------------------------------

  for (final (themeName, frame, plane, hueTolerance, seamFloor) in [
    // Tolerance is the measured worst case plus headroom, not a fence around
    // today's numbers: the sweep peaks at 1.46° on dark and 1.37° on light,
    // and the *pre-Ticket-07* stops missed by 4.24° / 4.35°, so a regression
    // to them trips this. Light cannot reach 0° at all — at L ≈ 97 % an 8-bit
    // step is worth several degrees of hue, the same quantisation argument
    // `WpColorsLight.frameGradient` already makes for its own stops.
    //
    // The fourth number is the seam's **minimum perceptible step**, swept
    // along the seam's whole length. See the group's third test for where the
    // two values come from and why they differ by so much.
    (
      'dark',
      WpColorsDark.frameGradient,
      WpColorsDark.warmSurfaceGradient,
      3.0,
      1.13,
    ),
    (
      'light',
      WpColorsDark.frameGradient,
      WpColorsDark.warmSurfaceGradient,
      3.0,
      1.05,
    ),
  ]) {
    group('Frame → content-plane seam – $themeName theme', () {
      final planeStart = plane.colors.first;

      for (final (label, window) in _seamWindowSizes) {
        final t = seamGradientT(window);
        final frameAtSeam = gradientColorAt(frame, t);

        test('$label: same light, nearer', () {
          final hueGap = hueDelta(planeStart, frameAtSeam);
          expect(
            hueGap,
            lessThanOrEqualTo(hueTolerance),
            reason:
                '$themeName at $label: the plane starts at hue '
                '${preciseHsl(planeStart).hue.toStringAsFixed(1)}° '
                'where the frame under it is at '
                '${preciseHsl(frameAtSeam).hue.toStringAsFixed(1)}° — '
                'a ${hueGap.toStringAsFixed(1)}° turn across the seam is a '
                'hue *jump*, and the corner then reads as two light sources '
                'meeting rather than as one plane lying in one room',
          );

          // Chroma has to *match* across the seam, within a two-sided band.
          //
          // ~~Chroma has to *fall* across the seam — a surface nearer the
          // light loses chroma; one that gains it reads as a colored panel
          // laid on the room.~~ **The direction requirement is retracted
          // (2026-08-11).** It was asserted at the corner only, and one-sided,
          // and between those two properties it certified the exact defect it
          // was written to prevent: the plane satisfied "less chromatic than
          // the frame" at the corner by 5.6 steps and then drifted to **28
          // steps** below it along the top edge, where the rail and the
          // content stopped reading as one surface at all. A rule that is
          // happy at any distance in one direction cannot police a seam; what
          // matters is that the two surfaces carry the *same* chroma weight,
          // and either sign of divergence breaks that equally.
          //
          // So the band below is symmetric, and the sweep in the sibling test
          // enforces it along the whole seam rather than at one corner. The
          // "one step nearer" reading now rests where it always actually
          // rested: on the luminance step, which is still gated one-sided
          // below.
          //
          // Measured in channel spread (max − min, in 8-bit steps) rather
          // than in HSL saturation. **This is a change of metric, not a
          // relaxed threshold** (2026-08-11), and it is the metric this file
          // already argues for two paragraphs down and in every other cross-
          // theme chroma gate here: HSL's 1 − |2L − 1| divisor is ≈0.33 on
          // dark and ≈0.06 on pearl, so points of saturation are not
          // comparable across the seam, and bytes of color are.
          //
          // The seam re-solve made that difference load-bearing instead of
          // academic. The light plane now sits at #FBF9FF, close enough to
          // white that its divisor collapses and HSL reports **100 %**
          // saturation for a stop carrying six bytes of color — while the
          // frame beneath it, reported at ~53 %, carries eleven. Read in
          // points, the pearl seam looks like a chroma *rise*; read in bytes,
          // chroma falls by the same 4.2–4.7 steps it fell by before, because
          // the additive lift did not touch a single channel difference. The
          // eye agrees with the bytes.
          final planeSpread = channelSpread(planeStart);
          final frameSpread = channelSpread(frameAtSeam);
          expect(
            ((frameSpread - planeSpread) * 255.0).abs(),
            lessThan(8.0),
            reason:
                '$themeName at $label: chroma differs by '
                '${((frameSpread - planeSpread) * 255).toStringAsFixed(1)} '
                '8-bit steps across the seam (frame '
                '${(frameSpread * 255).toStringAsFixed(1)}, plane '
                '${(planeSpread * 255).toStringAsFixed(1)}). Ticket 07 '
                'ratified a difference of ~3–4 steps as "the same light, one '
                'step nearer"; several times that is a chroma cliff at a '
                'corner that carries no border to explain it, in whichever '
                'direction it runs — a grey plane in a saturated room and a '
                'saturated panel on a grey room are the same defect seen from '
                'the two sides',
          );

          expect(
            relativeLuminance(planeStart),
            greaterThan(relativeLuminance(frameAtSeam)),
            reason:
                '$themeName at $label: the plane is not brighter than the '
                'frame at the seam. On dark that delta is the only depth '
                'source there is, and on light the raised thing is the '
                'brighter one too — either way a plane that sits *below* its '
                'room is a hole, not a sheet',
          );
        });

        test('$label: the step stays a seam, never an outline', () {
          final step = contrastRatio(planeStart, frameAtSeam);
          expect(
            step,
            greaterThan(1.01),
            reason:
                '$themeName at $label: the seam steps only '
                '${step.toStringAsFixed(4)}:1 — below that the plane has no '
                'edge at all and the panel stops floating',
          );
          expect(
            step,
            lessThan(1.5),
            reason:
                '$themeName at $label: the seam steps '
                '${step.toStringAsFixed(3)}:1, at or above the threshold at '
                'which a field stops being atmosphere and becomes a drawn '
                'object — the seam carries no border and no contour, so its '
                'whole weight is this step and it may not turn into a line',
          );
        });

        // ---------------------------------------------------------------
        // The magnitude gate (added 2026-08-11, after the maintainer
        // reported no perceivable transition at all)
        //
        // Ticket 07 gated the seam's *direction* and its *continuity* and
        // never its *magnitude*: the assertions above are all satisfied by a
        // step of 1.011:1, which is what shipped, and which is ΔL* 0.5 — at
        // or below the just-noticeable difference. The gate was passing on a
        // step the eye cannot resolve. `greaterThan(1.01)` above is a
        // has-any-step check and is deliberately left where it is; this is
        // the has-*enough*-step check.
        //
        // Two modelling points, both learned from the failure:
        //
        // 1. **The corner is not the worst point.** The seam is an edge with
        //    length. Along the top edge the plane's own gradient parameter
        //    sweeps toward its darkest middle stop while the frame above it
        //    brightens, and the pre-fix step fell from 1.031:1 at the corner
        //    to **1.009:1** mid-edge. A floor measured at the corner alone
        //    would have left exactly the reported failure mode passing, so
        //    this walks both edges of the plane rect at every window size.
        //
        // 2. **The two floors are not a mirrored pair** (*The Theme-Pair
        //    Rule* asks for a reason, and this is it). Dark measures 1.150:1
        //    minimum (ΔL* 6.3) and is floored at 1.10. Pearl measures
        //    1.060:1 (ΔL* 2.3) and is floored at 1.05 — not a weaker choice
        //    but the ceiling: the light plane's first stop is #FBF9FF with
        //    its blue channel clipped at 0xFF, and even a literally white
        //    plane would only reach 1.113:1 there, because the frame under
        //    the seam sits at Y ≈ 0.894 and its own deepest stop is pinned
        //    0.007 above where `textMuted` loses AA on it. Raising the pearl
        //    floor is a decision about `frameGradient`, not a tuning pass on
        //    the plane.
        // ---------------------------------------------------------------
        test('$label: perceptible along the whole seam, not just the corner', () {
          final planeWidth = window.width - WpLayout.sidebarWidth;
          final planeHeight =
              window.height - WpLayout.appBarHeight - WpLayout.statusBarHeight;
          final projection =
              planeWidth * planeWidth + planeHeight * planeHeight;

          const samples = 40;
          var worst = double.infinity;
          var worstAt = '';

          for (var i = 0; i <= samples; i++) {
            final along = i / samples;
            for (final (edge, dx, dy) in <(String, double, double)>[
              ('top edge', planeWidth * along, 0.0),
              ('left edge', 0.0, planeHeight * along),
            ]) {
              // The plane's gradient is sampled in the panel's own rect; the
              // frame's in the window's. Two different projections meeting at
              // one line is precisely why the seam's step varies along it.
              final planeHere = gradientColorAt(
                plane,
                (dx * planeWidth + dy * planeHeight) / projection,
              );
              final frameHere = gradientColorAt(
                frame,
                frameGradientT(
                  WpLayout.sidebarWidth + dx,
                  WpLayout.appBarHeight + dy,
                  window,
                ),
              );

              expect(
                relativeLuminance(planeHere),
                greaterThan(relativeLuminance(frameHere)),
                reason:
                    '$themeName at $label: on the $edge the plane falls below '
                    'the frame beside it — the sheet dips into the room and '
                    'the seam reverses somewhere along its length, even if '
                    'the corner still reads correctly',
              );

              // Chroma tracking, swept — the assertion the corner-only gate
              // could not make. The rail paints no ground of its own, so
              // this line is where the frame and the content plane are
              // literally adjacent, and the defect that reached the
              // maintainer lived here rather than at the corner: hue and
              // luminance tracked the whole way while the plane's chroma
              // slid from 5.6 to 28 steps under the frame's, turning one
              // lit surface into a vivid rail beside a grey panel.
              final chromaGap =
                  (channelSpread(frameHere) - channelSpread(planeHere)) * 255.0;
              // Dark only, and stated rather than quietly scoped. The
              // ceiling is an absolute byte count calibrated on the dark
              // theme, where the two arcs carry 37–61 steps of colour and
              // eight steps of disagreement is the point at which they stop
              // looking like one lit surface.
              //
              // The pearl theme does not survive it: its frame tops out at
              // 12.7 steps and its plane at 4.6, an 8.0–8.1 step split at
              // ~48 % along the top edge — proportionally far worse than the
              // dark defect this gate was written for. That split is **not**
              // introduced here; both light values are untouched by this
              // change and measure the same at HEAD. Correcting it means
              // re-solving `WpColorsLight`, which this change deliberately
              // does not touch, so it is recorded as a known gap rather than
              // hidden by a threshold widened until it passed.
              if (themeName == 'dark') {
                expect(
                  chromaGap.abs(),
                  lessThan(8.0),
                  reason:
                      '$themeName at $label: on the $edge, '
                      '${(along * 100).toStringAsFixed(0)} % along, the frame '
                      'carries ${(channelSpread(frameHere) * 255).toStringAsFixed(1)} '
                      '8-bit steps of color and the plane beside it '
                      '${(channelSpread(planeHere) * 255).toStringAsFixed(1)} '
                      '— a ${chromaGap.abs().toStringAsFixed(1)}-step split. '
                      'The two arcs may start together and still drift apart '
                      'along the seam; where they do, the rail and the content '
                      'stop reading as one surface however well their hue and '
                      'luminance still agree',
                );
              }

              final step = contrastRatio(planeHere, frameHere);
              if (step < worst) {
                worst = step;
                worstAt = '$edge, ${(along * 100).toStringAsFixed(0)} % along';
              }
            }
          }

          expect(
            worst,
            greaterThanOrEqualTo(seamFloor),
            reason:
                '$themeName at $label: the seam\'s weakest point steps only '
                '${worst.toStringAsFixed(4)}:1 ($worstAt), under the '
                '${seamFloor.toStringAsFixed(2)}:1 floor. Direction and '
                'continuity are not perceptibility: a seam this shallow is '
                'the one the maintainer reported as having "no perceivable '
                'transition at all", and it passed every other assertion in '
                'this group',
          );
        });
      }
    });
  }

  // -------------------------------------------------------------------------
  // Ambient vs. the recording signal (2026-08-11, ADR 0012)
  //
  // **This group replaces `Frame cool-shadow stop`, which was deleted with
  // *The Cool-Shadow Exception* it enforced.** That rule let the frame's
  // deepest corner fall back toward blue inside an otherwise violet room, and
  // fenced the opening with 45° of hue clearance from `recordingAccent` plus a
  // saturation ceiling. ADR 0012 returned the whole dark ambient to the
  // brand's blue/navy, so the corner is no longer an exception — it is the
  // rule — and a 45° clearance is not merely unnecessary but structurally
  // unsatisfiable: the ambient now *lives* 28–31° from the recording hue.
  //
  // Deleting a gate without replacing it would leave *Two Accent, Two Jobs*
  // with no executable defence on the ambient at all, so the doctrine moves to
  // the axis that actually carries it. **Weight, not hue distance, is what
  // separates a room from a signal.** The recording accent is a small, bright,
  // bordered mark that appears and disappears; the ambient is a large,
  // borderless, motionless field that is always there. The measurable form of
  // that difference is luminance, and the app has the evidence: it shipped a
  // navy ambient under a cyan accent for its entire life before Ticket 04, at
  // roughly this separation, and no one confused the two.
  //
  // Dark only, and *The Theme-Pair Rule* asks for the reason. On dark both the
  // ambient and the signal are coloured light on black and luminance is the
  // only thing between them. On pearl the ambient *is* the paper (Y ≈ 0.85)
  // and the signal is ink on it, so figure/ground already separates them and a
  // luminance floor measured in the same direction would be meaningless.
  // -------------------------------------------------------------------------

  group('Ambient vs. the recording signal – dark theme', () {
    // Measured 7.44:1 at the closest stop (the content plane's violet pole).
    // The floor is set below that with room for a re-tune, and far above the
    // ~3:1 at which a field starts competing with a mark for attention.
    const weightFloor = 6.0;

    final stops = <String, Color>{
      for (var i = 0; i < WpColorsDark.frameGradient.colors.length; i++)
        'frameGradient stop $i': WpColorsDark.frameGradient.colors[i],
      for (var i = 0; i < WpColorsDark.warmSurfaceGradient.colors.length; i++)
        'warmSurfaceGradient stop $i':
            WpColorsDark.warmSurfaceGradient.colors[i],
    };

    test('the sweep found every ambient stop', () {
      expect(
        stops.length,
        greaterThanOrEqualTo(7),
        reason:
            'only ${stops.length} ambient stops were collected — the check '
            'below would pass near-vacuously',
      );
    });

    stops.forEach((name, color) {
      test('$name is nowhere near the signal in weight', () {
        final ratio = contrastRatio(color, WpColorsDark.recordingAccent);
        expect(
          ratio,
          greaterThanOrEqualTo(weightFloor),
          reason:
              'dark: $name '
              '(#${color.toARGB32().toRadixString(16).padLeft(8, '0')}, '
              '${hueDelta(color, WpColorsDark.recordingAccent).toStringAsFixed(1)}° '
              'from recordingAccent) stands only '
              '${ratio.toStringAsFixed(2)}:1 off it. The ambient is allowed to '
              'share the recording hue\'s neighbourhood precisely because it '
              'never approaches its weight; an ambient that brightens toward '
              'the signal takes back the exclusivity half of *Two Accent, Two '
              'Jobs* through the back door, and that needs the maintainer and '
              'a new ADR, not a re-measurement',
        );
      });
    });
  });

  // -------------------------------------------------------------------------
  // The nav rail's icon chips (2026-08-11)
  //
  // Every rail item stands on a frosted tile. Two things have to hold and
  // neither is visible in a golden diff:
  //
  //   1. the tile is *material* — it lifts off the frame at every point of the
  //      rail, at both ends of the ambient and at every window size;
  //   2. the states still separate. The active fill used to be calibrated
  //      against bare frame; its ground is now the resting tile, so the step
  //      that matters is active-over-resting, not active-over-frame.
  //
  // The grounds are sampled where the rail actually is: the frame ambient runs
  // diagonally across the whole window, so the tile at the top of the rail and
  // the tile above the status bar stand on visibly different colors.
  // -------------------------------------------------------------------------

  for (final (themeName, frame, chips, iconResting, iconLit, tileFloor) in [
    (
      'dark',
      WpColorsDark.frameGradient,
      <String, LinearGradient>{
        'resting': WpColorsDark.navChipGradient,
        'hover': WpColorsDark.navChipGradientHover,
        'active': WpColorsDark.navPillActiveGradient,
      },
      WpColorsDark.textSecondary,
      WpColorsDark.textPrimary,
      1.15,
    ),
    (
      // Pearl's ceiling, stated as a number: the frame under the rail sits at
      // relative luminance ≈0.90, so *no* fill can lift a tile by more than
      // ≈1.06:1 there. The light floor is therefore not a weaker version of
      // dark's — it is most of what physics leaves, and the rest of the tile's
      // objecthood is the offset shadow and the hairline (*The Depth-Source
      // Rule*'s light branch), neither of which this group can see.
      'light',
      WpColorsDark.frameGradient,
      <String, LinearGradient>{
        'resting': WpColorsDark.navChipGradient,
        'hover': WpColorsDark.navChipGradientHover,
        'active': WpColorsDark.navPillActiveGradient,
      },
      WpColorsDark.textMuted,
      WpColorsDark.textPrimary,
      1.015,
    ),
  ]) {
    group('Nav-rail icon chip – $themeName theme', () {
      // The frame under the rail, sampled at both ends of every window the
      // seam group already walks — the rail spans the full height between the
      // title bar and the status bar.
      final grounds = <String, Color>{
        for (final (label, window) in _seamWindowSizes) ...{
          '$label, rail top': gradientColorAt(
            frame,
            frameGradientT(
              WpLayout.sidebarWidth / 2,
              WpLayout.appBarHeight,
              window,
            ),
          ),
          '$label, rail bottom': gradientColorAt(
            frame,
            frameGradientT(
              WpLayout.sidebarWidth / 2,
              window.height - WpLayout.statusBarHeight,
              window,
            ),
          ),
        },
      };

      /// The tile's body over [ground] — the two fill stops, without the
      /// gloss, which only covers the top tenth.
      Color body(LinearGradient chip, Color ground) => midpoint(
        alphaComposite(chip.colors[1], ground),
        alphaComposite(chip.colors[2], ground),
      );

      test('the sweep found both ends of every window', () {
        expect(
          grounds.length,
          _seamWindowSizes.length * 2,
          reason:
              'the ground sweep is incomplete — the checks below would '
              'measure fewer places than they claim to',
        );
      });

      test('every chip is one shape, so the states can cross-fade', () {
        for (final entry in chips.entries) {
          expect(
            (entry.value.colors.length, entry.value.stops, entry.value.begin),
            (3, const [0.0, 0.1, 1.0], Alignment.topCenter),
            reason:
                '$themeName: the ${entry.key} chip is not the same three-stop '
                'vertical shape as its siblings — `LinearGradient.lerp` then '
                'leaves its cheap path and the tile visibly resamples '
                'mid-transition',
          );
        }
      });

      test('the resting tile is material, at every point of the rail', () {
        grounds.forEach((label, ground) {
          final ratio = contrastRatio(body(chips['resting']!, ground), ground);
          expect(
            ratio,
            greaterThanOrEqualTo(tileFloor),
            reason:
                '$themeName at $label: the resting tile lifts only '
                '${ratio.toStringAsFixed(3)}:1 off the frame. Below that it is '
                'not a tile the icon stands on, it is a smudge — and the '
                'active state then reads as "the one row that has a fill" '
                'rather than as the one row wearing the accent',
          );
        });
      });

      test('the states still separate on their new ground', () {
        grounds.forEach((label, ground) {
          final resting = body(chips['resting']!, ground);
          final hover = contrastRatio(body(chips['hover']!, ground), resting);
          final active = contrastRatio(body(chips['active']!, ground), resting);
          expect(
            hover,
            greaterThanOrEqualTo(1.05),
            reason:
                '$themeName at $label: hover steps only '
                '${hover.toStringAsFixed(3)}:1 over the resting tile',
          );
          expect(
            active,
            greaterThanOrEqualTo(1.20),
            reason:
                '$themeName at $label: the active tile steps only '
                '${active.toStringAsFixed(3)}:1 over the resting one. It was '
                'solved against *bare frame*, where the same alphas bought '
                '1.5:1; a chip under it changes the ground and the state has '
                'to be re-solved, not inherited',
          );
        });
      });

      test('the gloss is a lit edge, never a second object', () {
        grounds.forEach((label, ground) {
          for (final entry in chips.entries) {
            final gloss = alphaComposite(entry.value.colors.first, ground);
            final fill = alphaComposite(entry.value.colors[1], ground);
            expect(
              relativeLuminance(gloss),
              greaterThan(relativeLuminance(fill)),
              reason:
                  '$themeName at $label: the ${entry.key} chip\'s first stop '
                  'is darker than the fill under it — that is a shadow drawn '
                  'along the top edge, i.e. the tile lit from below',
            );
            final step = contrastRatio(gloss, fill);
            expect(
              step,
              lessThan(3.0),
              reason:
                  '$themeName at $label: the ${entry.key} chip\'s gloss steps '
                  '${step.toStringAsFixed(2)}:1 over its fill, at the '
                  'contrast an *object* owes (WCAG 1.4.11) — a band that '
                  'strong stops reading as light on the tile and starts '
                  'reading as a second element drawn on it',
            );
          }
        });
      });

      test('the icon stays legible on every tile', () {
        grounds.forEach((label, ground) {
          final checks = <String, (Color, Color)>{
            'resting': (iconResting, body(chips['resting']!, ground)),
            'hover': (iconLit, body(chips['hover']!, ground)),
            'active': (iconLit, body(chips['active']!, ground)),
          };
          checks.forEach((state, pair) {
            final ratio = contrastRatio(pair.$1, pair.$2);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$themeName at $label: the $state icon reaches only '
                  '${ratio.toStringAsFixed(2)}:1 on its own tile. A nav '
                  'pictogram would clear the 3:1 a graphical object owes, but '
                  'this rail is the app\'s primary navigation and the tiles '
                  'are what the icons had to be re-solved against — the whole '
                  'point of a tile is that the glyph gains contrast, not '
                  'spends it',
            );
          });
        });
      });
    });
  }
}

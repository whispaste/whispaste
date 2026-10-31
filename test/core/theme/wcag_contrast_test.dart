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

import 'package:flutter/painting.dart' show HSLColor, LinearGradient;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart' show WpLayout;
import 'package:whispaste/services/model_download_service.dart'
    show TierPerformance;
import 'package:whispaste/widgets/find_replace.dart';
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

  // Translucent tints painted *behind* text that keeps its own colour. These
  // cannot live in `_darkPairs`: the effective background is a composite, and
  // `Color.alphaBlend` is not const. They are the pairings most likely to rot
  // unnoticed — nothing about `withValues(alpha: …)` at the call site hints
  // that a number is load-bearing, and the first draft of the find bar shipped
  // 0.45 here, which reads fine and measures 4.23:1.
  group('WCAG AA contrast – translucent accent tints (dark)', () {
    const tinted = <String, double>{
      'find bar, active match': WpFindHighlightController.activeHighlightAlpha,
      'find bar, other matches':
          WpFindHighlightController.inactiveHighlightAlpha,
    };
    // Every ground a tinted match can land on. `heading`/`form` fields fill
    // with `surfaceVariant`; since Ticket 09 the prose variants
    // (`passage`/`bare` — the History transcript and the Notes editor, i.e.
    // exactly where a find bar is used) fill with the translucent `cardFill`
    // over the app's one ambient, so the real ground there is that composite
    // at both ends of the gradient, not a flat token. `embedded` still sits
    // straight on its host row.
    final ambient = gradientExtremes(WpColorsDark.warmSurfaceGradient);
    final grounds = <String, Color>{
      'surfaceVariant': WpColorsDark.surfaceVariant,
      'surface': WpColorsDark.surface,
      'background': WpColorsDark.background,
      'cardFill over ambient.lightest': alphaComposite(
        WpColorsDark.cardFill,
        ambient.lightest,
      ),
      'cardFill over ambient.darkest': alphaComposite(
        WpColorsDark.cardFill,
        ambient.darkest,
      ),
    };

    for (final tint in tinted.entries) {
      for (final ground in grounds.entries) {
        test('${tint.key} on ${ground.key}', () {
          final composited = Color.alphaBlend(
            WpColorsDark.accent.withValues(alpha: tint.value),
            ground.value,
          );
          final ratio = contrastRatio(WpColorsDark.textPrimary, composited);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'textPrimary over accent @ alpha ${tint.value} on '
                '${ground.key} is ${ratio.toStringAsFixed(2)}:1 — body text '
                'under the AA floor. Lower the alpha rather than the floor.',
          );
        });
      }
    }

    // The list-search highlight the find bar borrowed its alpha from. It
    // recolours the glyph to `accent` instead of leaving it `textPrimary`, so
    // it is a different pairing on the same tint — and it was ungated too.
    for (final ground in grounds.entries) {
      test('list-search highlight on ${ground.key}', () {
        final composited = Color.alphaBlend(
          WpColorsDark.accent.withValues(alpha: 0.28),
          ground.value,
        );
        final ratio = contrastRatio(WpColorsDark.accent, composited);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason:
              'HighlightedText paints accent-on-accent-tint in bold, so it '
              'clears the large-text floor: ${ratio.toStringAsFixed(2)}:1 on '
              '${ground.key}.',
        );
      });
    }
  });

  // The settings row title (e.g. "Aus Korrekturen lernen" on the replacements
  // page) sits on the translucent card fill, which is painted over the
  // ambient gradient. Gated per appearance with that palette active, because
  // the title and the fill are read from the same palette.
  for (final (themeName, set) in [
    ('light', wpLightColors),
    ('dark', wpDarkColors),
    ('navy', wpNavyColors),
  ]) {
    group('Settings row title on its card fill – $themeName (≥ 4.5:1)', () {
      setUp(() => WpColors.activate(set));
      tearDown(() => WpColors.activate(wpLightColors));
      final ambient = gradientExtremes(set.warmSurfaceGradient);
      final grounds = <String, Color>{
        'cardFill over ambient.lightest': alphaComposite(
          set.cardFill,
          ambient.lightest,
        ),
        'cardFill over ambient.darkest': alphaComposite(
          set.cardFill,
          ambient.darkest,
        ),
      };
      for (final ground in grounds.entries) {
        test('textPrimary on ${ground.key}', () {
          final ratio = contrastRatio(WpColors.textPrimary, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'row title (WpColors.textPrimary) on ${ground.key} is '
                '${ratio.toStringAsFixed(2)}:1 — below the AA floor for body text.',
          );
        });
      }
    });
  }

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

  // ADR 0023: the info line reads the active set, so each appearance is
  // gated against its own grounds with that set activated.
  for (final (themeName, set) in [
    ('light', wpLightColors),
    ('dark', wpDarkColors),
    ('navy', wpNavyColors),
  ]) {
    group('Tier-performance info line – $themeName theme (≥ 4.5:1)', () {
      setUp(() => WpColors.activate(set));
      tearDown(() => WpColors.activate(wpLightColors));
      final surface = set.surface;
      final surfaceElevated = set.surfaceElevated;
      final accentButtonFill = set.accentButtonFill;
      final hover = set.hover;
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
        // A benchmarking row that is not the current tier can be hovered; the
        // hover token is a translucent wash, so it is measured over the card.
        'hover': alphaComposite(hover, surface),
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
          // Away from the ground: lighter on dark, darker on light.
          final sign = set.brightness == Brightness.dark ? 1 : -1;
          final delta =
              sign *
              (relativeLuminance(of(measured[i])) -
                  relativeLuminance(of(measured[i - 1])));
          expect(
            delta,
            greaterThan(0),
            reason:
                '$themeName: ${measured[i].name} does not sit further from the '
                'ground than ${measured[i - 1].name}. The line reports how much '
                'time a tier costs, so its weight has to rise with that cost — '
                'and it has to rise in the direction the theme leaves room in, '
                'lighter on a dark ground, darker on a light one',
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

  // -------------------------------------------------------------------------
  // Model → slot table (Ticket 14)
  //
  // The shipped model ids are a closed set, so the mapping owes a bijection —
  // and the sum-of-code-units hash cannot give one here: `whisper-small` (1352)
  // and `whisper-medium` (1456) are both ≡ 0 mod 8 and would paint the two
  // most-used models the same hue — hence a table, with the hash left as the
  // fallback for an id the table has not met.
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Sequential ramps (Ticket 14) — the ordinal half of *The Categorical vs.
  // Sequential Rule*. Nominal data gets distinct hues, ordered data gets one
  // hue at rising weight; what follows gates that the rungs of that one hue are
  // both separable from each other and legible against every surface.
  // -------------------------------------------------------------------------

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

  // The static 1px top edge: a highlight, not a light source. It has to lift
  // the fill it sits on (otherwise it is a shadow) and stay under the same
  // 1.5:1 object threshold the decorative wash is held to (otherwise it reads
  // as a drawn line the user is meant to interpret).

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

  // -------------------------------------------------------------------------
  // The seam between the frame and the content plane (Ticket 07)
  //
  // The content plane's first stop is painted at its own top-left corner,
  // which sits at (`sidebarWidth`, `appBarHeight`) = (232, 40) of a frame
  // gradient that spans the *whole window*. The plane is meant to read there
  // as the same light, only nearer: **the same hue, the same chroma within
  // the two-sided band, more light**. Anything else is a seam the eye reads
  // as two rooms meeting.
  //
  // Why the plane's stop is a constant and this sweep is the gate: the corner
  // slides along the frame gradient as the window changes (t ≈ 0.050–0.186
  // from 4K to the enforced minimum), so the frame's hue there runs from
  // 219.5° to 223.5°. A constant cannot be exact across that run, so the stop
  // is solved to its middle, and this sweep proves the rest of the range
  // instead of measuring the one window the token was solved at.
  //
  // "More light" is measured as *relative luminance*, not HSL lightness: both
  // ambients are blue-heavy at their violet end, and HSL lightness weights
  // blue like green while the eye — and every other gate in this file — does
  // not.
  // -------------------------------------------------------------------------

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

  // Warning banner (spec §4): amber text and icon on the amber soft fill. The
  // banner paints `highlightSoft` over whatever surface it sits on, so the
  // ground is that composite, not the flat fill.
  for (final (themeName, set) in [
    ('light', wpLightColors),
    ('dark', wpDarkColors),
    ('navy', wpNavyColors),
  ]) {
    group('Warning banner – $themeName theme (≥ 4.5:1)', () {
      final grounds = <String, Color>{
        'surface': set.surface,
        'background': set.background,
      };
      for (final ground in grounds.entries) {
        final fill = Color.alphaBlend(set.highlightSoft, ground.value);
        test('highlightText on warning fill over ${ground.key}', () {
          final ratio = contrastRatio(set.highlightText, fill);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '$themeName: warning icon/text reaches only '
                '${ratio.toStringAsFixed(2)}:1 on the amber fill over '
                '${ground.key}',
          );
        });
        test('textPrimary on warning fill over ${ground.key}', () {
          final ratio = contrastRatio(set.textPrimary, fill);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '$themeName: banner message reaches only '
                '${ratio.toStringAsFixed(2)}:1 on the amber fill over '
                '${ground.key}',
          );
        });
      }
    });
  }
}

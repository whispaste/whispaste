/// WhisPaste color palette — dark & light theme color definitions.
///
/// Calm, quiet palette with warm materiality: deep rich surfaces with a
/// single cyan accent, opaque dual-tone gradients for chromatic depth (see
/// `warmSurfaceGradient`), soft glass hints and crisp borders. No harsh
/// glow anywhere — depth comes from layered surfaces, tonal temperature
/// shifts, and soft shadows, never from alpha-blended light.
library;

import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';

import 'tokens.dart';

// ---------------------------------------------------------------------------
// Dark Theme Colors (Primary) — rich saturated navy tones, warm & unified
// ---------------------------------------------------------------------------
abstract final class WpColorsDark {
  /// Window frame — close to surface for unified monochrome feel
  static const Color background = Color(0xFF0F1320);

  /// Content surfaces — minimal step up from frame (≈ 2% lightness delta)
  static const Color surface = Color(0xFF141A29);

  /// Elevated panels, cards — richer blue tint
  static const Color surfaceElevated = Color(0xFF1B2336);

  /// Variant surface for alternate rows, secondary panels
  static const Color surfaceVariant = Color(0xFF232C40);
  static const Color hover = Color(0xFF212A40);

  /// Transparent version of hover for smooth AnimatedContainer transitions
  /// (prevents dark flash when interpolating from transparent to hover)
  static const Color hoverTransparent = Color(0x00212A40);
  static const Color active = Color(0xFF293352);

  static const Color borderSubtle = Color(0x1EFFFFFF);
  static const Color borderDefault = Color(0x30FFFFFF);

  /// Text — readable, not overly bright to avoid harshness
  static const Color textPrimary = Color(0xFFF0F4FA);
  static const Color textSecondary = Color(0xFFABB8CC);
  static const Color textMuted = Color(0xFF8A99B2);

  /// Vibrant cyan accent — highly saturated
  static const Color accent = Color(0xFF3CCBE6);
  static const Color accentHover = Color(0xFF66DBEE);
  static const Color accentSubtle = Color(0x2A3CCBE6);

  /// Instance-safe tint tokens: translucent fills/borders whose alpha lives in
  /// the *value*, used inside components that get reused as nested instances.
  /// Prefer them over inline `colour.withValues(...)` for component
  /// fills/borders.
  static const Color accentChipFill = Color(0x1A3CCBE6); // accent @ 10%
  static const Color accentChipFillHover = Color(0x2E3CCBE6); // accent @ 18%
  static const Color accentMiniTagFill = Color(0x1F3CCBE6); // accent @ 12%
  static const Color accentBorder30 = Color(0x4D3CCBE6); // accent @ 30%
  static const Color accentButtonFill = Color(0x143CCBE6); // accent @ 8%
  static const Color accentActiveFill = Color(0x1F3CCBE6); // accent @ 12%
  static const Color accentBadgeFill = Color(0x263CCBE6); // accent @ 15%
  static const Color accentBorder20 = Color(0x333CCBE6); // accent @ 20%
  static const Color accentRowHover = Color(0x0F3CCBE6); // accent @ 6%
  static const Color surfaceChipFill = Color(0x80141A29); // surface @ 50%
  static const Color surfaceMutedFill = Color(0x148A99B2); // textMuted @ 8%

  /// Saturated status colors — rich and warm
  static const Color success = Color(0xFF36D98B);
  static const Color warning = Color(0xFFF5C842);
  static const Color error = Color(0xFFFF7B7B);

  /// Danger/off-brand-neutral tint ladder — the same 6/8/12/20/30% alpha steps
  /// as the accent ladder above, keyed to [error]/[textMuted] instead, so a
  /// destructive or neutral control's hover, press and outline carry exactly
  /// the weight of an accent one's, only the hue differs.
  static const Color errorRowHover = Color(0x0FFF7B7B); // error @ 6%
  static const Color errorButtonFill = Color(0x14FF7B7B); // error @ 8%
  static const Color errorActiveFill = Color(0x1FFF7B7B); // error @ 12%
  static const Color errorBorder20 = Color(0x33FF7B7B); // error @ 20%
  static const Color errorBorder30 = Color(0x4DFF7B7B); // error @ 30%
  static const Color mutedRowHover = Color(0x0F8A99B2); // textMuted @ 6%
  static const Color mutedActiveFill = Color(0x1F8A99B2); // textMuted @ 12%

  /// Orange-600 — used for RAM/hardware preflight warnings.
  static const Color warningOrange = Color(0xFFEA580C);

  /// Solid red shades for destructive action buttons (e.g. quit CTA).
  static const Color errorRed = Color(0xFFDC2626);
  static const Color errorRedHover = Color(0xFFB91C1C);

  /// Watermark line color — ~3% white for subtle topographic depth.
  static const Color watermark = Color(0x08FFFFFF);

  /// Visible gradient for premium card/container backgrounds
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C2640), Color(0xFF141A29)],
  );

  /// Dual-tone temperature wash — cool navy top-left, neutral anchor,
  /// rose-coral-tinted warm navy bottom-right. Opaque tonal steps (no alpha
  /// glow): luminance stays flat across the gradient, only the hue drifts,
  /// so the content panel reads as chromatic *temperature*, not as light.
  /// The warm pole is a split-complement to `accent` (~190°), deliberately
  /// distinct from every avatar hue so it never reads as a second signal.
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF17203A), Color(0xFF141A29), Color(0xFF1E1A28)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Frame gradient — nearly flat, matching background for unified look
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF141928), Color(0xFF121726)],
  );

  /// Top accent line gradient
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF3CCBE6), Color(0xFF1AB5E0)],
  );

  /// Warm accent gradient — cyan to teal, rich and saturated
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3CCBE6), Color(0xFF14B8D4), Color(0xFF0A99B8)],
  );

  /// Nav-rail active pill — a *tonal* top-lit gradient on the existing accent,
  /// not a new hue: 20 % accent at the top stop falling to 12 % at the bottom.
  ///
  /// The mean (16 %) sits on top of the flat [accentSubtle] (16.5 %) it
  /// replaces, so the pill gains a lit top edge and a settled base without
  /// getting louder overall. Deliberately *not* [accentWarmGradient] — that
  /// one is opaque, and an opaque accent fill would swallow the accent-colored
  /// icon standing on it.
  static const LinearGradient navPillActiveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x333CCBE6), Color(0x1F3CCBE6)],
  );

  /// Glass tint — semi-transparent overlay for frosted panels
  static const Color glassTint = Color(0x18FFFFFF);

  /// Glass border — bright edge on frosted surfaces
  static const Color glassBorder = Color(0x24FFFFFF);
}

// ---------------------------------------------------------------------------
// Light Theme Colors
// ---------------------------------------------------------------------------
abstract final class WpColorsLight {
  /// Window frame — pearl-blue tint for brand identity; analogous to Dark's deep navy
  static const Color background = Color(0xFFE8EFF8);

  /// Content surfaces — cool pearl-white with visible cyan tint (not sterile white)
  static const Color surface = Color(0xFFF2F6FC);

  /// Elevated panels, cards — lighter than surface, still clearly tinted
  static const Color surfaceElevated = Color(0xFFF7FAFD);

  /// Variant surface for alternate rows, secondary panels
  static const Color surfaceVariant = Color(0xFFEBF1F8);
  static const Color hover = Color(0xFFE3EBF5);

  /// Transparent version of hover for smooth AnimatedContainer transitions
  /// (prevents flash when interpolating from transparent to hover)
  static const Color hoverTransparent = Color(0x00E3EBF5);
  static const Color active = Color(0xFFD5DFEE);

  static const Color borderSubtle = Color(0x140F172A);
  static const Color borderDefault = Color(0x24131F32);

  /// Strong text contrast for light theme
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF44556E);
  static const Color textMuted = Color(0xFF5B697E);

  /// Deep teal accent — analogous to Dark's #3CCBE6, darkened for WCAG AA on
  /// light (≥5.4:1 against both `surface` and `background`; the previous
  /// #0887A8 only reached ≈3.6-3.8:1, under the 4.5:1 AA floor for normal text).
  static const Color accent = Color(0xFF06678A);
  static const Color accentSubtle = Color(0x1C06678A); // accent @ 11%

  /// Instance-safe tint tokens — see [WpColorsDark.accentChipFill] for rationale.
  static const Color accentChipFill = Color(0x1A06678A); // accent @ 10%
  static const Color accentChipFillHover = Color(0x2E06678A); // accent @ 18%
  static const Color accentMiniTagFill = Color(0x1F06678A); // accent @ 12%
  static const Color accentBorder30 = Color(0x4D06678A); // accent @ 30%
  static const Color accentButtonFill = Color(0x1406678A); // accent @ 8%
  static const Color accentActiveFill = Color(0x1F06678A); // accent @ 12%
  static const Color accentBadgeFill = Color(0x2606678A); // accent @ 15%
  static const Color accentBorder20 = Color(0x3306678A); // accent @ 20%
  static const Color accentRowHover = Color(0x0F06678A); // accent @ 6%
  static const Color surfaceChipFill = Color(0x80F2F6FC); // surface @ 50%
  static const Color surfaceMutedFill = Color(0x145B697E); // textMuted @ 8%

  /// Danger/off-brand-neutral tint ladder — see [WpColorsDark.errorRowHover]
  /// for rationale.
  static const Color errorRowHover = Color(0x0FCC1C1C); // error @ 6%
  static const Color errorButtonFill = Color(0x14CC1C1C); // error @ 8%
  static const Color errorActiveFill = Color(0x1FCC1C1C); // error @ 12%
  static const Color errorBorder20 = Color(0x33CC1C1C); // error @ 20%
  static const Color errorBorder30 = Color(0x4DCC1C1C); // error @ 30%
  static const Color mutedRowHover = Color(0x0F5B697E); // textMuted @ 6%
  static const Color mutedActiveFill = Color(0x1F5B697E); // textMuted @ 12%

  static const Color success = Color(0xFF05875C);
  static const Color warning = Color(0xFFC97A06);
  static const Color error = Color(0xFFCC1C1C);

  /// Premium pearl-blue card gradient — subtle diagonal wash
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5F9FD), Color(0xFFEDF3FA)],
  );

  /// Dual-tone temperature wash — cool pearl top-left, neutral anchor,
  /// near-neutral pearl bottom-right. Mirrors [WpColorsDark.warmSurfaceGradient]
  /// in shape only: R/G/B stay within a few points of each other at every
  /// stop, so the drift reads as a tonal-luminance shift, not a color cast —
  /// neither a yellow/beige pole (B as channel minimum) nor a rose/magenta
  /// pole (G as channel minimum) survives here. Drift stays shallow,
  /// luminance flat: opaque tonal steps, no alpha glow.
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF2F7FC), Color(0xFFEFF3F9), Color(0xFFF1F1F5)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Frame gradient — matches background pearl-blue, subtle depth
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEAF1F9), Color(0xFFE6EDF7), Color(0xFFE5ECF6)],
    stops: [0.0, 0.48, 1.0],
  );

  /// Warm accent gradient — teal to deep teal, consistent with accent
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF06678A), Color(0xFF0E7490), Color(0xFF155E75)],
  );

  /// Nav-rail active pill — see [WpColorsDark.navPillActiveGradient].
  ///
  /// Light keeps its own, lower alpha pair (14 % → 8 %, mean 11 %) rather than
  /// reusing the dark stops: the deep-teal accent on a near-white pearl
  /// surface reads heavier per unit alpha than cyan on navy does. The mean
  /// again matches the flat [accentSubtle] (11 %) it replaces.
  static const LinearGradient navPillActiveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x2406678A), Color(0x1406678A)],
  );

  /// Glass tint — soft white overlay for light frosted panels
  static const Color glassTint = Color(0x80FFFFFF);

  /// Glass border — bright edge on frosted surfaces
  static const Color glassBorder = Color(0x40FFFFFF);

  /// Watermark line color — very faint slate tint for subtle topographic depth.
  static const Color watermark = Color(0x0A243B53);
}

// ---------------------------------------------------------------------------
// Reusable glass decoration builder
// ---------------------------------------------------------------------------

/// Theme-independent accents used identically in light and dark — a sanctioned
/// exception to the per-theme token split above, for colors chosen for
/// user-facing variety/recognition rather than surface hierarchy.
abstract final class WpSharedColors {
  /// Warm, distinguishable hues for hashing an identity to a color (history
  /// entry avatars, by title/id). Order matters — index 0 is the default.
  static const List<Color> avatarPalette = [
    Color(0xFF22D3EE), // cyan (default)
    Color(0xFF8B5CF6), // violet
    Color(0xFFF59E0B), // amber
    Color(0xFF10B981), // emerald
    Color(0xFFF472B6), // pink
    Color(0xFF3B82F6), // blue
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // teal
  ];

  /// Pinned/favorited-item accent (star icon, toggle). Amber reads as
  /// "favorite" cross-platform regardless of theme, like a star rating.
  static const Color pinnedAccent = Color(0xFFFFB300); // Colors.amber.shade600
}

/// Theme-paired rendering recipe for the history-entry avatar disc.
///
/// [WpSharedColors.avatarPalette] is deliberately theme-*independent*, so the
/// whole light/dark adaptation has to live in how a palette hue is prepared —
/// not in the hue itself. Every value below is therefore mirrored rather than
/// merely scaled: on dark the hue is pushed **toward light** and the fill kept
/// thin; on light it is pushed **toward ink** and the fill made *denser*, which
/// is the opposite of the usual "light theme needs less ink" compensation (that
/// rule exists for tokens whose base color already darkens per theme — this one
/// does not, so a thinner fill on pearl-white would simply erase the disc).
///
/// The lightness shifts are clamped into a legibility band. The band is what
/// keeps the recipe hue-agnostic: a pure shift drives already-dark hues
/// (emerald, teal) to near-black glyphs on light and washes pale hues out on
/// dark, so the band caps both ends without flattening the hues that sit in
/// between. On today's palette the dark bands never bind — they are a guard for
/// a future palette, not an active correction.
///
/// Calibrated against two contrast targets, verified per slot and per theme in
/// `test/core/theme/wcag_contrast_test.dart`:
/// * disc vs. `surface`/`surfaceElevated` ≥ 1.5:1 (WCAG 1.4.11, graphical
///   object) — the disc has to be *seen*;
/// * glyph vs. disc ≥ 3:1 — the icon has to be *read*.
///
/// Both targets pull against each other on light (a denser disc drags the glyph
/// further toward ink), which is why they are calibrated together.
final class WpAvatarTint {
  const WpAvatarTint._({
    required this.fillTopAlpha,
    required this.fillBottomAlpha,
    required this.edgeAlpha,
    required this.glyphAlpha,
    required this.fillLightnessShift,
    required this.fillLightnessMin,
    required this.fillLightnessMax,
    required this.topStopLightnessDelta,
    required this.glyphLightnessShift,
    required this.glyphLightnessMin,
    required this.glyphLightnessMax,
  });

  /// Alpha of the lit (top-left) gradient stop.
  final double fillTopAlpha;

  /// Alpha of the shaded (bottom-right) gradient stop.
  final double fillBottomAlpha;

  /// Alpha of the 1px hue-tinted rim.
  final double edgeAlpha;

  /// Alpha of the icon glyph.
  final double glyphAlpha;

  /// Lightness shift applied to the palette hue before it fills the disc.
  /// Positive on dark, negative on light — the mirror that makes the fill
  /// separate from its ground instead of dissolving into it.
  final double fillLightnessShift;

  /// Legibility band for the shifted fill lightness.
  final double fillLightnessMin;
  final double fillLightnessMax;

  /// Extra lightness delta of the lit stop over the shaded one. Carries the
  /// same sign as [fillLightnessShift]: "lit" means away from the ground.
  final double topStopLightnessDelta;

  /// Lightness shift applied to the palette hue for the glyph. Same sign as
  /// [fillLightnessShift] but larger, so the icon separates from the disc it
  /// sits on. Keep it clear of `fillLightnessShift + topStopLightnessDelta` —
  /// at equality the glyph and the lit stop collapse onto the same color and
  /// only their alphas still tell them apart.
  final double glyphLightnessShift;

  /// Legibility band for the shifted glyph lightness.
  final double glyphLightnessMin;
  final double glyphLightnessMax;

  /// Dark theme: thin fill, hue pushed lighter, glyph lighter still.
  static const WpAvatarTint dark = WpAvatarTint._(
    fillTopAlpha: 0.28,
    fillBottomAlpha: 0.20,
    edgeAlpha: 0.30,
    glyphAlpha: 0.95,
    fillLightnessShift: 0.12,
    fillLightnessMin: 0.45,
    fillLightnessMax: 0.86,
    topStopLightnessDelta: 0.12,
    glyphLightnessShift: 0.20,
    glyphLightnessMin: 0.55,
    glyphLightnessMax: 0.92,
  );

  /// Light theme: denser fill (not thinner), hue pushed toward ink, glyph
  /// darker still — every sign mirrored against [dark].
  static const WpAvatarTint light = WpAvatarTint._(
    fillTopAlpha: 0.36,
    fillBottomAlpha: 0.26,
    edgeAlpha: 0.44,
    glyphAlpha: 0.95,
    fillLightnessShift: -0.20,
    fillLightnessMin: 0.22,
    fillLightnessMax: 0.56,
    topStopLightnessDelta: -0.12,
    glyphLightnessShift: -0.36,
    glyphLightnessMin: 0.14,
    glyphLightnessMax: 0.34,
  );

  static WpAvatarTint of(bool isDark) => isDark ? dark : light;

  /// Lit (top-left) gradient stop for [base], alpha included.
  Color fillTop(Color base) => _shift(
    base,
    fillLightnessShift + topStopLightnessDelta,
    fillLightnessMin + topStopLightnessDelta,
    fillLightnessMax + topStopLightnessDelta,
  ).withValues(alpha: fillTopAlpha);

  /// Shaded (bottom-right) gradient stop for [base], alpha included.
  Color fillBottom(Color base) =>
      _fillBase(base).withValues(alpha: fillBottomAlpha);

  /// Hue-tinted rim for [base], alpha included.
  Color edge(Color base) => _fillBase(base).withValues(alpha: edgeAlpha);

  /// Icon color for [base], alpha included.
  Color glyph(Color base) => _shift(
    base,
    glyphLightnessShift,
    glyphLightnessMin,
    glyphLightnessMax,
  ).withValues(alpha: glyphAlpha);

  Color _fillBase(Color base) =>
      _shift(base, fillLightnessShift, fillLightnessMin, fillLightnessMax);

  static Color _shift(Color base, double delta, double min, double max) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(min, max).clamp(0.0, 1.0))
        .toColor();
  }
}

/// The translucent scrim behind a [BackdropFilter]-blurred dialog barrier.
///
/// Needs true black/white rather than a themed surface token — the blur
/// already carries the surface tint, this only needs to darken/lighten what
/// shows through it. Was duplicated verbatim across five dialog widgets.
Color wpDialogBarrierColor(bool isDark) {
  return (isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF))
      .withValues(alpha: isDark ? 0.45 : 0.35);
}

/// Creates a frosted-glass [BoxDecoration] suitable for cards and panels.
///
/// Subtle, not heavy — just enough to hint at depth and translucency.
/// Use with [ClipRRect] + [BackdropFilter] for the full glass effect.
BoxDecoration wpGlassDecoration({
  required bool isDark,
  BorderRadius? borderRadius,
  double borderOpacity = 1.0,
}) {
  return BoxDecoration(
    color: isDark ? WpColorsDark.glassTint : WpColorsLight.glassTint,
    borderRadius: borderRadius ?? WpRadius.borderMd,
    border: Border.all(
      color: (isDark ? WpColorsDark.glassBorder : WpColorsLight.glassBorder)
          .withValues(alpha: borderOpacity * (isDark ? 0.094 : 0.251)),
    ),
  );
}

/// A widget that applies a subtle frosted-glass effect to its child.
///
/// Wraps content in [ClipRRect] + [BackdropFilter] with a translucent tint.
/// The blur is deliberately light (sigmaX/Y = 12) for a premium, soft look.
class WpGlassPanel extends StatelessWidget {
  const WpGlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blurSigma = 12.0,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final br = borderRadius ?? WpRadius.borderMd;

    // On Windows frameless windows, BackdropFilter + ImageFilter.blur is
    // broken, so fall back to a solid opaque panel fill.
    final bool useBlur = !Platform.isWindows;

    final decoration = useBlur
        ? wpGlassDecoration(isDark: isDark, borderRadius: br)
        : wpGlassDecoration(isDark: isDark, borderRadius: br).copyWith(
            color: isDark
                ? WpColorsDark.surfaceElevated
                : WpColorsLight.surfaceElevated,
          );

    final content = Container(
      decoration: decoration,
      padding: padding,
      child: child,
    );

    return ClipRRect(
      borderRadius: br,
      child: useBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: content,
            )
          : content,
    );
  }
}

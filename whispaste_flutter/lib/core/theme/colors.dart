/// WhisPaste color palette — dark & light theme color definitions.
///
/// Premium palette: deep rich surfaces with cyan accent. Subtle glass hints
/// and warm gradients for emotional gaming-launcher feel. No harsh glow —
/// premium depth through frosted layers, soft gradients, and crisp borders.
library;

import 'dart:ui';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Dark Theme Colors (Primary) — warm navy-slate tones, NOT cold/harsh black
// ---------------------------------------------------------------------------
abstract final class WpColorsDark {
  /// Window frame — deep rich navy
  static const Color background = Color(0xFF0E1219);

  /// Content surfaces — clear lift from frame
  static const Color surface = Color(0xFF161B28);

  /// Elevated panels, cards — visible step up
  static const Color surfaceElevated = Color(0xFF1E2435);

  /// Variant surface for alternate rows, secondary panels
  static const Color surfaceVariant = Color(0xFF242A3C);
  static const Color hover = Color(0xFF222840);
  /// Transparent version of hover for smooth AnimatedContainer transitions
  /// (prevents dark flash when interpolating from transparent to hover)
  static const Color hoverTransparent = Color(0x00222840);
  static const Color active = Color(0xFF2A3148);

  static const Color borderSubtle = Color(0x1EFFFFFF);
  static const Color borderDefault = Color(0x30FFFFFF);
  static const Color borderAccent = Color(0x6022D3EE);

  /// High-contrast text — brighter for clear readability on dark surfaces
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFB4C0D0);
  static const Color textMuted = Color(0xFF94A3B8);

  /// Vibrant cyan accent — punchy and saturated
  static const Color accent = Color(0xFF4CE0F5);
  static const Color accentHover = Color(0xFF7AEDFB);
  static const Color accentSubtle = Color(0x2A4CE0F5);

  static const Color success = Color(0xFF6BEE9E);
  static const Color warning = Color(0xFFFCD34D);
  static const Color error = Color(0xFFFF8A8A);

  /// Visible gradient for premium card/container backgrounds
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C2438), Color(0xFF151B28)],
  );

  /// Warm surface gradient — VISIBLE diagonal wash with teal tint
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A2236), Color(0xFF161B28), Color(0xFF17202F)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Frame gradient — deeper separation from content
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF111620), Color(0xFF0C1017)],
  );

  /// Top accent line gradient
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF4CE0F5), Color(0xFF1AB5E0)],
  );

  /// Warm accent gradient — cyan to teal, rich and saturated
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4CE0F5), Color(0xFF14B8D4), Color(0xFF0A99B8)],
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
  static const Color background = Color(0xFFECF0F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F2F7);
  static const Color hover = Color(0xFFDFE4ED);
  static const Color hoverTransparent = Color(0x00DFE4ED);
  static const Color active = Color(0xFFCCD4E2);

  static const Color borderSubtle = Color(0x14000000);
  static const Color borderDefault = Color(0x22000000);
  static const Color borderAccent = Color(0x4A0891B2);

  /// Strong text contrast for light theme
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF3E4E66);
  static const Color textMuted = Color(0xFF566478);

  static const Color accent = Color(0xFF0887A8);
  static const Color accentHover = Color(0xFF0C6B87);
  static const Color accentSubtle = Color(0x1C0891B2);

  static const Color success = Color(0xFF05875C);
  static const Color warning = Color(0xFFC97A06);
  static const Color error = Color(0xFFCC1C1C);

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF3F0FF), Color(0xFFFFFFFF)],
  );

  /// Warm surface gradient — visible lavender-to-cyan wash
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEDE8FF), Color(0xFFFCFCFF), Color(0xFFE8F5FF)],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF0891B2), Color(0xFF0284C7)],
  );

  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0891B2), Color(0xFF0E7490), Color(0xFF155E75)],
  );

  /// Glass tint — soft white overlay for light frosted panels
  static const Color glassTint = Color(0x80FFFFFF);

  /// Glass border — bright edge on frosted surfaces
  static const Color glassBorder = Color(0x40FFFFFF);
}

// ---------------------------------------------------------------------------
// Reusable glass decoration builder
// ---------------------------------------------------------------------------

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
    borderRadius: borderRadius ?? BorderRadius.circular(10),
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
    final br = borderRadius ?? BorderRadius.circular(10);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: wpGlassDecoration(isDark: isDark, borderRadius: br),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

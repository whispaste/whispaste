/// WhisPaste color palette — dark & light theme color definitions.
///
/// Premium palette: deep rich surfaces with cyan accent. Subtle glass hints
/// and warm gradients for emotional gaming-launcher feel. No harsh glow —
/// premium depth through frosted layers, soft gradients, and crisp borders.
library;

import 'dart:ui';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Dark Theme Colors (Primary) — warm slate-blue tones, NOT cold black
// ---------------------------------------------------------------------------
abstract final class WpColorsDark {
  static const Color background = Color(0xFF0F1117);
  static const Color surface = Color(0xFF1E2130);
  static const Color surfaceElevated = Color(0xFF252A3A);
  static const Color surfaceVariant = Color(0xFF2E3348);
  static const Color hover = Color(0xFF2A2E3E);
  static const Color active = Color(0xFF333852);

  static const Color borderSubtle = Color(0x14FFFFFF);
  static const Color borderDefault = Color(0x24FFFFFF);
  static const Color borderAccent = Color(0x4D22D3EE);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color accent = Color(0xFF22D3EE);
  static const Color accentHover = Color(0xFF67E8F9);
  static const Color accentSubtle = Color(0x1E22D3EE);

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFF87171);

  /// Subtle gradient for premium card/container backgrounds
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF141820), Color(0xFF111418)],
  );

  /// Warm surface gradient — slate-blue wash for emotional depth
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E2130), Color(0xFF151825), Color(0xFF1A1E2E)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Top accent line gradient
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF22D3EE), Color(0xFF0EA5E9)],
  );

  /// Warm accent gradient — cyan to teal to slight purple
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22D3EE), Color(0xFF06B6D4), Color(0xFF0891B2)],
  );

  /// Glass tint — semi-transparent overlay for frosted panels
  static const Color glassTint = Color(0x0DFFFFFF);

  /// Glass border — bright edge on frosted surfaces
  static const Color glassBorder = Color(0x18FFFFFF);
}

// ---------------------------------------------------------------------------
// Light Theme Colors
// ---------------------------------------------------------------------------
abstract final class WpColorsLight {
  static const Color background = Color(0xFFF3F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF7F9FC);
  static const Color hover = Color(0xFFE8ECF2);
  static const Color active = Color(0xFFD5DCE6);

  static const Color borderSubtle = Color(0x0C000000);
  static const Color borderDefault = Color(0x18000000);
  static const Color borderAccent = Color(0x330891B2);

  static const Color textPrimary = Color(0xFF1A2030);
  static const Color textSecondary = Color(0xFF5A6880);
  static const Color textMuted = Color(0xFF8D99AE);

  static const Color accent = Color(0xFF0891B2);
  static const Color accentHover = Color(0xFF0E7490);
  static const Color accentSubtle = Color(0x140891B2);

  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FAFF), Color(0xFFFFFFFF)],
  );

  /// Warm surface gradient — soft lavender wash for emotional depth
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5F3FF), Color(0xFFFFFFFF), Color(0xFFF0FAFF)],
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

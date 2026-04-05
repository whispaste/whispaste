/// WhisPaste color palette — dark & light theme color definitions.
///
/// Premium palette: deep rich surfaces with cyan accent. No glow effects —
/// premium depth through layered surfaces, crisp borders, and subtle gradients.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Dark Theme Colors (Primary)
// ---------------------------------------------------------------------------
abstract final class WpColorsDark {
  static const Color background = Color(0xFF0A0D12);
  static const Color surface = Color(0xFF111418);
  static const Color surfaceElevated = Color(0xFF171B22);
  static const Color surfaceVariant = Color(0xFF1C2028);
  static const Color hover = Color(0xFF22262F);
  static const Color active = Color(0xFF282D38);

  static const Color borderSubtle = Color(0x12FFFFFF);
  static const Color borderDefault = Color(0x1EFFFFFF);
  static const Color borderAccent = Color(0x3322D3EE);

  static const Color textPrimary = Color(0xFFF0F2F5);
  static const Color textSecondary = Color(0xFF8C96A8);
  static const Color textMuted = Color(0xFF555E6E);

  static const Color accent = Color(0xFF22D3EE);
  static const Color accentHover = Color(0xFF06B6D4);
  static const Color accentSubtle = Color(0x1422D3EE);

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFF87171);

  /// Subtle gradient for premium card/container backgrounds
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF141820), Color(0xFF111418)],
  );

  /// Top accent line gradient
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF22D3EE), Color(0xFF0EA5E9)],
  );
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

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF0891B2), Color(0xFF0284C7)],
  );
}

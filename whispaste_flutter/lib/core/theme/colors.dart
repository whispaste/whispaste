/// WhisPaste color palette — dark & light theme color definitions.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Dark Theme Colors (Primary)
// ---------------------------------------------------------------------------
abstract final class WpColorsDark {
  static const Color background = Color(0xFF0B0E14);
  static const Color surface = Color(0xFF12161F);
  static const Color surfaceVariant = Color(0xFF1A1F2E);
  static const Color hover = Color(0xFF222838);
  static const Color active = Color(0xFF2A3145);

  static const Color borderSubtle = Color(0x0FFFFFFF); // 6%
  static const Color borderDefault = Color(0x1AFFFFFF); // 10%

  static const Color textPrimary = Color(0xFFE8ECF4);
  static const Color textSecondary = Color(0xFF8B95A8);
  static const Color textMuted = Color(0xFF5A6478);

  static const Color accent = Color(0xFF22D3EE);
  static const Color accentHover = Color(0xFF06B6D4);
  static const Color accentSubtle = Color(0x1F22D3EE); // 12%

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFF87171);
}

// ---------------------------------------------------------------------------
// Light Theme Colors
// ---------------------------------------------------------------------------
abstract final class WpColorsLight {
  static const Color background = Color(0xFFF1F5F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF8FAFC);
  static const Color hover = Color(0xFFE2E8F0);
  static const Color active = Color(0xFFCBD5E1);

  static const Color borderSubtle = Color(0x0F000000); // 6%
  static const Color borderDefault = Color(0x1A000000); // 10%

  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  static const Color accent = Color(0xFF0891B2);
  static const Color accentHover = Color(0xFF0E7490);
  static const Color accentSubtle = Color(0x1F0891B2);

  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
}

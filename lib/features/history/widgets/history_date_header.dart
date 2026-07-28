import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Date group header — ChatGPT-style time divider
// ---------------------------------------------------------------------------

class HistoryDateHeader extends StatelessWidget {
  const HistoryDateHeader({
    super.key,
    required this.label,
    required this.isDark,
  });

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    // Ruhiger als der frühere Doppellinien-Trenner: ein linksbündiges
    // Text-Label, wie HistoryCompactDateHeader es bereits macht — weniger
    // dekorativ, moderner.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.md,
        WpSpacing.xl,
        WpSpacing.xs,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: WpTypography.caption,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact date header — minimal text-only header
// ---------------------------------------------------------------------------

class HistoryCompactDateHeader extends StatelessWidget {
  const HistoryCompactDateHeader({
    super.key,
    required this.label,
    required this.isDark,
  });

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.sm,
        WpSpacing.xl,
        WpSpacing.xxs,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: WpTypography.micro,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        ),
      ),
    );
  }
}

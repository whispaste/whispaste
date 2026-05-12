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
    final lineColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.md,
        WpSpacing.xl,
        WpSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: lineColor)),
        ],
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
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        ),
      ),
    );
  }
}

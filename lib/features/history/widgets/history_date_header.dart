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
      // The date label is what turns a flat list into groups, but visually —
      // weight, letter-spacing, position. A screen reader gets none of that and
      // reads "Yesterday" as one more line of body text between two entries.
      // `header: true` restores the structure and, more importantly, makes the
      // groups jumpable by header navigation instead of row by row.
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: TextStyle(
            fontSize: WpTypography.caption,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: color,
          ),
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
      // Same reasoning as HistoryDateHeader above — the compact list groups by
      // the same dates and must be navigable the same way.
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: WpTypography.micro,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
          ),
        ),
      ),
    );
  }
}

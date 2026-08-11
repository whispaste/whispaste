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
    const color = WpColorsDark.textMuted;

    // Ruhiger als der frühere Doppellinien-Trenner: ein linksbündiges
    // Text-Label, wie HistoryCompactDateHeader es bereits macht — weniger
    // dekorativ, moderner.
    return Padding(
      // Vertical only. The enclosing list owns the horizontal page inset
      // (ticket 03, point 5) — carrying `xl` here too would double-pad the
      // headers against the rows they group.
      padding: const EdgeInsets.only(top: WpSpacing.md, bottom: WpSpacing.xs),
      // The date label is what turns a flat list into groups, but visually —
      // weight, letter-spacing, position. A screen reader gets none of that and
      // reads "Yesterday" as one more line of body text between two entries.
      // `header: true` restores the structure and, more importantly, makes the
      // groups jumpable by header navigation instead of row by row.
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: const TextStyle(
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
      // Vertical only — see HistoryDateHeader above.
      padding: const EdgeInsets.only(top: WpSpacing.sm, bottom: WpSpacing.xxs),
      // Same reasoning as HistoryDateHeader above — the compact list groups by
      // the same dates and must be navigable the same way.
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: WpTypography.micro,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: WpColorsDark.textMuted,
          ),
        ),
      ),
    );
  }
}

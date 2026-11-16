import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Which role a [WpAccentBadge] speaks for.
enum WpAccentBadgeTone {
  /// Cyan: a category the user can act on (imported, interactive).
  accent,

  /// Amber: a marker for something the app suggested, which the user should
  /// check (ticket spec §4: amber marks, never a button fill).
  highlight,

  /// Grey: a plain fact about the entry that asks for nothing, e.g. that the
  /// user typed it in by hand.
  muted,
}

/// Small tinted label pill that marks a list tile as belonging to a distinct
/// category (e.g. imported from a vocabulary folder, or an interactive
/// snippet) without a behavioural difference in the row itself.
class WpAccentBadge extends StatelessWidget {
  const WpAccentBadge({
    super.key,
    required this.label,
    this.tone = WpAccentBadgeTone.accent,
  });

  final String label;
  final WpAccentBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      WpAccentBadgeTone.accent => (WpColors.accentSubtle, WpColors.accent),
      WpAccentBadgeTone.highlight => (
        WpColors.highlightSoft,
        WpColors.highlightText,
      ),
      WpAccentBadgeTone.muted => (
        WpColors.surfaceMutedFill,
        WpColors.textSecondary,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: WpRadius.borderSm,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: WpTypography.caption,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Which role a [WpAccentBadge] speaks for.
enum WpAccentBadgeTone {
  /// Cyan: a category the user can act on (imported, interactive).
  accent,

  /// Amber: a marker for something the app suggested, which the user should
  /// check (WP-14 spec §4: amber marks, never a button fill).
  highlight,
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
    final highlight = tone == WpAccentBadgeTone.highlight;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: highlight ? WpColors.highlightSoft : WpColors.accentSubtle,
        borderRadius: WpRadius.borderSm,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlight ? WpColors.highlightText : WpColors.accent,
          fontSize: WpTypography.micro,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

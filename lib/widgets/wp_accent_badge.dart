import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Small accent-tinted label pill — used to mark a list tile as belonging to
/// a distinct category (e.g. imported from a vocabulary folder, or an
/// interactive snippet) without a behavioral difference in the row itself.
class WpAccentBadge extends StatelessWidget {
  const WpAccentBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: WpColors.accent.withValues(alpha: 0.12),
        borderRadius: WpRadius.borderSm,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WpColors.accent,
          fontSize: WpTypography.micro,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

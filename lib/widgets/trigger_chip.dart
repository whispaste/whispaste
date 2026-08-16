import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Small accent pill for a single trigger phrase inside a list tile — shared
/// by the Replacements settings page.
///
/// Already on the material Ticket 08 gave the other primitives, and left
/// unchanged by it: a translucent tinted fill, a translucent tinted rim, no
/// shadow, no gradient of its own. It is a *value* pill, not an interactive
/// one, so it keeps the accent rather than the frost — the accent is what says
/// "this is the trigger", and swapping it for the neutral card tint would
/// delete the only thing the chip communicates.
class WpTriggerChip extends StatelessWidget {
  const WpTriggerChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: WpSpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: WpColors.accentChipFill,
        borderRadius: BorderRadius.circular(WpRadius.full),
        border: Border.all(color: WpColors.accentBorder20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WpColors.accent,
          fontWeight: FontWeight.w600,
          fontSize: WpTypography.small,
        ),
      ),
    );
  }
}

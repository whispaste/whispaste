import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Small accent pill for a single trigger phrase inside a list tile — shared
/// by the Replacements settings page.
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
        color: WpColorsDark.accentChipFill,
        borderRadius: BorderRadius.circular(WpRadius.full),
        border: Border.all(color: WpColorsDark.accentBorder20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WpColorsDark.accent,
          fontWeight: FontWeight.w600,
          fontSize: WpTypography.small,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Small accent pill for a single trigger phrase inside a list tile — shared
/// by the Replacements and Automations settings pages.
class WpTriggerChip extends StatelessWidget {
  const WpTriggerChip({super.key, required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: WpSpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? WpColorsDark.accentChipFill
            : WpColorsLight.accentChipFill,
        borderRadius: BorderRadius.circular(WpRadius.full),
        border: Border.all(
          color: isDark
              ? WpColorsDark.accentBorder20
              : WpColorsLight.accentBorder20,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
          fontWeight: FontWeight.w600,
          fontSize: WpTypography.small,
        ),
      ),
    );
  }
}

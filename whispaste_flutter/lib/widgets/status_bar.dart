import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Bottom status bar — compact, refined chips showing app state.
///
/// Clean design: slim 34px bar, subtle chip styling, no visual noise.
class WpStatusBar extends StatelessWidget {
  const WpStatusBar({
    super.key,
    required this.modeLabel,
    required this.postProcessingLabel,
    this.hotkeyLabel,
    this.isOnline = true,
  });

  final String modeLabel;
  final String postProcessingLabel;
  final String? hotkeyLabel;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStyle = Theme.of(context).textTheme.labelSmall!;

    return Container(
      height: WpLayout.statusBarHeight,
      decoration: BoxDecoration(
        color: isDark ? WpColorsDark.surface : WpColorsLight.surface,
        border: Border(
          top: BorderSide(
            color: isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
      child: Row(
        children: [
          _StatusChip(
            icon: LucideIcons.cpu,
            label: modeLabel,
            textStyle: textStyle,
            isDark: isDark,
          ),
          const SizedBox(width: WpSpacing.xxs),
          _StatusChip(
            icon: LucideIcons.sparkles,
            label: postProcessingLabel,
            textStyle: textStyle,
            isDark: isDark,
          ),
          if (hotkeyLabel != null) ...[
            const SizedBox(width: WpSpacing.xxs),
            _StatusChip(
              icon: LucideIcons.keyboard,
              label: hotkeyLabel!,
              textStyle: textStyle,
              isDark: isDark,
            ),
          ],
          const Spacer(),
          // Connectivity dot + label
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant,
              borderRadius: WpRadius.borderFull,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? (isDark ? WpColorsDark.success : WpColorsLight.success)
                        : cs.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: textStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.textStyle,
    required this.isDark,
    this.icon,
  });

  final IconData? icon;
  final String label;
  final TextStyle textStyle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant,
        borderRadius: WpRadius.borderFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: cs.secondary),
            const SizedBox(width: 4),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}

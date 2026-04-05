import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Bottom status bar — sits on the app frame, full width.
///
/// Refined chips showing app state. Taller than before (42px) for readability.
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
      color: isDark ? WpColorsDark.background : WpColorsLight.background,
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
      child: Row(
        children: [
          _StatusChip(
            icon: LucideIcons.cpu,
            label: modeLabel,
            textStyle: textStyle,
            isDark: isDark,
          ),
          const SizedBox(width: WpSpacing.xs),
          _StatusChip(
            icon: LucideIcons.sparkles,
            label: postProcessingLabel,
            textStyle: textStyle,
            isDark: isDark,
          ),
          if (hotkeyLabel != null) ...[
            const SizedBox(width: WpSpacing.xs),
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
              horizontal: WpSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.surface.withValues(alpha: 0.5)
                  : WpColorsLight.surfaceVariant,
              borderRadius: WpRadius.borderFull,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? (isDark ? WpColorsDark.success : WpColorsLight.success)
                        : cs.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
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
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? WpColorsDark.surface.withValues(alpha: 0.5)
            : WpColorsLight.surfaceVariant,
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

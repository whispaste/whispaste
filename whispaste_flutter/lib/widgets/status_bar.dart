import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';

/// Bottom status bar with chips showing app state info.
///
/// Matches the design: slim bar at bottom with status chips,
/// hotkey hint, connectivity indicator.
class WpStatusBar extends StatelessWidget {
  const WpStatusBar({
    super.key,
    required this.modeLabel,
    required this.postProcessingLabel,
    this.hotkeyLabel,
    this.isOnline = true,
    this.onSponsorTap,
  });

  final String modeLabel;
  final String postProcessingLabel;
  final String? hotkeyLabel;
  final bool isOnline;
  final VoidCallback? onSponsorTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall!;

    return Container(
      height: WpLayout.statusBarHeight,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
      child: Row(
        children: [
          // Mode chip (Local / Cloud)
          _StatusChip(
            icon: Icons.dns_outlined,
            label: modeLabel,
            textStyle: textStyle,
            colorScheme: cs,
          ),
          const SizedBox(width: WpSpacing.xs),
          // Post-processing chip
          _StatusChip(
            icon: Icons.auto_fix_high_outlined,
            label: postProcessingLabel,
            textStyle: textStyle,
            colorScheme: cs,
          ),
          if (hotkeyLabel != null) ...[
            const SizedBox(width: WpSpacing.xs),
            _StatusChip(
              icon: Icons.keyboard_outlined,
              label: hotkeyLabel!,
              textStyle: textStyle,
              colorScheme: cs,
            ),
          ],
          const Spacer(),
          // Connectivity indicator
          _StatusChip(
            icon: null,
            label: isOnline ? 'Online' : 'Offline',
            textStyle: textStyle,
            colorScheme: cs,
            dotColor: isOnline ? const Color(0xFF34D399) : cs.error,
          ),
          if (onSponsorTap != null) ...[
            const SizedBox(width: WpSpacing.xs),
            IconButton(
              onPressed: onSponsorTap,
              icon: Icon(Icons.favorite_border, size: 16, color: cs.error),
              tooltip: 'Support WhisPaste',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.textStyle,
    required this.colorScheme,
    this.icon,
    this.dotColor,
  });

  final IconData? icon;
  final String label;
  final TextStyle textStyle;
  final ColorScheme colorScheme;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: WpSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.outlineVariant,
        borderRadius: WpRadius.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: colorScheme.secondary),
            const SizedBox(width: 4),
          ],
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}

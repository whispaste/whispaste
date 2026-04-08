import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Filter chip
// ---------------------------------------------------------------------------

class HistoryFilterChip extends StatefulWidget {
  const HistoryFilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.isDark,
    this.icon,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;
  final IconData? icon;

  @override
  State<HistoryFilterChip> createState() => _HistoryFilterChipState();
}

class _HistoryFilterChipState extends State<HistoryFilterChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    if (widget.isActive) {
      bg = widget.isDark
          ? WpColorsDark.accentSubtle
          : WpColorsLight.accentSubtle;
      fg = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    } else if (_isHovered) {
      bg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
      fg = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      bg = widget.isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant;
      fg = widget.isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderFull,
            border: widget.isActive
                ? Border.all(
                    color: (widget.isDark
                            ? WpColorsDark.accent
                            : WpColorsLight.accent)
                        .withValues(alpha: 0.3),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: WpIconSize.sm, color: fg),
                const SizedBox(width: WpSpacing.xxs),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

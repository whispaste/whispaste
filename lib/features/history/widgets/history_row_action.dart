import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Row action button (hover-only, used in entry rows)
// ---------------------------------------------------------------------------

class HistoryRowAction extends StatefulWidget {
  const HistoryRowAction({
    super.key,
    this.icon,
    this.faIcon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
    this.isDestructive = false,
    this.activeColor,
  }) : assert(icon != null || faIcon != null, 'Provide icon or faIcon');

  final IconData? icon;
  final FaIconData? faIcon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDestructive;
  /// When set, overrides the icon color regardless of hover/active state.
  final Color? activeColor;

  @override
  State<HistoryRowAction> createState() => _HistoryRowActionState();
}

class _HistoryRowActionState extends State<HistoryRowAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    if (widget.activeColor != null) {
      iconColor = widget.activeColor!;
    } else if (widget.isDestructive && _isHovered) {
      iconColor = widget.isDark ? WpColorsDark.error : WpColorsLight.error;
    } else if (_isHovered) {
      iconColor = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      iconColor = widget.isDark
          ? WpColorsDark.textMuted
          : WpColorsLight.textMuted;
    }

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xxs,
              vertical: WpSpacing.xxs,
            ),
            child: AnimatedContainer(
              duration: WpMotion.fast,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isHovered
                    ? (widget.isDark
                        ? WpColorsDark.active
                        : WpColorsLight.active)
                    : (widget.isDark
                        ? WpColorsDark.hoverTransparent
                        : WpColorsLight.hoverTransparent),
                borderRadius: WpRadius.borderSm,
              ),
              child: widget.faIcon != null
                  ? FaIcon(widget.faIcon!, size: 16, color: iconColor)
                  : Icon(widget.icon!, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

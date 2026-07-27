import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';

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
    this.count,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;
  final IconData? icon;

  /// Number of search hits for this filter. Shown as a badge when non-null.
  final int? count;

  @override
  State<HistoryFilterChip> createState() => _HistoryFilterChipState();
}

class _HistoryFilterChipState extends State<HistoryFilterChip> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'HistoryFilterChip');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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
      fg = widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    } else {
      bg = widget.isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant;
      fg = widget.isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary;
    }

    // Compact visual pill — the actual tap/focus surface around it is
    // stretched to WpLayout.minTouchTarget height by the InkWell below.
    final pill = AnimatedContainer(
      duration: WpMotion.durationFor(
        context,
        _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
      ),
      curve: WpMotion.defaultCurve,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: WpRadius.borderFull,
        border: widget.isActive
            ? Border.all(
                color: widget.isDark
                    ? WpColorsDark.accentBorder30
                    : WpColorsLight.accentBorder30,
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
              fontSize: WpTypography.body,
              height: 1.15,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (widget.count != null) ...[
            const SizedBox(width: 4),
            Text(
              '${widget.count}',
              style: TextStyle(
                color: (!widget.isActive && widget.count! > 0)
                    ? (widget.isDark
                          ? WpColorsDark.accent
                          : WpColorsLight.accent)
                    : fg.withValues(alpha: 0.6),
                fontSize: WpTypography.caption,
                height: 1.15,
                fontWeight: (!widget.isActive && widget.count! > 0)
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.isActive,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          focusNode: _focusNode,
          // WpFocusRing owns all focus visuals — suppress InkWell's own.
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: WpLayout.minTouchTarget,
            ),
            child: Center(
              // External-node mode: the ring hugs the compact pill while the
              // shared FocusNode lives on the taller InkWell surface.
              child: WpFocusRing(
                focusNode: _focusNode,
                radius: WpRadius.lg,
                child: pill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

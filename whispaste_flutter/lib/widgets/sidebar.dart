import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Navigation item data for the sidebar.
class WpNavItem {
  const WpNavItem({
    required this.id,
    required this.icon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final String label;
}

/// Premium left sidebar — icon-only rail with refined active state.
///
/// Clean design: thin accent indicator, subtle background shift on active,
/// smooth hover transitions. No glow effects.
class WpSidebar extends StatelessWidget {
  const WpSidebar({
    super.key,
    required this.items,
    required this.activeId,
    required this.onItemTap,
    this.bottomItems = const [],
  });

  final List<WpNavItem> items;
  final String activeId;
  final ValueChanged<String> onItemTap;
  final List<Widget> bottomItems;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: WpLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? WpColorsDark.surface : WpColorsLight.surface,
        border: Border(
          right: BorderSide(
            color: isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: WpSpacing.sm),
          // Brand mark — small accent line
          Container(
            width: 24,
            height: 3,
            decoration: BoxDecoration(
              gradient: isDark
                  ? WpColorsDark.accentGradient
                  : WpColorsLight.accentGradient,
              borderRadius: WpRadius.borderFull,
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          // Nav items
          ...items.map((item) => _NavItemWidget(
                item: item,
                isActive: item.id == activeId,
                onTap: () => onItemTap(item.id),
                isDark: isDark,
              )),
          const Spacer(),
          // Bottom items
          ...bottomItems,
          const SizedBox(height: WpSpacing.sm),
        ],
      ),
    );
  }
}

class _NavItemWidget extends StatefulWidget {
  const _NavItemWidget({
    required this.item,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  final WpNavItem item;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  @override
  State<_NavItemWidget> createState() => _NavItemWidgetState();
}

class _NavItemWidgetState extends State<_NavItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final iconColor = widget.isActive
        ? cs.primary
        : _isHovered
            ? cs.onSurface
            : cs.secondary;

    final bgColor = widget.isActive
        ? cs.primaryContainer
        : _isHovered
            ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
            : Colors.transparent;

    return Tooltip(
      message: widget.item.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            width: WpLayout.sidebarWidth,
            height: 44,
            child: Stack(
              children: [
                // Active indicator — crisp accent bar on left edge
                AnimatedPositioned(
                  duration: WpMotion.normal,
                  curve: WpMotion.defaultCurve,
                  left: 0,
                  top: widget.isActive ? 8 : 22,
                  bottom: widget.isActive ? 8 : 22,
                  child: AnimatedContainer(
                    duration: WpMotion.normal,
                    width: widget.isActive ? 3 : 0,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Icon with background pill
                Center(
                  child: AnimatedContainer(
                    duration: WpMotion.fast,
                    curve: WpMotion.defaultCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.sm,
                      vertical: WpSpacing.xxs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: WpRadius.borderSm,
                    ),
                    child: Icon(
                      widget.item.icon,
                      color: iconColor,
                      size: WpIconSize.md,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

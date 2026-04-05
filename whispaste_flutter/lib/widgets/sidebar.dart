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

/// Gaming-launcher sidebar — icon-only rail, seamless with content.
///
/// Inspired by Dixper/BottleNet: large icons, generous spacing,
/// same background as content, accent pill on active. No border.
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
      // Seamless — same background as content, no border
      color: isDark ? WpColorsDark.background : WpColorsLight.background,
      child: Column(
        children: [
          const SizedBox(height: WpSpacing.md),
          // Nav items — centered vertically with generous spacing
          ...items.map((item) => _NavItemWidget(
                item: item,
                isActive: item.id == activeId,
                onTap: () => onItemTap(item.id),
                isDark: isDark,
              )),
          const Spacer(),
          // Bottom items
          ...bottomItems,
          const SizedBox(height: WpSpacing.md),
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
    // Active: accent icon on accent-tinted pill
    // Hovered: lighter icon on subtle hover surface
    // Default: muted icon, transparent
    final Color iconColor;
    final Color bgColor;

    if (widget.isActive) {
      iconColor = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
      bgColor = widget.isDark
          ? WpColorsDark.accentSubtle
          : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      iconColor = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
      bgColor = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      iconColor = widget.isDark
          ? WpColorsDark.textMuted
          : WpColorsLight.textMuted;
      bgColor = Colors.transparent;
    }

    return Tooltip(
      message: widget.item.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            width: WpLayout.sidebarWidth,
            height: 52,
            child: Center(
              child: AnimatedContainer(
                duration: WpMotion.fast,
                curve: WpMotion.defaultCurve,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(WpRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  widget.item.icon,
                  color: iconColor,
                  size: WpIconSize.lg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

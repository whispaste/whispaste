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
/// Inspired by Dixper: icons positioned in upper portion (not dead center),
/// generous spacing, solid filled pill for active state. No glow effects.
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
      color: isDark ? WpColorsDark.background : WpColorsLight.background,
      child: Column(
        children: [
          // Icons in upper portion — shifted up from center like Dixper
          const SizedBox(height: WpSpacing.xl),
          // Nav items with generous spacing
          for (final item in items)
            _NavItemWidget(
              item: item,
              isActive: item.id == activeId,
              onTap: () => onItemTap(item.id),
              isDark: isDark,
            ),
          const Spacer(),
          // Bottom items pinned to bottom
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
    // Active: solid filled squircle with white icon (premium, high contrast)
    // Hovered: subtle elevated surface with lighter icon
    // Default: muted icon, transparent
    final Color iconColor;
    final Color bgColor;
    final Border? border;

    if (widget.isActive) {
      // Solid filled accent background — clean, premium, like Dixper's active
      iconColor = widget.isDark
          ? WpColorsDark.background
          : WpColorsLight.background;
      bgColor = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
      border = null;
    } else if (_isHovered) {
      iconColor = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
      bgColor = widget.isDark
          ? WpColorsDark.surfaceElevated
          : WpColorsLight.hover;
      border = Border.all(
        color: widget.isDark
            ? WpColorsDark.borderDefault
            : WpColorsLight.borderDefault,
      );
    } else {
      iconColor = widget.isDark
          ? WpColorsDark.textMuted
          : WpColorsLight.textMuted;
      bgColor = Colors.transparent;
      border = null;
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
          child: Padding(
            // Generous vertical spacing between icons (~10px gap)
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs - 2),
            child: SizedBox(
              width: WpLayout.sidebarWidth,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: WpMotion.fast,
                  curve: WpMotion.defaultCurve,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(WpRadius.md),
                    border: border,
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
      ),
    );
  }
}

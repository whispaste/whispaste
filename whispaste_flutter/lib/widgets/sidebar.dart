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

    return SizedBox(
      width: WpLayout.sidebarWidth,
      child: Column(
        children: [
          // Weighted spacers: ~40% above, ~60% below → slightly above center
          const Spacer(flex: 4),
          // Nav items with generous spacing
          for (final item in items)
            _NavItemWidget(
              item: item,
              isActive: item.id == activeId,
              onTap: () => onItemTap(item.id),
              isDark: isDark,
            ),
          const Spacer(flex: 6),
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
    // Active: accent-subtle bg + accent icon + left indicator bar
    // Hovered: simple bg-hover + text-primary — clean, like old app
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
          ? WpColorsDark.textSecondary
          : WpColorsLight.textMuted;
      bgColor = widget.isDark
          ? WpColorsDark.hoverTransparent
          : WpColorsLight.hoverTransparent;
    }

    return Semantics(
      label: widget.item.label,
      button: true,
      selected: widget.isActive,
      child: Tooltip(
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
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
            child: SizedBox(
              width: WpLayout.sidebarWidth,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Left accent indicator bar for active item
                  if (widget.isActive)
                    Positioned(
                      left: 0,
                      child: Container(
                        width: 3,
                        height: 22,
                        decoration: BoxDecoration(
                          gradient: widget.isDark
                              ? WpColorsDark.accentWarmGradient
                              : WpColorsLight.accentWarmGradient,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(WpRadius.sm),
                            bottomRight: Radius.circular(WpRadius.sm),
                          ),
                        ),
                      ),
                    ),
                   // Icon pill
                   AnimatedContainer(
                     duration: WpMotion.hoverIn,
                     curve: WpMotion.defaultCurve,
                     width: 38,
                     height: 38,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(WpRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.item.icon,
                      color: iconColor,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';

/// Navigation item data for the sidebar.
class WpNavItem {
  const WpNavItem({
    required this.id,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Left icon sidebar navigation (70px wide).
///
/// Matches the design system: dark surface, icon-only items with tooltip,
/// active indicator as thin accent bar on left edge.
class WpSidebar extends StatelessWidget {
  const WpSidebar({
    super.key,
    required this.items,
    required this.activeId,
    required this.onItemTap,
    this.bottomItems = const [],
    this.brandWidget,
  });

  final List<WpNavItem> items;
  final String activeId;
  final ValueChanged<String> onItemTap;
  final List<Widget> bottomItems;
  final Widget? brandWidget;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: WpLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          right: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: WpSpacing.md),
          // Brand icon
          if (brandWidget != null) ...[
            brandWidget!,
            const SizedBox(height: WpSpacing.lg),
          ],
          // Nav items
          ...items.map((item) => _NavItemWidget(
                item: item,
                isActive: item.id == activeId,
                onTap: () => onItemTap(item.id),
                isDark: isDark,
              )),
          const Spacer(),
          // Bottom items (theme toggle, lang toggle)
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
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: widget.item.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: WpMotion.normal,
            curve: WpMotion.defaultCurve,
            width: WpLayout.sidebarWidth,
            height: 48,
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: Stack(
              children: [
                // Active indicator — thin accent bar on left
                if (widget.isActive)
                  Positioned(
                    left: 0,
                    top: 10,
                    bottom: 10,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                // Icon centered
                Center(
                  child: AnimatedContainer(
                    duration: WpMotion.normal,
                    padding: const EdgeInsets.all(WpSpacing.xs),
                    decoration: BoxDecoration(
                      color: widget.isActive
                          ? cs.primaryContainer
                          : _isHovered
                              ? cs.outlineVariant
                              : Colors.transparent,
                      borderRadius: WpRadius.borderSm,
                    ),
                    child: Icon(
                      widget.isActive ? widget.item.activeIcon : widget.item.icon,
                      color: widget.isActive
                          ? cs.primary
                          : _isHovered
                              ? cs.onSurface
                              : cs.secondary,
                      size: 22,
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

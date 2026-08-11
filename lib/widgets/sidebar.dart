import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// Navigation item data for the sidebar.
class WpNavItem {
  const WpNavItem({
    required this.id,
    required this.icon,
    required this.label,
    this.badgeHint,
  });

  final String id;
  final IconData icon;
  final String label;

  /// Reason the attention dot is shown — e.g. "Version 1.2.3 verfügbar".
  ///
  /// Deliberately a sentence and not a `bool`: the dot itself is invisible to
  /// screen readers and meaningless to anyone who cannot guess what changed,
  /// so the badge only exists together with the phrase that explains it. When
  /// set, the phrase is appended to the item's tooltip *and* its semantics
  /// label; when null, no dot is painted and both stay byte-identical to a
  /// plain item.
  final String? badgeHint;
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
    this.dividerAfterIds = const <String>{},
  });

  final List<WpNavItem> items;
  final String activeId;
  final ValueChanged<String> onItemTap;

  /// Rail entries pinned to the bottom (e.g. Settings).
  ///
  /// Same type and same renderer as [items] — they only differ in where the
  /// rail puts them. They used to be arbitrary `Widget`s, which is how a
  /// second copy of the nav-item look grew its own RTL bug and its own
  /// vertical rhythm; there is now exactly one implementation.
  final List<WpNavItem> bottomItems;

  /// Item ids after which a subtle group divider is rendered.
  ///
  /// Empty by default, which reproduces the original flat rail exactly —
  /// callers opt in to grouping without affecting existing layouts.
  final Set<String> dividerAfterIds;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final column = Column(
      children: [
        // Weighted spacers: ~40% above, ~60% below → slightly above center
        const Spacer(flex: 4),
        // Nav items with generous spacing
        for (final item in items) ...[
          // loam-ignore: a11y-interactive-semantics – semantics provided in _NavItemWidget.build
          _NavItemWidget(
            item: item,
            isActive: item.id == activeId,
            onTap: () => onItemTap(item.id),
            isDark: isDark,
          ),
          if (dividerAfterIds.contains(item.id))
            _SidebarGroupDivider(isDark: isDark),
        ],
        const Spacer(flex: 6),
        // Bottom items pinned to bottom
        for (final item in bottomItems)
          // loam-ignore: a11y-interactive-semantics – semantics provided in _NavItemWidget.build
          _NavItemWidget(
            item: item,
            isActive: item.id == activeId,
            onTap: () => onItemTap(item.id),
            isDark: isDark,
          ),
        const SizedBox(height: WpNavRail.bottomInset),
      ],
    );

    return SizedBox(
      width: WpLayout.sidebarWidth,
      // The rail's decorative plate — one flat wash over the whole strip, the
      // same one the settings ground carries, and never varied per item (*The
      // Decorative Color Rule*). A `DecoratedBox` rather than a `Container`:
      // it adds no padding and no constraints of its own, so the rail's height
      // budget and its Spacer rhythm are exactly what they were.
      child: DecoratedBox(
        decoration: BoxDecoration(color: wpDecorativeChromeWash(isDark)),
        // Scroll fallback, second half of the height-budget fix (the first is
        // WpLayout.minWindowHeight). The rail's rows are fixed-height and its
        // spacers cannot go negative, so any window shorter than the rail
        // needs used to produce a hard RenderFlex overflow. `minimumSize` is
        // only a request — tiling window managers (sway/i3) ignore it
        // outright, and at fractional display scales the client area can land
        // a fraction of a dp short — so the rail has to survive being handed
        // less room than it asked for.
        //
        // No scrollbar: the rail *is* chrome, 72 dp wide and icon-only; a
        // track running down it would read as a second border on every page.
        // It also never appears in the normal case — with the minimum window
        // enforced, the scroll extent is zero and this whole branch is inert.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                // Keeps the Spacer rhythm intact whenever there *is* room: the
                // column still fills the rail's full height, and only grows
                // past it (into scrollable overflow) once the rows no longer
                // fit.
                constraints: BoxConstraints(
                  minHeight: constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : 0,
                ),
                // The scroll view offers unbounded height, which a Column with
                // Spacers cannot lay out in. IntrinsicHeight resolves the
                // column to its natural height (flex children contribute 0),
                // which the ConstrainedBox above then lifts back to the
                // available height whenever that is larger.
                child: IntrinsicHeight(child: column),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle horizontal hairline separating nav-item groups.
///
/// Purely decorative (no semantics, not focusable): narrower than the icon
/// pill so it reads as a quiet group break, not a full-width rule. Stays a
/// hairline rather than a tinted group plate — the rail's vertical budget is
/// already tight at the enforced minimum window size.
class _SidebarGroupDivider extends StatelessWidget {
  const _SidebarGroupDivider({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpNavRail.rowPadding),
      child: Container(
        width: WpNavRail.dividerWidth,
        height: WpNavRail.dividerThickness,
        // `borderDefault`, not `borderSubtle`: at 36 px wide and 1 px tall
        // between two icon groups, the subtle tone read as a rendering
        // artifact rather than as a deliberate break.
        color: isDark
            ? WpColorsDark.borderDefault
            : WpColorsLight.borderDefault,
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
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Active: tonal accent gradient + hairline + elevation, accent icon,
    //         reading-start indicator bar
    // Hovered: flat bg-hover + text-primary — clean, like old app
    // Default: muted icon, transparent
    //
    // Only the active pill lifts off the rail. Hover and idle stay flat on
    // purpose: elevation here means "this is where you are", and a rail where
    // the cursor also raises pills has two things claiming that meaning.
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

    // Everything the pill fills is routed through the *gradient* channel,
    // never `color`. `BoxDecoration.lerp` interpolates `color` and `gradient`
    // independently, so a `color -> gradient` cross-fade produces a frame
    // where both are non-null — which the BoxDecoration constructor asserts
    // against. Inactive states therefore use a flat two-stop gradient with
    // the same axis and stop count as the active one, which also keeps
    // `LinearGradient.lerp` on its cheap same-shape path.
    final Gradient pillGradient = widget.isActive
        ? (widget.isDark
              ? WpColorsDark.navPillActiveGradient
              : WpColorsLight.navPillActiveGradient)
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgColor, bgColor],
          );

    final Color accent = widget.isDark
        ? WpColorsDark.accent
        : WpColorsLight.accent;
    final String? badgeHint = widget.item.badgeHint;
    // The dot is decorative — it carries no semantics of its own, so the
    // reason it appeared has to travel in the label the item already has.
    final String description = badgeHint == null
        ? widget.item.label
        : '${widget.item.label}, $badgeHint';

    return Semantics(
      label: description,
      button: true,
      selected: widget.isActive,
      child: Tooltip(
        message: description,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.md,
            child: InkWell(
              onTap: widget.onTap,
              focusNode: _focusNode,
              // WpFocusRing owns all focus visuals — suppress InkWell's own.
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: WpNavRail.rowPadding,
                ),
                child: SizedBox(
                  width: WpNavRail.itemWidth,
                  height: WpNavRail.itemHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Accent indicator bar for active item.
                      // PositionedDirectional(start: 0) so it appears on the
                      // left in LTR and on the right in RTL (e.g. Hebrew).
                      if (widget.isActive)
                        PositionedDirectional(
                          start: 0,
                          child: Container(
                            width: WpNavRail.indicatorWidth,
                            height: WpNavRail.indicatorHeight,
                            decoration: BoxDecoration(
                              gradient: widget.isDark
                                  ? WpColorsDark.accentWarmGradient
                                  : WpColorsLight.accentWarmGradient,
                              // Directional, like the `start: 0` above it:
                              // the bar is flush with the window edge and
                              // rounds on its *inner* side. With the plain
                              // `topRight`/`bottomRight` it used to round on
                              // the outer edge in RTL (Hebrew) — the shape
                              // flipped while the position did not.
                              borderRadius: const BorderRadiusDirectional.only(
                                topEnd: Radius.circular(WpRadius.sm),
                                bottomEnd: Radius.circular(WpRadius.sm),
                              ),
                            ),
                          ),
                        ),
                      // Icon pill
                      AnimatedContainer(
                        duration: WpMotion.durationFor(
                          context,
                          WpMotion.hoverIn,
                        ),
                        curve: WpMotion.defaultCurve,
                        width: WpNavRail.pillSize,
                        height: WpNavRail.pillSize,
                        decoration: BoxDecoration(
                          gradient: pillGradient,
                          borderRadius: BorderRadius.circular(WpRadius.md),
                          // Always a 1 px border, only its colour animates —
                          // a null->Border cross-fade scales the *width* up
                          // from zero, which would nudge the glyph by half a
                          // pixel mid-transition.
                          border: Border.all(
                            color: widget.isActive
                                ? (widget.isDark
                                      ? WpColorsDark.accentBorder20
                                      : WpColorsLight.accentBorder20)
                                : Colors.transparent,
                          ),
                          // `subtleFor`, not the hardcoded dark-theme
                          // `subtle` — black-alpha shadows read far heavier
                          // over the pearl light surfaces. The off state is
                          // the alpha-0 twin rather than null, so toggling
                          // fades the ink out instead of shrinking it into a
                          // harder-edged patch for one frame.
                          boxShadow: widget.isActive
                              ? WpShadows.subtleFor(widget.isDark)
                              : WpShadows.subtleTransparent,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          widget.item.icon,
                          color: iconColor,
                          size: WpIconSize.md,
                        ),
                      ),
                      // Attention dot on the pill's reading-end top corner.
                      if (badgeHint != null)
                        PositionedDirectional(
                          top: WpNavRail.badgeTop,
                          end: WpNavRail.badgeEnd,
                          child: Container(
                            width: WpNavRail.badgeSize,
                            height: WpNavRail.badgeSize,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
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

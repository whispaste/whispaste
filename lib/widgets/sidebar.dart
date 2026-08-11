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
/// Icons positioned in the upper portion (not dead center), generous spacing,
/// and every icon on a frosted chip: a top-lit gradient tile with a
/// precomposited gloss, the active one tinted with the accent. The bloom is
/// fill, chroma and a lit edge — never a colored shadow at offset 0, which
/// *The Depth-Source Rule* forbids as a glow.
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
      // **The rail paints no ground.** It stands on the frame's diagonal
      // ambient, which runs on through the title bar above it and the status
      // bar below it as one light source — so any fill here, however quiet,
      // would cut a seam down the frame at x = 72 dp. It carried the
      // decorative chrome wash until Ticket 06; the wash's job was to make the
      // chrome its own plate, and `frameGradient` now does that itself and for
      // all three bars at once. See *The Decorative Color Rule* in
      // `lib/DESIGN.md` for the narrowing, and
      // `test/widgets/frame_single_paint_test.dart` for the gate.
      //
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
        color: WpColorsDark.borderDefault,
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
    // **Every item stands on a chip.** The tile is *material*, not a state:
    // a top-lit frost gradient with a precomposited gloss on its first tenth,
    // worn by resting, hovered and active items alike. That is what keeps the
    // accent-tinted tile the single marking of selection (*The One Highlight
    // Per State Rule*) — the rail no longer says "you are here" by being the
    // only row with a fill at all, it says it in the accent's hue.
    //
    // Active:  accent tile (36→25 % dark / 20→12 % light) + accent hairline +
    //          bright icon + reading-start indicator bar
    // Hovered: the same tile one step along (brighter on dark, deeper on
    //          pearl — the light theme has ~0.03 of luminance left above the
    //          resting tile and 1.07:1 below it) + text-primary icon
    // Resting: the frost tile + muted icon
    //
    // The icon on the active tile is `textPrimary`, not `accent`: the tile it
    // stands on is now accent-tinted, and an accent glyph on an accent fill
    // falls to ≈3.5:1 where a bright one holds ≈9:1. Selection is carried by
    // the tile's hue and the indicator bar; the glyph's job is to be legible.
    final Color iconColor;

    if (widget.isActive || _isHovered) {
      iconColor = WpColorsDark.textPrimary;
    } else {
      iconColor = WpColorsDark.textSecondary;
    }

    // Everything the chip fills is routed through the *gradient* channel,
    // never `color`. `BoxDecoration.lerp` interpolates `color` and `gradient`
    // independently, so a `color -> gradient` cross-fade produces a frame
    // where both are non-null — which the BoxDecoration constructor asserts
    // against. All three states are three-stop gradients on one axis with
    // identical stops, which also keeps `LinearGradient.lerp` on its cheap
    // same-shape path.
    final Gradient pillGradient = widget.isActive
        ? (WpColorsDark.navPillActiveGradient)
        : _isHovered
        ? (WpColorsDark.navChipGradientHover)
        : (WpColorsDark.navChipGradient);

    // The resting hairline: `borderSubtle` on dark, `borderDefault` on light.
    // Not a copy-paste slip — on pearl the tile has only ≈1.03:1 of fill lift
    // to work with, so the hairline is carrying objecthood there, the same
    // reason `_SidebarGroupDivider` below takes the default weight.
    final Color chipBorder = widget.isActive
        ? (WpColorsDark.accentBorder20)
        : (WpColorsDark.borderSubtle);

    const Color accent = WpColorsDark.accent;
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
                            decoration: const BoxDecoration(
                              gradient: WpColorsDark.accentWarmGradient,
                              // Directional, like the `start: 0` above it:
                              // the bar is flush with the window edge and
                              // rounds on its *inner* side. With the plain
                              // `topRight`/`bottomRight` it used to round on
                              // the outer edge in RTL (Hebrew) — the shape
                              // flipped while the position did not.
                              borderRadius: BorderRadiusDirectional.only(
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
                          border: Border.all(color: chipBorder),
                          // **One depth source per theme** (*The Depth-Source
                          // Rule*): on light the tile's lift is this offset
                          // shadow, worn by every chip in every state so
                          // nothing animates here; on dark it is the tile's
                          // own brightness delta against the frame and there
                          // is no shadow at all. The dark theme used to put
                          // `WpShadows.subtle` under the active pill alone —
                          // black ink on a near-black ground, which is the
                          // mud that rule exists to keep out, and it now sits
                          // on a frame saturated enough to show it.
                          boxShadow: null,
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
                            decoration: const BoxDecoration(
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

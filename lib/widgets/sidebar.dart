import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart' show WpTypeScaleTokens;
import '../core/theme/tokens.dart';
import 'brand_wordmark.dart';
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

/// Navigation sidebar of the app shell (chat-08, chat-10).
///
/// A 232 px column on the window frame: the brand lock-up at the top, then the
/// working areas with an outline icon and a label, a hairline between groups,
/// and the pinned bottom group. The active entry is a soft cyan fill with a
/// 3 px petrol bar on its reading-start edge; the label and icon take the
/// accent colour too, so selection never rests on colour alone.
///
/// At text scales above 1.0 the expanded column widens, up to
/// [WpNavRail.maxTextScaleWidthFactor] times its width, and labels wrap onto
/// further lines instead of being ellipsised (UX-033).
///
/// Below the shell's compact breakpoint (960 px) the sidebar collapses to an
/// icon-only rail ([compact]); every entry then keeps its label as tooltip.
///
/// The sidebar paints no ground of its own: it stands on the window frame
/// gradient painted by the shell, so the title bar, sidebar and frame read as
/// one surface.
class WpSidebar extends StatelessWidget {
  const WpSidebar({
    super.key,
    required this.items,
    required this.activeId,
    required this.onItemTap,
    this.bottomItems = const [],
    this.dividerAfterIds = const <String>{},
    this.compact = false,
  });

  /// Entries of the working areas, top to bottom.
  final List<WpNavItem> items;

  /// Id of the entry to show as selected.
  final String activeId;

  final ValueChanged<String> onItemTap;

  /// Entries pinned to the bottom (Hilfe, Einstellungen). Same type and same
  /// renderer as [items]; they differ only in where the rail places them.
  final List<WpNavItem> bottomItems;

  /// Item ids after which a group divider is drawn.
  final Set<String> dividerAfterIds;

  /// Icon-only rail below the compact breakpoint.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // UX-033: the expanded rail widens with the text scale (capped) so that
    // labels keep their words whole; the compact rail never grows.
    final growth = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, WpNavRail.maxTextScaleWidthFactor);
    final railWidth = compact
        ? WpLayout.sidebarWidthCompact
        : WpLayout.sidebarWidth * growth;
    final itemWidth = railWidth - 2 * WpNavRail.inset;

    return SizedBox(
      width: railWidth,
      // The rail must survive being handed less height than it asks for
      // (tiling window managers, fractional scales): when the rows no longer
      // fit, the column scrolls instead of overflowing. With the minimum
      // window height enforced the scroll extent is zero and this is inert.
      child: _RailScroll(
        children: [
          _BrandHeader(compact: compact),
          for (final item in items) ...[
            // loam-ignore: a11y-interactive-semantics – semantics provided in _NavItemWidget.build
            _NavItemWidget(
              item: item,
              isActive: item.id == activeId,
              compact: compact,
              itemWidth: itemWidth,
              onTap: () => onItemTap(item.id),
            ),
            if (dividerAfterIds.contains(item.id)) const _GroupDivider(),
          ],
          const Spacer(),
          if (bottomItems.isNotEmpty) const _GroupDivider(),
          for (final item in bottomItems)
            // loam-ignore: a11y-interactive-semantics – semantics provided in _NavItemWidget.build
            _NavItemWidget(
              item: item,
              isActive: item.id == activeId,
              compact: compact,
              itemWidth: itemWidth,
              onTap: () => onItemTap(item.id),
            ),
          const SizedBox(height: WpNavRail.bottomInset),
        ],
      ),
    );
  }
}

/// Scrollable column of the rail. The rail is chrome, so it shows no scrollbar
/// (see sidebar_height_budget_test); when the rows overflow the window, a short
/// fade marks the edge instead (UX-091), since the pinned Help and Settings
/// entries sit below the fold and would otherwise be invisible.
class _RailScroll extends StatefulWidget {
  const _RailScroll({required this.children});

  final List<Widget> children;

  @override
  State<_RailScroll> createState() => _RailScrollState();
}

class _RailScrollState extends State<_RailScroll> {
  final ScrollController _controller = ScrollController();
  bool _moreBelow = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.removeListener(_update);
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final more = _controller.position.extentAfter > 0.5;
    if (more != _moreBelow) setState(() => _moreBelow = more);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _update());
              return false;
            },
            child: SingleChildScrollView(
              controller: _controller,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : 0,
                ),
                child: IntrinsicHeight(
                  child: Column(children: widget.children),
                ),
              ),
            ),
          ),
        ),
        if (_moreBelow)
          Positioned(
            key: const ValueKey('sidebar-scroll-fade'),
            left: 0,
            right: 0,
            bottom: 0,
            height: WpSpacing.xl,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      WpColors.frame.background.withValues(alpha: 0),
                      WpColors.frame.background,
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Brand lock-up: the original artwork, never a re-typeset name. Expanded:
/// the full word-and-image mark; compact rail: the logo mark alone, centred.
/// Both use the variant drawn for the frame's brightness.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final onDark = WpColors.frame.brightness == Brightness.dark;
    final Widget art = compact
        ? Image.asset(
            onDark
                ? 'assets/icons/logo-dark.png'
                : 'assets/icons/logo-light.png',
            width: WpNavRail.brandHeight,
            height: WpNavRail.brandHeight,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          )
        : WpBrandWordmark(height: WpNavRail.brandHeight, onDark: onDark);

    return Semantics(
      label: 'WhisPaste',
      image: true,
      child: Padding(
        padding: compact
            ? const EdgeInsets.only(
                top: WpNavRail.brandTop,
                bottom: WpNavRail.brandGap,
              )
            : const EdgeInsetsDirectional.only(
                start: WpNavRail.inset + WpNavRail.contentStart,
                top: WpNavRail.brandTop,
                bottom: WpNavRail.brandGap,
              ),
        child: Align(
          alignment: compact
              ? Alignment.center
              : AlignmentDirectional.centerStart,
          child: art,
        ),
      ),
    );
  }
}

/// Hairline between two groups of entries.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: WpNavRail.groupBreakHeight,
      thickness: 1,
      indent: WpNavRail.inset + WpNavRail.contentStart,
      endIndent: WpNavRail.inset + WpSpacing.xs,
      color: WpColors.frame.borderSubtle,
    );
  }
}

class _NavItemWidget extends StatefulWidget {
  const _NavItemWidget({
    required this.item,
    required this.isActive,
    required this.compact,
    required this.itemWidth,
    required this.onTap,
  });

  final WpNavItem item;
  final bool isActive;
  final bool compact;
  final double itemWidth;
  final VoidCallback onTap;

  @override
  State<_NavItemWidget> createState() => _NavItemWidgetState();
}

class _NavItemWidgetState extends State<_NavItemWidget> {
  bool _isHovered = false;
  final _focusNode = FocusNode();
  final _tooltipKey = GlobalKey<TooltipState>();
  bool _shownByFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// On the icon-only rail the name is not on screen, so keyboard focus shows
  /// it as tooltip (hover alone did before; UX-010). Flutter keeps a tooltip
  /// shown by ensureTooltipVisible until it is dismissed, so losing focus must
  /// dismiss it again; only the tooltip focus itself opened is dismissed.
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (widget.compact) {
        _tooltipKey.currentState?.ensureTooltipVisible();
        _shownByFocus = true;
      }
    } else if (_shownByFocus) {
      _shownByFocus = false;
      Tooltip.dismissAllToolTips();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final active = widget.isActive;
    final badgeHint = item.badgeHint;
    // The dot is decorative: the reason it appeared travels in the label.
    final description = badgeHint == null
        ? item.label
        : '${item.label}, $badgeHint';

    final Color foreground = active
        ? WpColors.frame.accent
        : _isHovered
        ? WpColors.frame.textPrimary
        : WpColors.frame.textSecondary;
    final Color? fill = active
        ? WpColors.frame.accentActiveFill
        : _isHovered
        ? WpColors.frame.hover
        : null;

    final labelStyle = Theme.of(context).textTheme.bodyLarge!.copyWith(
      fontSize: WpTypeScaleTokens.bodyLg,
      fontWeight: FontWeight.w400,
      color: foreground,
    );

    final row = SizedBox(
      width: widget.compact ? WpNavRail.compactItemWidth : widget.itemWidth,
      child: Stack(
        children: [
          // Soft fill: the selection colour when active, a hover wash otherwise.
          Positioned.fill(
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.hoverIn),
              curve: WpMotion.defaultCurve,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(WpNavRail.activeRadius),
              ),
            ),
          ),
          // 3 px petrol bar on the reading-start edge (flips in RTL).
          if (active)
            PositionedDirectional(
              start: 0,
              top: WpSpacing.xs,
              bottom: WpSpacing.xs,
              child: Container(
                width: WpNavRail.indicatorWidth,
                decoration: BoxDecoration(
                  color: WpColors.frame.accent,
                  borderRadius: const BorderRadiusDirectional.horizontal(
                    end: Radius.circular(WpNavRail.indicatorWidth),
                  ),
                ),
              ),
            ),
          // Sizes the entry: at least the 44 px box (so icon and label sit on
          // its middle line), taller when a label wraps at a large text
          // scale. The label is never ellipsised (UX-033, WCAG 1.4.4).
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: WpNavRail.itemHeight),
            child: Padding(
              padding: widget.compact
                  ? EdgeInsets.zero
                  : const EdgeInsetsDirectional.only(
                      start: WpNavRail.contentStart,
                    ),
              child: Row(
                mainAxisAlignment: widget.compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(item.icon, size: WpNavRail.iconSize, color: foreground),
                  if (!widget.compact) ...[
                    const SizedBox(width: WpNavRail.iconLabelGap),
                    Flexible(child: Text(item.label, style: labelStyle)),
                  ],
                ],
              ),
            ),
          ),
          if (badgeHint != null)
            PositionedDirectional(
              top: WpSpacing.xs,
              end: WpSpacing.xs,
              child: Container(
                width: WpNavRail.badgeSize,
                height: WpNavRail.badgeSize,
                decoration: BoxDecoration(
                  color: WpColors.frame.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );

    final interactive = Semantics(
      label: description,
      button: true,
      selected: active,
      identifier: 'sidebar-nav-${item.id}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpNavRail.activeRadius,
          child: InkWell(
            key: ValueKey('sidebar-nav-${item.id}'),
            onTap: widget.onTap,
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(WpNavRail.activeRadius),
            // WpFocusRing owns the focus visuals; suppress InkWell's own.
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: ExcludeSemantics(child: row),
          ),
        ),
      ),
    );

    // Every entry keeps its tooltip, labelled or not: the tooltip is the
    // announcement of a badge reason, and the rail has always had it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpNavRail.inset,
        0,
        WpNavRail.inset,
        WpNavRail.itemGap,
      ),
      child: Tooltip(
        key: _tooltipKey,
        message: description,
        preferBelow: false,
        waitDuration: WpMotion.tooltipWait,
        child: interactive,
      ),
    );
  }
}

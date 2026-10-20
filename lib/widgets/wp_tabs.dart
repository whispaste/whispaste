import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

/// Text tabs for switching between sibling views of one page, e.g. the
/// sections of a detail page.
///
/// The selected tab is the accent colour with a 2 px underline; the others are
/// `textSecondary`. A 1 px `borderSubtle` rule runs under the whole row, so the
/// underline reads as belonging to the row, not floating over the content.
///
/// Keyboard: Left/Right move focus along the row (mirrored under RTL), Home and
/// End jump to the first and last tab. Focus only moves; Enter or Space selects
/// the focused tab, so a screen reader does not announce every stop.
///
/// Semantics: the row is a tab bar and each label a tab with its selected
/// state. When the labels are wider than the row, a chevron button appears on
/// each edge that has tabs out of view; a press scrolls one tab width further.
/// The chevrons are labelled buttons, but keyboard focus stays on the tabs,
/// which scroll into view by themselves. A vertical mouse wheel scrolls the row
/// sideways.
class WpTabs extends StatefulWidget {
  const WpTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.itemKeys = const [],
    this.itemIdentifiers = const [],
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Optional test keys, one per label (matched by index).
  final List<Key> itemKeys;

  /// Optional semantics identifiers, one per label (matched by index), for
  /// flows that address a tab without its localized label.
  final List<String> itemIdentifiers;

  @override
  State<WpTabs> createState() => _WpTabsState();
}

/// Hit width of each scroll chevron (WCAG 2.5.5 / 48 px touch target).
const double _kChevronHitWidth = 48;

class _WpTabsState extends State<WpTabs> {
  final List<FocusNode> _focusNodes = [];
  final ScrollController _scroll = ScrollController();

  /// Whether tabs lie beyond the leading or trailing edge.
  bool _overflowsStart = false;
  bool _overflowsEnd = false;

  /// Average width of one tab, the step of a chevron press.
  double _tabWidth = 0;

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
    _scroll.addListener(_updateOverflow);
  }

  @override
  void didUpdateWidget(WpTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _updateOverflow() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final start = position.pixels > 1;
    final end = position.maxScrollExtent - position.pixels > 1;
    final contentWidth = position.maxScrollExtent + position.viewportDimension;
    final tabWidth = widget.labels.isEmpty
        ? 0.0
        : contentWidth / widget.labels.length;
    if (start == _overflowsStart &&
        end == _overflowsEnd &&
        tabWidth == _tabWidth) {
      return;
    }
    setState(() {
      _overflowsStart = start;
      _overflowsEnd = end;
      _tabWidth = tabWidth;
    });
  }

  /// Scrolls by [delta] logical pixels, clamped to the row. Offsets are
  /// direction-agnostic here: under RTL the scroll origin is already mirrored.
  void _scrollBy(double delta, {bool animate = true}) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = (position.pixels + delta)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if (animate) {
      _scroll.animateTo(
        target,
        duration: WpMotion.normal,
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// Maps a vertical mouse wheel onto the horizontal row.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _scrollBy(dy, animate: false),
    );
  }

  void _syncFocusNodes() {
    while (_focusNodes.length < widget.labels.length) {
      _focusNodes.add(FocusNode(debugLabel: 'WpTab'));
    }
    while (_focusNodes.length > widget.labels.length) {
      _focusNodes.removeLast().dispose();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final count = _focusNodes.length;
    final current = _focusNodes.indexWhere((n) => n.hasFocus);
    if (count == 0 || current < 0) return KeyEventResult.ignored;

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final key = event.logicalKey;
    final int target;
    if (key == LogicalKeyboardKey.arrowRight) {
      target = (current + (rtl ? -1 : 1) + count) % count;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      target = (current + (rtl ? 1 : -1) + count) % count;
    } else if (key == LogicalKeyboardKey.home) {
      target = 0;
    } else if (key == LogicalKeyboardKey.end) {
      target = count - 1;
    } else {
      return KeyEventResult.ignored;
    }
    _focusNodes[target].requestFocus();
    final focused = _focusNodes[target].context;
    if (focused != null) {
      Scrollable.ensureVisible(focused, alignment: 0.5);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Re-measure after each layout, since the labels or the window width may
    // have changed the overflow.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverflow());
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: WpColors.borderSubtle)),
        ),
        // Scrolls sideways when the labels are wider than the row, so a narrow
        // window shows the first tabs and the rest one swipe away instead of
        // overflowing. Chevrons sit on the edges that still hide tabs.
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Listener(
                onPointerSignal: _onPointerSignal,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Semantics(
                      role: SemanticsRole.tabBar,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < widget.labels.length; i++)
                            _WpTab(
                              key: i < widget.itemKeys.length
                                  ? widget.itemKeys[i]
                                  : null,
                              identifier: i < widget.itemIdentifiers.length
                                  ? widget.itemIdentifiers[i]
                                  : null,
                              label: widget.labels[i],
                              selected: i == widget.selectedIndex,
                              focusNode: _focusNodes[i],
                              onTap: () => widget.onSelected(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_overflowsStart)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollChevron(
                    isStart: true,
                    label: L10n.of(context).tabsScrollBack,
                    testId: 'wp-tabs-scroll-start',
                    onTap: () => _scrollBy(-_tabWidth),
                  ),
                ),
              if (_overflowsEnd)
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollChevron(
                    isStart: false,
                    label: L10n.of(context).tabsScrollForward,
                    testId: 'wp-tabs-scroll-end',
                    onTap: () => _scrollBy(_tabWidth),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edge button that scrolls the tab row by one tab width. The icon matches the
/// text direction, so the start chevron points toward the start under RTL too.
class _ScrollChevron extends StatelessWidget {
  const _ScrollChevron({
    required this.isStart,
    required this.label,
    required this.testId,
    required this.onTap,
  });

  final bool isStart;
  final String label;
  final String testId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The start chevron points left in LTR and right in RTL, and vice versa.
    final pointsLeft = isStart != rtl;
    return Semantics(
      identifier: testId,
      label: label,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: _kChevronHitWidth,
        child: Material(
          color: WpColors.surface,
          child: InkWell(
            key: Key(testId),
            onTap: onTap,
            canRequestFocus: false,
            child: Center(
              child: Icon(
                pointsLeft ? Icons.chevron_left : Icons.chevron_right,
                size: WpIconSize.md,
                color: WpColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WpTab extends StatelessWidget {
  const _WpTab({
    super.key,
    this.identifier,
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onTap,
  });

  final String? identifier;
  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? WpColors.accent : WpColors.textSecondary;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      fontFamily: kWpUiFont,
      fontFamilyFallback: kWpFontFallback,
    );

    return Semantics(
      role: SemanticsRole.tab,
      selected: selected,
      identifier: identifier,
      // loam-ignore: a11y-interactive-semantics – the wrapped child keeps its own role and label; WpTouchTarget only enlarges the tap area and is excluded from semantics (see wp_touch_target.dart).
      child: WpTouchTarget(
        onTap: onTap,
        // The underline sits on the tab row's bottom edge, so the visual is
        // pinned there and the extra room opens above the label.
        alignment: Alignment.bottomCenter,
        child: WpFocusRing(
          focusNode: focusNode,
          radius: WpRadiusTokens.sm,
          child: InkWell(
            onTap: onTap,
            focusNode: focusNode,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2,
                    color: selected ? WpColors.accent : Colors.transparent,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.md,
                  vertical: WpSpacing.sm,
                ),
                child: Text(label, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

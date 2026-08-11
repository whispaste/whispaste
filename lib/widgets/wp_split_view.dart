/// Split view — resizable master/detail layout shared by every list area.
///
/// Owns the geometry (column widths, drag limits, the collapse to a
/// full-screen detail on narrow windows), the open/close animation and the
/// cross-fade between selected items. What the two columns *contain* is
/// entirely the caller's business, so history's view-mode switcher and notes'
/// editor panel stay in their own features.
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Split-view layout
// ---------------------------------------------------------------------------

/// Master/detail layout with a draggable divider.
///
/// [T] is the selected item itself, not its id: while the detail column is
/// animating closed, the view keeps rendering the item the caller has already
/// dropped from its selection — an id would no longer resolve.
class WpSplitView<T> extends StatefulWidget {
  const WpSplitView({
    super.key,
    required this.isDark,
    required this.selectedItem,
    required this.idOf,
    required this.listBuilder,
    required this.detailBuilder,
  });

  final bool isDark;

  /// The item whose detail column is open, or `null` for the list-only state.
  final T? selectedItem;

  /// Stable identity of an item — drives the cross-fade between two different
  /// selections (and only between *different* ones: an item updated in place
  /// keeps its id and therefore does not re-fade).
  final String Function(T item) idOf;

  /// Builds the left column. [selectedId] is `null` while no detail is open.
  final Widget Function(BuildContext context, String? selectedId) listBuilder;

  /// Builds the right column for [item].
  final Widget Function(BuildContext context, T item) detailBuilder;

  @override
  State<WpSplitView<T>> createState() => _WpSplitViewState<T>();
}

class _WpSplitViewState<T> extends State<WpSplitView<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _detailWidth;

  /// The last item the detail column showed — outlives
  /// [WpSplitView.selectedItem] for the length of the closing animation.
  T? _displayedItem;

  double _listWidth = _defaultListWidth;
  bool _isDragging = false;

  static const _defaultListWidth = 340.0;
  static const _minListWidth = 240.0;
  static const _maxListFraction = 0.65;
  static const _dividerHitWidth = 8.0;
  static const _dividerVisualWidth = 1.0;

  /// Minimum pixel width before the detail column actually renders its
  /// content. Below this threshold, the column shows nothing to prevent
  /// RenderFlex overflows during the open/close animation.
  static const _minDetailRenderWidth = 280.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: WpMotion.smooth);
    _detailWidth = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    if (widget.selectedItem != null) {
      _displayedItem = widget.selectedItem;
      _anim.value = 1.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _anim.duration = WpMotion.durationFor(context, WpMotion.smooth);
  }

  @override
  void didUpdateWidget(covariant WpSplitView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedItem != null && oldWidget.selectedItem == null) {
      // Opening the detail column
      _displayedItem = widget.selectedItem;
      _anim.forward();
    } else if (widget.selectedItem == null && oldWidget.selectedItem != null) {
      // Closing the detail column
      _anim.reverse().then((_) {
        if (mounted) setState(() => _displayedItem = null);
      });
    } else if (widget.selectedItem != null) {
      // Switching to a different item (or the same item updated by a stream)
      _displayedItem = widget.selectedItem;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String? get _visibleId {
    final item = widget.selectedItem ?? _displayedItem;
    return item == null ? null : widget.idOf(item);
  }

  /// Keyed here rather than at the call sites so the cross-fade below cannot
  /// silently stop working when a caller forgets to key its panel.
  Widget _buildDetail(BuildContext context, T item) => KeyedSubtree(
    key: ValueKey(widget.idOf(item)),
    child: widget.detailBuilder(context, item),
  );

  @override
  Widget build(BuildContext context) {
    final showDetail = widget.selectedItem != null || _displayedItem != null;

    if (!showDetail) {
      return widget.listBuilder(context, null);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final isCompact = totalWidth < WpLayout.breakpointMobile;

        // ── Compact: full-screen detail overlay ──
        if (isCompact) {
          final item = widget.selectedItem ?? _displayedItem;
          if (item != null && widget.selectedItem != null) {
            return _buildDetail(context, item);
          }
          return widget.listBuilder(context, _visibleId);
        }

        // ── Desktop: side-by-side list + detail ──
        // When detail is open, cap the list column so the detail gets at
        // least _minDetailRenderWidth. If there's not enough total space for
        // both columns, fall back to compact/fullscreen detail.
        final roomForDetail = totalWidth - _minListWidth - _dividerHitWidth;
        if (roomForDetail < _minDetailRenderWidth &&
            widget.selectedItem != null) {
          // Not enough room for split — show full-screen detail.
          return _buildDetail(
            context,
            widget.selectedItem ?? _displayedItem as T,
          );
        }

        final maxListW = totalWidth * _maxListFraction;
        // Ensure the list column never eats so much that detail can't render.
        final maxListForDetail =
            totalWidth - _dividerHitWidth - _minDetailRenderWidth;
        return AnimatedBuilder(
          animation: _detailWidth,
          builder: (context, _) {
            final detailFraction = _detailWidth.value;
            final effectiveList = _listWidth.clamp(
              _minListWidth,
              detailFraction > 0.05
                  ? maxListForDetail.clamp(_minListWidth, maxListW)
                  : maxListW,
            );
            final detailW =
                (totalWidth - effectiveList - _dividerHitWidth) *
                detailFraction;
            final listW = totalWidth - detailW - _dividerHitWidth;

            return Row(
              children: [
                SizedBox(
                  width: listW.clamp(effectiveList, totalWidth),
                  child: widget.listBuilder(context, _visibleId),
                ),
                // Draggable divider
                _SplitViewDivider(
                  isDark: widget.isDark,
                  isDragging: _isDragging,
                  hitWidth: _dividerHitWidth,
                  visualWidth: _dividerVisualWidth,
                  dragMax: detailFraction > 0.05
                      ? maxListForDetail.clamp(_minListWidth, maxListW)
                      : maxListW,
                  minListWidth: _minListWidth,
                  currentListWidth: _listWidth,
                  onDragStart: () => setState(() => _isDragging = true),
                  onDragUpdate: (newWidth) =>
                      setState(() => _listWidth = newWidth),
                  onDragEnd: () => setState(() => _isDragging = false),
                ),
                SizedBox(
                  width: detailW.clamp(0.0, totalWidth - _minListWidth),
                  child:
                      detailFraction > 0.05 && detailW >= _minDetailRenderWidth
                      ? ClipRect(
                          child: Opacity(
                            opacity: detailFraction.clamp(0.0, 1.0),
                            child: AnimatedSwitcher(
                              duration: WpMotion.durationFor(
                                context,
                                WpMotion.fast,
                              ),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                              child: _buildDetail(
                                context,
                                widget.selectedItem ?? _displayedItem as T,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Draggable column divider for the split view
// ---------------------------------------------------------------------------

class _SplitViewDivider extends StatelessWidget {
  const _SplitViewDivider({
    required this.isDark,
    required this.isDragging,
    required this.hitWidth,
    required this.visualWidth,
    required this.dragMax,
    required this.minListWidth,
    required this.currentListWidth,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final bool isDark;
  final bool isDragging;
  final double hitWidth;
  final double visualWidth;
  final double dragMax;
  final double minListWidth;
  final double currentListWidth;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragUpdate: (details) {
          final newWidth = (currentListWidth + details.delta.dx).clamp(
            minListWidth,
            dragMax,
          );
          onDragUpdate(newWidth);
        },
        onHorizontalDragEnd: (_) => onDragEnd(),
        child: Container(
          width: hitWidth,
          color: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              // Off-scale on purpose: the divider's thickening under the
              // cursor is a pointer affordance, not a UI transition, and
              // reads as lag at WpMotion.fast.
              duration: WpMotion.durationFor(
                context,
                const Duration(milliseconds: 150),
              ),
              width: isDragging ? 3.0 : visualWidth,
              decoration: BoxDecoration(
                color: isDragging
                    ? (WpColors.accent.withValues(alpha: 0.5))
                    : (WpColors.borderSubtle),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

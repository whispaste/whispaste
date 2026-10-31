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
    required this.selectedItem,
    required this.idOf,
    required this.listBuilder,
    required this.detailBuilder,
    this.crossFadeDetail = true,
  });

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

  /// Whether switching to a different item cross-fades the detail column.
  ///
  /// The fade keeps both panels mounted for its duration. That is fine for a
  /// read-only detail view, and wrong for one holding a text field whose
  /// [TextEditingController]/[FocusNode] the *caller* owns: the two panels
  /// then race over the platform text-input connection and over which one
  /// holds the node's [FocusAttachment] — and detaching a focused node drops
  /// its pending focus notification, leaving a field that paints a focus ring
  /// it cannot type into. Pass `false` there; the single panel is updated in
  /// place instead.
  final bool crossFadeDetail;

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

  /// Narrowest window that still shows the list and the detail side by side.
  /// Below it the detail takes the full width (focused detail).
  static const _splitMinWidth =
      _minListWidth + _dividerHitWidth + WpLayout.minReadableDetailWidth;

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
  /// silently stop working when a caller forgets to key its panel. The stable
  /// key under [WpSplitView.crossFadeDetail] `false` is the same lever used
  /// the other way: one key for every item means the [AnimatedSwitcher] never
  /// sees a new child and reuses the one element.
  Widget _buildDetail(BuildContext context, T item) => KeyedSubtree(
    key: widget.crossFadeDetail
        ? ValueKey<String>(widget.idOf(item))
        : const ValueKey<String>('detail'),
    child: widget.detailBuilder(context, item),
  );

  @override
  Widget build(BuildContext context) {
    final showDetail = widget.selectedItem != null || _displayedItem != null;

    // One Stack with the same three Positioned children in every state: the
    // list is always child 0, so its element — and with it its scroll offset
    // and its own state — survives opening, closing and resizing the detail.
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final isSplit = totalWidth >= _splitMinWidth;
        // Narrow window with a selection: the detail takes the full width
        // and the list is kept mounted but hidden.
        final isFocusedDetail = !isSplit && widget.selectedItem != null;

        return AnimatedBuilder(
          animation: _detailWidth,
          builder: (context, _) {
            final detailFraction = isSplit ? _detailWidth.value : 0.0;
            // The list column is capped so the detail keeps at least
            // WpLayout.minReadableDetailWidth while it is open.
            final maxListW = totalWidth * _maxListFraction;
            final maxListForDetail =
                totalWidth - _dividerHitWidth - WpLayout.minReadableDetailWidth;
            final dragMax = detailFraction > 0.05
                ? maxListForDetail.clamp(_minListWidth, maxListW)
                : maxListW;

            final double listW;
            final double dividerW;
            final double detailW;
            if (isFocusedDetail) {
              listW = totalWidth;
              dividerW = 0;
              detailW = totalWidth;
            } else if (!isSplit) {
              listW = totalWidth;
              dividerW = 0;
              detailW = 0;
            } else {
              // ── Desktop: side-by-side list + detail ──
              final effectiveList = _listWidth.clamp(_minListWidth, dragMax);
              dividerW = showDetail ? _dividerHitWidth : 0;
              detailW =
                  (totalWidth - effectiveList - dividerW) * detailFraction;
              listW = (totalWidth - detailW - dividerW).clamp(
                effectiveList,
                totalWidth,
              );
            }
            final detailBoxW = detailW.clamp(0.0, totalWidth - _minListWidth);
            final detailLeft = listW + dividerW;

            final Widget detail;
            if (isFocusedDetail) {
              detail = _buildDetail(context, widget.selectedItem as T);
            } else if (isSplit &&
                detailFraction > 0.05 &&
                detailW >= _minDetailRenderWidth) {
              detail = ClipRect(
                child: Opacity(
                  opacity: detailFraction.clamp(0.0, 1.0),
                  child: AnimatedSwitcher(
                    duration: WpMotion.durationFor(context, WpMotion.fast),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _buildDetail(
                      context,
                      widget.selectedItem ?? _displayedItem as T,
                    ),
                  ),
                ),
              );
            } else {
              detail = const SizedBox.shrink();
            }

            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: listW,
                  child: Offstage(
                    offstage: isFocusedDetail,
                    child: ExcludeFocus(
                      excluding: isFocusedDetail,
                      child: widget.listBuilder(context, _visibleId),
                    ),
                  ),
                ),
                Positioned(
                  left: listW,
                  top: 0,
                  bottom: 0,
                  width: dividerW,
                  child: dividerW > 0
                      ? _SplitViewDivider(
                          isDragging: _isDragging,
                          hitWidth: _dividerHitWidth,
                          visualWidth: _dividerVisualWidth,
                          dragMax: dragMax,
                          minListWidth: _minListWidth,
                          currentListWidth: _listWidth,
                          onDragStart: () => setState(() => _isDragging = true),
                          onDragUpdate: (newWidth) =>
                              setState(() => _listWidth = newWidth),
                          onDragEnd: () => setState(() => _isDragging = false),
                        )
                      : const SizedBox.shrink(),
                ),
                Positioned(
                  left: detailLeft,
                  top: 0,
                  bottom: 0,
                  width: detailBoxW,
                  child: detail,
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
              duration: WpMotion.durationFor(context, WpMotion.fast),
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

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A column in which one child ([WpFillSlot]) takes the height the others
/// leave, but never less than its minimum (#1371).
///
/// A `Column` with an `Expanded` child overflows once the fixed rows (an
/// editor's tool row and status line, the pane's head and footer) need more
/// than the height there is: at 200 % text size in a short window that cut
/// off the bottom of every editor. This column instead grows past the height
/// it was given, so a `SingleChildScrollView` around it scrolls, and in a
/// tall enough window it looks exactly like the `Column` it replaces.
///
/// The fill child gets `max(minimum, available - rest)`, where `available`
/// is [viewportExtent] (the height outside a surrounding scroll view, which
/// itself passes an unbounded height) or else the incoming maximum height.
/// Its minimum is [minFillExtent], and with [WpFillSlot.probe] at least the
/// height it takes when laid out without a height limit: a nested
/// [WpFillColumn] answers that with its own minimum, so the minimums of
/// pane, editor and writing surface add up.
///
/// Laid out with an unbounded height and no [viewportExtent], the column is
/// as tall as its minimum. The children are stretched to the full width.
class WpFillColumn extends MultiChildRenderObjectWidget {
  const WpFillColumn({
    super.key,
    this.viewportExtent,
    this.minFillExtent = 0,
    required super.children,
  });

  /// The height to fill when the incoming one is unbounded (inside a scroll
  /// view, the viewport's height).
  final double? viewportExtent;

  /// The least height of the [WpFillSlot] child.
  final double minFillExtent;

  @override
  WpRenderFillColumn createRenderObject(BuildContext context) =>
      WpRenderFillColumn(
        viewportExtent: viewportExtent,
        minFillExtent: minFillExtent,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    WpRenderFillColumn renderObject,
  ) {
    renderObject
      ..viewportExtent = viewportExtent
      ..minFillExtent = minFillExtent;
  }
}

/// Marks the one child of a [WpFillColumn] that takes the remaining height.
class WpFillSlot extends ParentDataWidget<WpFillColumnParentData> {
  const WpFillSlot({super.key, this.probe = false, required super.child});

  /// Measure the child without a height limit first and keep that height as
  /// its minimum. Only for children that can be laid out so (no scroll view,
  /// no `Expanded` directly inside); a nested [WpFillColumn] can.
  final bool probe;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as WpFillColumnParentData;
    if (data.fill && data.probe == probe) return;
    data
      ..fill = true
      ..probe = probe;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => WpFillColumn;
}

class WpFillColumnParentData extends ContainerBoxParentData<RenderBox> {
  bool fill = false;
  bool probe = false;
}

class WpRenderFillColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, WpFillColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, WpFillColumnParentData> {
  WpRenderFillColumn({this._viewportExtent, this._minFillExtent = 0});

  double? get viewportExtent => _viewportExtent;
  double? _viewportExtent;
  set viewportExtent(double? value) {
    if (value == _viewportExtent) return;
    _viewportExtent = value;
    markNeedsLayout();
  }

  double get minFillExtent => _minFillExtent;
  double _minFillExtent;
  set minFillExtent(double value) {
    if (value == _minFillExtent) return;
    _minFillExtent = value;
    markNeedsLayout();
  }

  bool _overflows = false;
  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! WpFillColumnParentData) {
      child.parentData = WpFillColumnParentData();
    }
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth, 'WpFillColumn needs a bounded width');
    final width = constraints.maxWidth;
    final loose = BoxConstraints.tightFor(width: width);
    RenderBox? fill;
    var rest = 0.0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as WpFillColumnParentData;
      if (data.fill && fill == null) {
        fill = child;
      } else {
        child.layout(loose, parentUsesSize: true);
        rest += child.size.height;
      }
      child = data.nextSibling;
    }

    var fillExtent = 0.0;
    if (fill != null) {
      final data = fill.parentData! as WpFillColumnParentData;
      var minimum = minFillExtent;
      if (data.probe) {
        fill.layout(loose, parentUsesSize: true);
        minimum = math.max(minimum, fill.size.height);
      }
      final available =
          viewportExtent ??
          (constraints.hasBoundedHeight ? constraints.maxHeight : 0.0);
      fillExtent = math.max(minimum, available - rest);
      fill.layout(
        BoxConstraints.tightFor(width: width, height: fillExtent),
        parentUsesSize: true,
      );
    }

    var y = 0.0;
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as WpFillColumnParentData;
      data.offset = Offset(0, y);
      y += child.size.height;
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(width, y));
    _overflows = y > size.height;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_overflows) {
      _clipLayer.layer = null;
      defaultPaint(context, offset);
      return;
    }
    // Only where a caller gave a bounded height and no scroll view: what
    // does not fit is cut off at the edge instead of painting over the
    // neighbours.
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      defaultPaint,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _overflows ? Offset.zero & size : null;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }
}

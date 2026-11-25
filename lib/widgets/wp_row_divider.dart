import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme/colors.dart';

/// The 1 px line between two rows of a card or list, in the subtle border
/// colour. [inset] indents it, e.g. to start under a row's text instead of
/// its icon.
///
/// The app's one row rule. Lists of rows place it through [WpDividedColumn],
/// never by hand, so a rule cannot end up at a list edge or next to another.
class WpRowDivider extends StatelessWidget {
  const WpRowDivider({super.key, this.inset = EdgeInsets.zero});

  final EdgeInsetsGeometry inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: inset,
    child: Container(height: 1, color: WpColors.borderSubtle),
  );
}

/// A vertical list of rows with exactly one [WpRowDivider] between two rows
/// that show something.
///
/// The column owns the separation; its rows never draw a rule of their own.
/// Whether a row shows anything is only known at layout time: many rows build
/// [SizedBox.shrink] when they do not apply (a GPU check off Windows, a notice
/// without a cause). The column therefore drops the rule in front of a row
/// that lays out with no height and the rule in front of the first row that
/// has height, so an empty row never leaves two rules stacked or a rule at
/// the top or bottom edge (#2050).
///
/// A [SizedBox] without a child is air, not a row: between two rows its
/// height is split around the single rule; before the first row or after the
/// last one it keeps its height.
class WpDividedColumn extends StatelessWidget {
  const WpDividedColumn({
    super.key,
    required this.children,
    this.inset = EdgeInsets.zero,
    this.ruleBefore,
  });

  final List<Widget> children;

  /// Inset of the default rule.
  final EdgeInsetsGeometry inset;

  /// The rule in front of a row, or null for a row that belongs to the one
  /// above it and gets none. Defaults to a [WpRowDivider] with [inset].
  final Widget? Function(Widget next)? ruleBefore;

  @override
  Widget build(BuildContext context) =>
      _DividedColumn(children: _slots(children));

  List<Widget> _slots(List<Widget> children) {
    final out = <Widget>[];
    var gap = 0.0;
    var hasRow = false;
    for (final child in children) {
      if (child is SizedBox && child.child == null) {
        gap += child.height ?? 0;
        continue;
      }
      final rule = !hasRow
          ? null
          : ruleBefore != null
          ? ruleBefore!(child)
          : WpRowDivider(inset: inset);
      if (rule != null) {
        out.add(
          _Slot(
            kind: _SlotKind.rule,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (gap > 0) SizedBox(height: gap / 2),
                rule,
                // Air under the rule keeps the old distance to the row below.
                if (gap > 0) SizedBox(height: gap / 2 + 1),
              ],
            ),
          ),
        );
      } else if (gap > 0) {
        out.add(
          _Slot(
            kind: _SlotKind.air,
            child: SizedBox(height: gap),
          ),
        );
      }
      gap = 0;
      // A row without a rule in front (e.g. a detail of the row above) does
      // not open a new row for the rule logic.
      out.add(
        _Slot(
          kind: rule == null && hasRow ? _SlotKind.attached : _SlotKind.row,
          child: child,
        ),
      );
      hasRow = true;
    }
    if (gap > 0) {
      out.add(
        _Slot(
          kind: _SlotKind.air,
          child: SizedBox(height: gap),
        ),
      );
    }
    return out;
  }
}

/// Whether [rule], a [WpRowDivider] inside a [WpDividedColumn], is drawn:
/// false when the column dropped it because it was not between two rows with
/// height. For the guard test only.
@visibleForTesting
bool debugWpRowDividerShown(RenderObject rule) {
  for (RenderObject? r = rule; r != null; r = r.parent) {
    final data = r.parentData;
    if (data is _SlotData) return data.kind != _SlotKind.rule || data.shown;
  }
  return true;
}

enum _SlotKind { row, attached, rule, air }

class _SlotData extends ContainerBoxParentData<RenderBox> {
  _SlotKind kind = _SlotKind.row;

  /// Set during layout: false for a rule that is not between two rows with
  /// height. Such a rule takes no room and paints nothing.
  bool shown = true;
}

class _Slot extends ParentDataWidget<_SlotData> {
  const _Slot({required this.kind, required super.child});

  final _SlotKind kind;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _SlotData;
    if (data.kind == kind) return;
    data.kind = kind;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _DividedColumn;
}

class _DividedColumn extends MultiChildRenderObjectWidget {
  const _DividedColumn({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDividedColumn();
}

class _RenderDividedColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotData) child.parentData = _SlotData();
  }

  _SlotData _data(RenderBox child) => child.parentData! as _SlotData;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final childConstraints = BoxConstraints.tightFor(width: width);
    // Pass 1: everything but the rules, to learn which rows are empty.
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      if (_data(c).kind != _SlotKind.rule) {
        c.layout(childConstraints, parentUsesSize: true);
      }
    }
    // Pass 2: a rule shows only after a row with height and in front of a
    // row with height (the slot right after a rule is always its row).
    var seenRow = false;
    var y = 0.0;
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      final data = _data(c);
      if (data.kind == _SlotKind.rule) {
        final next = data.nextSibling;
        data.shown = seenRow && next != null && next.size.height > 0;
        c.layout(childConstraints, parentUsesSize: true);
        data.offset = Offset(0, y);
        // A dropped rule takes no room and is not painted.
        if (data.shown) y += c.size.height;
        continue;
      } else if (data.kind == _SlotKind.row && c.size.height > 0) {
        seenRow = true;
      }
      data.offset = Offset(0, y);
      y += c.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var w = 0.0;
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      w = math.max(w, c.getMinIntrinsicWidth(double.infinity));
    }
    return w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var w = 0.0;
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      w = math.max(w, c.getMaxIntrinsicWidth(double.infinity));
    }
    return w;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    var h = 0.0;
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      h += c.getMinIntrinsicHeight(width);
    }
    return h;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    var h = 0.0;
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      h += c.getMaxIntrinsicHeight(width);
    }
    return h;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      final data = _data(c);
      if (data.kind == _SlotKind.rule && !data.shown) continue;
      context.paintChild(c, data.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (var c = lastChild; c != null; c = _data(c).previousSibling) {
      final data = _data(c);
      if (data.kind == _SlotKind.rule && !data.shown) continue;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            c!.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (var c = firstChild; c != null; c = _data(c).nextSibling) {
      final data = _data(c);
      if (data.kind == _SlotKind.rule && !data.shown) continue;
      visitor(c);
    }
  }
}

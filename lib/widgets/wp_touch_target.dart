import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme/tokens.dart';

/// Enlarges the tap surface of a compact control to
/// [WpLayout.minTouchTarget] square without changing what is painted.
///
/// [child] is laid out and painted at its own size, centred in a box of at
/// least 48 × 48. The whole box is one opaque gesture target that forwards
/// taps to [onTap], including taps on [child] itself: a glyph or other child
/// without a recognizer of its own (an [Icon]) therefore cannot swallow the
/// tap. A child with its own recognizer (InkWell, DropdownButton) still wins:
/// the gesture arena gives a tie to the innermost recognizer, so its tap does
/// not also fire [onTap].
///
/// Costs layout: the widget is at least 48 px in both axes, so a control
/// smaller than that takes the difference as extra room in its parent.
class WpTouchTarget extends StatelessWidget {
  const WpTouchTarget({
    super.key,
    required this.child,
    required this.onTap,
    this.alignment = Alignment.center,
    this.fillHeight = false,
  });

  final Widget child;

  /// `null` leaves the surrounding area inert, as a disabled control should.
  final VoidCallback? onTap;

  /// Where the visual sits inside the 48 px box. Centred by default; a
  /// control that hangs off an edge of its row (a tab underline) pins itself
  /// to that edge so its paint keeps lining up with the row.
  final AlignmentGeometry alignment;

  /// Hands a height the parent fixes on to [child] instead of centring the
  /// child in it. For a control whose own box already meets the touch target
  /// and that stands in a `WpControlRow`, which stretches every member to the
  /// tallest one: centred, a button stayed 3 dp short of the field beside it
  /// at larger text sizes (UX-131). The width is still aligned, never filled.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: WpLayout.minTouchTarget,
        minHeight: WpLayout.minTouchTarget,
      ),
      // Excluded from semantics: the visual child owns the control's role,
      // label and tap action, so this target must not add a second tappable
      // node that would split or swallow them.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        // widthFactor/heightFactor 1: size to the child (or the 48 px minimum),
        // not to the whole loose constraint a parent such as a Row passes.
        child: fillHeight
            ? _FillHeightAlign(
                alignment: alignment.resolve(Directionality.maybeOf(context)),
                child: child,
              )
            : Align(
                alignment: alignment,
                widthFactor: 1,
                heightFactor: 1,
                child: child,
              ),
      ),
    );
  }
}

/// [Align] with width and height factor 1, except that a tight height from
/// the parent reaches the child as a tight height. Intrinsics come from the
/// child, so it works under `IntrinsicHeight`.
class _FillHeightAlign extends SingleChildRenderObjectWidget {
  const _FillHeightAlign({required this.alignment, super.child});

  final Alignment alignment;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFillHeightAlign(alignment);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFillHeightAlign renderObject,
  ) {
    renderObject.alignment = alignment;
  }
}

class _RenderFillHeightAlign extends RenderShiftedBox {
  _RenderFillHeightAlign(this._alignment) : super(null);

  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final loose = constraints.loosen();
    child.layout(
      constraints.hasTightHeight
          ? loose.tighten(height: constraints.maxHeight)
          : loose,
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
    (child.parentData! as BoxParentData).offset = _alignment.alongOffset(
      size - child.size as Offset,
    );
  }
}

import 'package:flutter/material.dart';

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
  });

  final Widget child;

  /// `null` leaves the surrounding area inert, as a disabled control should.
  final VoidCallback? onTap;

  /// Where the visual sits inside the 48 px box. Centred by default; a
  /// control that hangs off an edge of its row (a tab underline) pins itself
  /// to that edge so its paint keeps lining up with the row.
  final AlignmentGeometry alignment;

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
        child: Align(
          alignment: alignment,
          widthFactor: 1,
          heightFactor: 1,
          child: child,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_touch_target.dart';

// ---------------------------------------------------------------------------
// WpRowCheckbox — the multi-select checkbox of a list row (CONTEXT.md
// §5.5.13). Single source for a styling block that used to be copied into
// the history list and compact views at two different sizes (24 vs 18).
//
// ticket spec §4: the visible box is 20 px with 4 px corners. The layout slot
// and the tap target are both 48 px (WpLayout.minTouchTarget), so the slot
// grows by 24 px against the former 24 px slot. Material draws its checkbox
// at a fixed 18 px, so the box is scaled up to 20 px; the tick gains weight
// rather than losing it.
// ---------------------------------------------------------------------------

class WpRowCheckbox extends StatelessWidget {
  const WpRowCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticsLabel,
  });

  final bool value;

  /// Screen-reader name of the box, e.g. the term or event the row lists.
  /// Without it the box is announced as an unnamed checkbox.
  final String? semanticsLabel;

  /// Called on tap. Row-level multi-select toggles the row itself, so this
  /// deliberately takes no argument — the checkbox never owns the state.
  final VoidCallback onChanged;

  /// Layout extent, so rows can reserve space for the leading slot.
  static const double extent = WpLayout.minTouchTarget;

  /// The visible box (ticket spec §4).
  static const double boxSize = 20;

  /// Material's fixed checkbox extent that [boxSize] scales from.
  static const double _materialBox = 18;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extent,
      height: extent,
      // loam-ignore: a11y-interactive-semantics – the wrapped child keeps its own role and label; WpTouchTarget only enlarges the tap area and is excluded from semantics (see wp_touch_target.dart).
      child: WpTouchTarget(
        onTap: onChanged,
        child: Center(
          child: Transform.scale(
            scale: boxSize / _materialBox,
            child: Checkbox(
              value: value,
              semanticLabel: semanticsLabel,
              onChanged: (_) => onChanged(),
              activeColor: WpColors.accent,
              side: BorderSide(color: WpColors.textMuted),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ),
    );
  }
}

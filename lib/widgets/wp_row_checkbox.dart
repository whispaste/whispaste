import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

// ---------------------------------------------------------------------------
// WpRowCheckbox — the multi-select checkbox of a list row (CONTEXT.md
// §5.5.13). Single source for a styling block that used to be copied into
// the history list and compact views at two different sizes (24 vs 18).
//
// 24 px is the surviving size: it is the accessible one of the two, and it
// matches Material's own checkbox extent, so the tick keeps its intended
// stroke weight instead of being scaled down. The compact view's row grows
// by a few pixels while multi-select is on — a transient mode, and the price
// of one checkbox instead of two.
// ---------------------------------------------------------------------------

class WpRowCheckbox extends StatelessWidget {
  const WpRowCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;

  /// Called on tap. Row-level multi-select toggles the row itself, so this
  /// deliberately takes no argument — the checkbox never owns the state.
  final VoidCallback onChanged;

  /// Layout extent, so rows can reserve space for the leading slot.
  static const double extent = 24;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extent,
      height: extent,
      child: Checkbox(
        value: value,
        onChanged: (_) => onChanged(),
        activeColor: WpColors.accent,
        side: const BorderSide(color: WpColors.textMuted),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

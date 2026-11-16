import 'package:flutter/widgets.dart';

import '../core/theme/tokens.dart';

/// Buttons side by side with the standard gap ([WpSpacing.buttonGap], #1687).
///
/// Use it wherever two or more buttons with a visible box sit in one row
/// (the edit and delete buttons of a list row, a pair of actions), so no
/// two boxes ever touch. Groups that may wrap use a `Wrap` with the same
/// spacing instead.
class WpButtonGroup extends StatelessWidget {
  const WpButtonGroup({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: crossAxisAlignment,
    spacing: WpSpacing.buttonGap,
    children: children,
  );
}

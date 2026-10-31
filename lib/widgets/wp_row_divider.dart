import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// The 1 px line between two rows of a card or list, in the subtle border
/// colour. [inset] indents it, e.g. to start under a row's text instead of
/// its icon.
class WpRowDivider extends StatelessWidget {
  const WpRowDivider({super.key, this.inset = EdgeInsets.zero});

  final EdgeInsetsGeometry inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: inset,
    child: Container(height: 1, color: WpColors.borderSubtle),
  );
}

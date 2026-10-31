import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// A thin, rounded determinate progress bar: [WpColors.accent] on the accent
/// badge fill. [value] is 0..1; null shows the indeterminate sweep.
class WpProgressBar extends StatelessWidget {
  const WpProgressBar({
    super.key,
    required this.value,
    this.height = 4,
    this.color,
  });

  final double? value;
  final double height;

  /// Fill colour; defaults to [WpColors.accent].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: WpRadius.borderFull,
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: WpColors.accentBadgeFill,
        color: color ?? WpColors.accent,
        minHeight: height,
      ),
    );
  }
}

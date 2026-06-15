import 'package:flutter/material.dart';

/// WhisPaste brand wordmark — the full logo + "Whispaste" text as a PNG image.
///
/// Automatically selects the dark or light variant based on theme brightness.
/// Dark variant: light bars + white "Whis" + cyan "paste" (for dark backgrounds).
/// Light variant: dark bars + navy "Whis" + cyan "paste" (for light backgrounds).
class WpBrandWordmark extends StatelessWidget {
  const WpBrandWordmark({super.key, this.height = 28});

  /// Logical height of the wordmark image.
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/icons/wordmark-dark.png'
        : 'assets/icons/wordmark-light.png';

    return Image.asset(
      asset,
      height: height,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      excludeFromSemantics: true,
    );
  }
}

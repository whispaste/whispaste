import 'package:flutter/material.dart';

/// WhisPaste brand wordmark — the original word-and-image mark (logo bars and
/// wave + "Whispaste") as a PNG image with 1.5x–4x resolution variants.
///
/// Dark variant: light bars + white "Whis" + cyan "paste" (for dark backgrounds).
/// Light variant: dark bars + navy "Whis" + cyan "paste" (for light backgrounds).
class WpBrandWordmark extends StatelessWidget {
  const WpBrandWordmark({super.key, this.height = 28, this.onDark});

  /// Logical height of the wordmark image.
  final double height;

  /// Whether the mark sits on a dark surface; defaults to the theme's
  /// brightness. Pass it explicitly where the surface differs from the theme
  /// (the sidebar frame).
  final bool? onDark;

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;

    return Image.asset(
      dark
          ? 'assets/icons/wordmark-dark.png'
          : 'assets/icons/wordmark-light.png',
      height: height,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      excludeFromSemantics: true,
    );
  }
}

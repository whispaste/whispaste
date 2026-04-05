import 'package:flutter/material.dart';

/// WhisPaste brand logo — renders the real app icon from assets.
///
/// Automatically selects the dark or light variant based on theme.
/// Uses high-quality PNG assets (1024×1024 source) for crisp rendering.
class WpBrandLogo extends StatelessWidget {
  const WpBrandLogo({
    super.key,
    this.size = 32,
    this.withBackground = false,
    this.borderRadius,
  });

  /// Logical size of the logo.
  final double size;

  /// If true, renders the logo with the rounded dark background variant.
  final bool withBackground;

  /// Custom border radius when [withBackground] is true.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (withBackground) {
      return ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/icons/logo-bg.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          isAntiAlias: true,
        ),
      );
    }

    final asset = isDark
        ? 'assets/icons/logo-dark.png'
        : 'assets/icons/logo-light.png';

    return Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      isAntiAlias: true,
    );
  }
}

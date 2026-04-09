/// Subtle topographic contour watermark painted on the app frame.
///
/// Draws faint concentric arcs offset to the bottom-right, evoking a
/// premium dashboard / gaming-launcher feel without competing with
/// content. Opacity kept at ≈ 3% so it's FELT, not SEEN.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// Topographic watermark widget — wraps [WpTopoPainter] in a [CustomPaint].
class WpFrameWatermark extends StatelessWidget {
  const WpFrameWatermark({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WpTopoPainter(isDark: isDark),
      child: const SizedBox.expand(),
    );
  }
}

/// Paints faint concentric elliptical arcs in two clusters.
class WpTopoPainter extends CustomPainter {
  const WpTopoPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = isDark
          ? const Color(0x08FFFFFF) // ~3% white on dark
          : WpColorsLight.watermark; // ~4% black on light

    // Origin offset to bottom-right so arcs peek from the corner
    final cx = size.width * 0.85;
    final cy = size.height * 0.9;
    final maxR = math.max(size.width, size.height) * 0.7;

    // Draw concentric elliptical arcs
    for (var r = 40.0; r < maxR; r += 55) {
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: r * 2.2,
        height: r * 1.6,
      );
      canvas.drawArc(rect, math.pi * 0.8, math.pi * 1.1, false, paint);
    }

    // Second cluster — subtle, top-left
    final cx2 = size.width * 0.12;
    final cy2 = size.height * 0.15;
    for (var r = 30.0; r < maxR * 0.4; r += 60) {
      final rect = Rect.fromCenter(
        center: Offset(cx2, cy2),
        width: r * 1.8,
        height: r * 2.0,
      );
      canvas.drawArc(rect, -math.pi * 0.3, math.pi * 0.8, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WpTopoPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

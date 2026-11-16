/// The WhisPaste wave mark (bars and wave) as vector paths, for painting it
/// in one flat colour where the shipped logo files (a gradient raster inside
/// an SVG, `assets/icons/logo-*.svg`) cannot be tinted.
///
/// Geometry is taken from the outlines in `assets/icons/logo-dark.svg`, in its
/// 1024 x 1024 view box. Used by the floating button's resting form (#483).
library;

import 'dart:ui';

abstract final class WpLogoMark {
  /// Bounding box of the mark inside the view box.
  static Rect get bounds => _bounds ??= path().getBounds();
  static Rect? _bounds;

  /// The mark (wave plus four bars) in view-box coordinates.
  static Path path() {
    return Path()
      ..moveTo(184.471, 724.191)
      ..cubicTo(180.84, 723.403, 196.947, 693.445, 235.71, 673.263)
      ..cubicTo(256.533, 662.422, 289.581, 679.907, 296.124, 686.979)
      ..cubicTo(302.667, 694.052, 361.895, 754.933, 373.49, 760.208)
      ..cubicTo(385.085, 765.483, 400.828, 783.984, 436.217, 758.258)
      ..cubicTo(464.6, 737.626, 506.136, 610.778, 515.561, 592.037)
      ..cubicTo(530.128, 563.072, 552.309, 527.241, 588.421, 523.12)
      ..cubicTo(608.272, 520.855, 640.51, 537.076, 658.883, 562.207)
      ..cubicTo(677.255, 587.338, 727.108, 667.311, 772.894, 684.186)
      ..cubicTo(801.805, 694.841, 821.214, 689.077, 859.337, 658.4)
      ..cubicTo(894.71, 629.936, 909.165, 589.12, 908.201, 599.364)
      ..cubicTo(904.463, 639.095, 873.734, 804.604, 698.09, 911.413)
      ..cubicTo(674.8, 925.575, 752.371, 817.049, 747.163, 807.587)
      ..cubicTo(744.509, 802.763, 681.492, 814.298, 643.374, 747.329)
      ..cubicTo(599.368, 670.014, 559.53, 633.453, 524.144, 709.911)
      ..cubicTo(498.157, 766.06, 467.3, 843.123, 430.562, 862.457)
      ..cubicTo(396.132, 880.577, 354.414, 871.732, 329.655, 849.415)
      ..cubicTo(308.594, 830.432, 265.673, 783.352, 257.473, 772.765)
      ..cubicTo(223.317, 728.665, 195.613, 726.611, 184.471, 724.191)
      ..close()
      ..moveTo(375.173, 107.502)
      ..cubicTo(375.173, 82.808, 355.124, 62.759, 330.43, 62.759)
      ..cubicTo(305.736, 62.759, 285.687, 82.808, 285.687, 107.502)
      ..lineTo(285.687, 605.512)
      ..cubicTo(285.687, 630.207, 305.736, 650.255, 330.43, 650.255)
      ..cubicTo(355.124, 650.255, 375.173, 630.207, 375.173, 605.512)
      ..lineTo(375.173, 107.502)
      ..close()
      ..moveTo(523.02, 220.333)
      ..cubicTo(523.02, 195.638, 502.971, 175.59, 478.277, 175.59)
      ..cubicTo(453.582, 175.59, 433.534, 195.638, 433.534, 220.333)
      ..lineTo(433.534, 492.682)
      ..cubicTo(433.534, 517.376, 453.582, 537.425, 478.277, 537.425)
      ..cubicTo(502.971, 537.425, 523.02, 517.376, 523.02, 492.682)
      ..lineTo(523.02, 220.333)
      ..close()
      ..moveTo(227.326, 260.644)
      ..cubicTo(227.326, 235.95, 207.278, 215.901, 182.583, 215.901)
      ..cubicTo(157.889, 215.901, 137.84, 235.95, 137.84, 260.644)
      ..lineTo(137.84, 452.371)
      ..cubicTo(137.84, 477.065, 157.889, 497.114, 182.583, 497.114)
      ..cubicTo(207.278, 497.114, 227.326, 477.065, 227.326, 452.371)
      ..lineTo(227.326, 260.644)
      ..close()
      ..moveTo(670.866, 328.731)
      ..cubicTo(670.866, 304.037, 650.818, 283.988, 626.123, 283.988)
      ..cubicTo(601.429, 283.988, 581.38, 304.037, 581.38, 328.731)
      ..lineTo(581.38, 384.283)
      ..cubicTo(581.38, 408.978, 601.429, 429.026, 626.123, 429.026)
      ..cubicTo(650.818, 429.026, 670.866, 408.978, 670.866, 384.283)
      ..lineTo(670.866, 328.731)
      ..close();
  }

  /// Draws the mark centred in [box], scaled to fit, in [color].
  static void paint(Canvas canvas, Rect box, Color color) {
    final b = bounds;
    final scale = (box.width / b.width) < (box.height / b.height)
        ? box.width / b.width
        : box.height / b.height;
    canvas
      ..save()
      ..translate(box.center.dx, box.center.dy)
      ..scale(scale)
      ..translate(-b.center.dx, -b.center.dy)
      ..drawPath(path(), Paint()..color = color)
      ..restore();
  }
}

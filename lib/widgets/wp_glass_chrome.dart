/// WpGlassChrome — the shared painted glass surface for structural app chrome.
///
/// Wraps any child and paints a translucent slab with a lit rim behind it.
/// One [CustomPainter] draws the whole material: a neutral gradient fill, a
/// top-down sheen, an inner Fresnel band, a short specular streak, and a 1 px
/// rim lit from above.
///
/// ## Why the glass is painted, never blurred
///
/// There is no compositor blur pass anywhere in this file, and that is an
/// architecture decision rather than an optimisation waiting to be reversed.
/// A real blur is the one effect whose cost lands precisely on the weak and
/// integrated GPUs this product promises to serve, and it renders unevenly
/// across the three desktop platforms. Faking the read with gradients and
/// edge light costs the same everywhere, which is why this component needs no
/// hardware fallback at all. `test/widgets/wp_glass_chrome_guard_test.dart`
/// keeps that enforced instead of merely documented.
///
/// The technique is derived from the recording overlay's painter
/// (`lib/widgets/floating_overlay/overlay_painter.dart`), minus its liquid
/// silhouette and its animation: this chrome is **static**, so the overlay
/// stays the app's single moving element.
///
/// ## Where the accent lives
///
/// The brand accent (Signal-Cyan on dark, Harbor-Teal on light) is carried by
/// the rim alone. The fill, sheen and specular are achromatic, so even a
/// full-height pane reads as neutral glass with a branded edge rather than as
/// a second accent area.
///
/// An unrelated `WpGlassPanel` in `lib/core/theme/colors.dart` takes the
/// opposite, blur-based approach. The two are deliberately separate; nothing
/// here builds on it.
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// A translucent glass surface painted behind [child].
class WpGlassChrome extends StatelessWidget {
  const WpGlassChrome({
    super.key,
    required this.child,
    this.radius = WpRadius.lg,
  });

  final Widget child;

  /// Corner radius, in logical pixels. Defaults to [WpRadius.lg].
  ///
  /// Pass another step off the [WpRadius] scale — the geometry stays on the
  /// existing flat scale; the macOS reference informs the material and the
  /// light behaviour, not the corner shape.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WpGlassChromePainter(
        brightness: Theme.of(context).brightness,
        radius: radius,
      ),
      child: child,
    );
  }
}

/// The glass tints resolved for one [Brightness].
///
/// Exposed (rather than resolved inline in the painter) so widget tests can
/// assert the theme pairing without golden snapshots.
class WpGlassChromeColors {
  const WpGlassChromeColors._({
    required this.fillStart,
    required this.fillEnd,
    required this.sheen,
    required this.innerRim,
    required this.specular,
    required this.edgeTop,
    required this.edgeBottom,
  });

  static const WpGlassChromeColors _dark = WpGlassChromeColors._(
    fillStart: WpColorsDark.glassChromeFillStart,
    fillEnd: WpColorsDark.glassChromeFillEnd,
    sheen: WpColorsDark.glassChromeSheen,
    innerRim: WpColorsDark.glassChromeInnerRim,
    specular: WpColorsDark.glassChromeSpecular,
    edgeTop: WpColorsDark.glassChromeEdgeTop,
    edgeBottom: WpColorsDark.glassChromeEdgeBottom,
  );

  static const WpGlassChromeColors _light = WpGlassChromeColors._(
    fillStart: WpColorsLight.glassChromeFillStart,
    fillEnd: WpColorsLight.glassChromeFillEnd,
    sheen: WpColorsLight.glassChromeSheen,
    innerRim: WpColorsLight.glassChromeInnerRim,
    specular: WpColorsLight.glassChromeSpecular,
    edgeTop: WpColorsLight.glassChromeEdgeTop,
    edgeBottom: WpColorsLight.glassChromeEdgeBottom,
  );

  static WpGlassChromeColors of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  /// Surface fill, top-left to bottom-right.
  final Color fillStart;
  final Color fillEnd;

  /// Top-down highlight across the upper half of the slab.
  final Color sheen;

  /// Inner band just inside the rim — the apparent thickness of the glass.
  final Color innerRim;

  /// Short bright streak along the top edge.
  final Color specular;

  /// Outer rim, lit from above: accent at the top edge, a trace at the bottom.
  final Color edgeTop;
  final Color edgeBottom;
}

/// Paints the glass slab: fill, sheen, inner Fresnel band, specular, rim.
class WpGlassChromePainter extends CustomPainter {
  const WpGlassChromePainter({required this.brightness, required this.radius});

  final Brightness brightness;
  final double radius;

  WpGlassChromeColors get colors => WpGlassChromeColors.of(brightness);

  /// Where the top-down sheen has faded out. Half the height keeps it a wash
  /// over the upper body on a tall pane instead of a band with a visible end.
  static const double _sheenEndStop = 0.5;

  static const double _innerRimInset = 1.5;
  static const double _innerRimWidth = 1.0;
  static const double _rimWidth = 1.0;

  /// Specular geometry. The streak is a fraction of the width, so it stays a
  /// highlight on a wide surface instead of stretching into a full-width line.
  static const double _specularWidthFactor = 0.45;
  static const double _specularInsetTop = 1.5;
  static const double _specularStrokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final c = colors;
    // Half a pixel in, so the 1 px rim stroke lands fully inside the bounds.
    final rect = (Offset.zero & size).deflate(0.5);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.fillStart, c.fillEnd],
        ).createShader(rect),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.sheen, _clear(c.sheen)],
          stops: const [0.0, _sheenEndStop],
        ).createShader(rect),
    );

    // Inner Fresnel band: glass reflects most at grazing angles, so the edge
    // carries the material identity when the fill itself is near-clear.
    canvas.drawRRect(
      rrect.deflate(_innerRimInset),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _innerRimWidth
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.innerRim, _clear(c.innerRim)],
        ).createShader(rect),
    );

    _paintSpecular(canvas, rect, c);

    // Rim light, not a border: a uniform stroke would read as an outline, the
    // top-to-bottom falloff reads as light catching the upper edge.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _rimWidth
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.edgeTop, c.edgeBottom],
        ).createShader(rect),
    );
  }

  void _paintSpecular(Canvas canvas, Rect rect, WpGlassChromeColors c) {
    final half = rect.width * _specularWidthFactor / 2;
    if (half <= 0) return;

    final y = rect.top + _specularInsetTop;
    final cx = rect.center.dx;
    canvas.drawLine(
      Offset(cx - half, y),
      Offset(cx + half, y),
      Paint()
        ..strokeWidth = _specularStrokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [_clear(c.specular), c.specular, _clear(c.specular)],
        ).createShader(Rect.fromLTRB(cx - half, y - 1, cx + half, y + 1)),
    );
  }

  @override
  bool shouldRepaint(WpGlassChromePainter old) =>
      old.brightness != brightness || old.radius != radius;
}

/// The same hue at zero alpha.
///
/// Gradients must fade to their own colour, not to [Colors.transparent]:
/// stops interpolate per channel, so a white-to-transparent-black ramp drags
/// its midpoint toward grey and the sheen picks up a dirty band.
Color _clear(Color color) => color.withValues(alpha: 0);

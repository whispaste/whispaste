/// The single shared floating-button renderer.
///
/// One [CustomPainter] draws the V2 floating button for **every** platform that
/// hosts it in a thin native window shell (macOS/Windows now, Linux via issue
/// 09). It reproduces the approved spike design (`spike/lib/main.dart`
/// `_drawButton` / `_mic`), flattened in the WP-75 flat pass: a single-colour disc with a painted soft
/// shadow, a thin neutral hairline border and a dark mic glyph — explicitly
/// **no** accent ring and **no** light effect (ADR 0002, calm UI).
///
/// Every dimension, colour and gradient comes from [OverlayDesignSpec.button]
/// (flat disc colour, border, mic geometry as ratios of the disc diameter) and
/// [OverlayDesignSpec.glyphStopsFor] (per-state mic tint, resolved per
/// background tone, WP-75) — there are deliberately **no** design constants in
/// this file.
///
/// The disc chrome (flat fill + painted shadow) uses the intrinsic
/// per-element opacity from [OverlayDesignSpec]. The mic glyph stays fully opaque.
library;

import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_design_spec.dart';

/// Paints the V2 floating-button disc and its mic glyph from the SSOT spec.
class WpFloatingButtonPainter extends CustomPainter {
  /// Creates a painter for one immutable button frame.
  const WpFloatingButtonPainter({
    required this.spec,
    required this.diameter,
    required this.iconColor,
    required this.iconGradient,
    this.square = false,
  });

  /// Draws a rounded square ([OverlayDesignSpec.buttonSquareCornerRatio])
  /// instead of the round disc (WP-95 button shape).
  final bool square;

  /// The V2 button appearance tokens, from the spec.
  final FloatingButtonSpec spec;

  /// Disc diameter in logical pixels (settings-owned: 44 / 56 / 80).
  final double diameter;

  /// Solid mic-glyph colour used when [iconGradient] is null (idle/disabled).
  final Color iconColor;

  /// Per-state mic-glyph gradient stops (e.g. done → `#30C065` middle stop), or
  /// null when the glyph is a solid [iconColor] (idle/disabled). Drawn over the
  /// glyph's bounding box.
  final List<Color>? iconGradient;

  @override
  void paint(Canvas canvas, Size size) {
    final r = diameter / 2;
    final center = Offset(
      OverlayDesignSpec.shadowPadding + r,
      OverlayDesignSpec.shadowPadding + r,
    );

    _drawShadow(canvas, center, r);
    _drawDisc(canvas, center, r);
    _drawBorder(canvas, center, r);
    _drawMic(canvas, center);
  }

  /// The disc, the shadow and the border share one outline: a circle, or a
  /// rounded square of the same size when [square] is set.
  void _outline(Canvas canvas, Offset center, double r, Paint paint) {
    if (!square) {
      canvas.drawCircle(center, r, paint);
      return;
    }
    final radius = Radius.circular(
      r * OverlayDesignSpec.buttonSquareCornerRatio,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCircle(center: center, radius: r),
        radius,
      ),
      paint,
    );
  }

  // ── Chrome ────────────────────────────────────────────────────────────────────

  void _drawShadow(Canvas canvas, Offset center, double r) {
    _outline(
      canvas,
      center + OverlayDesignSpec.shadowOffset,
      r,
      Paint()
        ..color = spec.shadowColor
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.shadowBlur,
        ),
    );
  }

  void _drawDisc(Canvas canvas, Offset center, double r) {
    // Flat disc (WP-75 flat pass): one colour, no tint gradient.
    _outline(
      canvas,
      center,
      r,
      Paint()..color = spec.discColor.withValues(alpha: spec.discFillOpacity),
    );
  }

  void _drawBorder(Canvas canvas, Offset center, double r) {
    _outline(
      canvas,
      center,
      r - spec.borderInset,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.borderWidth
        ..color = spec.borderColor,
    );
    // UX-048: the dark presets get a 1 px light outer edge around the disc,
    // following the button's shape like the border above.
    if (spec.edgeColor.a > 0) {
      _outline(
        canvas,
        center,
        r - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = spec.edgeColor,
      );
    }
  }

  // ── Mic glyph (always opaque) ───────────────────────────────────────────────

  void _drawMic(Canvas canvas, Offset center) {
    final mic = spec.mic;
    final d = diameter;

    // Per-state tint: a gradient shader (active states) or a solid colour.
    final Paint fill = Paint();
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = mic.strokeRatio * d
      ..strokeCap = StrokeCap.round;
    final gradient = iconGradient;
    if (gradient != null) {
      final bounds = Rect.fromCenter(
        center: center,
        width: spec.iconRatio * d,
        height: spec.iconRatio * d,
      );
      final shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradient,
      ).createShader(bounds);
      fill.shader = shader;
      stroke.shader = shader;
    } else {
      fill.color = iconColor;
      stroke.color = iconColor;
    }

    // Capsule body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(0, mic.bodyCenterDyRatio * d),
          width: mic.bodyWidthRatio * d,
          height: mic.bodyHeightRatio * d,
        ),
        Radius.circular(mic.bodyRadiusRatio * d),
      ),
      fill,
    );

    // Cradle arc.
    canvas.drawArc(
      Rect.fromCircle(
        center: center + Offset(0, mic.arcCenterDyRatio * d),
        radius: mic.arcRadiusRatio * d,
      ),
      mic.arcStartAngle,
      mic.arcSweepAngle,
      false,
      stroke,
    );

    // Stem.
    canvas.drawLine(
      center + Offset(0, mic.stemTopDyRatio * d),
      center + Offset(0, mic.stemBottomDyRatio * d),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant WpFloatingButtonPainter old) {
    return old.spec != spec ||
        old.diameter != diameter ||
        old.iconColor != iconColor ||
        old.square != square ||
        !_sameGradient(old.iconGradient, iconGradient);
  }

  static bool _sameGradient(List<Color>? a, List<Color>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

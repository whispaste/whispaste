/// The single shared floating-button renderer.
///
/// One [CustomPainter] draws the V2 floating button for **every** platform that
/// hosts it in a thin native window shell (macOS/Windows now, Linux via issue
/// 09). It reproduces the approved spike design (`spike/lib/main.dart`
/// `_drawButton` / `_mic`): a white tint-gradient disc with a painted soft
/// shadow, a thin neutral hairline border and a dark mic glyph — explicitly
/// **no** accent ring and **no** glow (ADR 0002, calm UI).
///
/// Every dimension, colour and gradient comes from [OverlayDesignSpec.button]
/// (disc gradient, border, mic geometry as ratios of the disc diameter) and
/// [OverlayDesignSpec.stateGradients] (per-state mic tint, e.g. the done green
/// `#30C065`) — there are deliberately **no** design constants in this file.
///
/// The disc chrome (fill gradient + painted shadow) uses the intrinsic
/// per-element opacity from [OverlayDesignSpec]. The mic glyph stays fully opaque.
library;

import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_design_spec.dart';

/// Paints the V2 floating-button disc and its mic glyph from the SSOT spec.
class FloatingButtonPainter extends CustomPainter {
  /// Creates a painter for one immutable button frame.
  const FloatingButtonPainter({
    required this.spec,
    required this.diameter,
    required this.iconColor,
    required this.iconGradient,
  });

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

  // ── Chrome ────────────────────────────────────────────────────────────────────

  void _drawShadow(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center + OverlayDesignSpec.shadowOffset,
      r,
      Paint()
        ..color = OverlayDesignSpec.shadowColor.withValues(
          alpha: OverlayDesignSpec.shadowOpacity,
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.shadowBlur,
        ),
    );
  }

  void _drawDisc(Canvas canvas, Offset center, double r) {
    final a = spec.discFillOpacity;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            spec.discColor.withValues(alpha: a),
            spec.discGradientEnd.withValues(alpha: a),
          ],
        ).createShader(rect),
    );
  }

  void _drawBorder(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center,
      r - spec.borderInset,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.borderWidth
        ..color = spec.borderColor,
    );
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
  bool shouldRepaint(covariant FloatingButtonPainter old) {
    return old.spec != spec ||
        old.diameter != diameter ||
        old.iconColor != iconColor ||
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

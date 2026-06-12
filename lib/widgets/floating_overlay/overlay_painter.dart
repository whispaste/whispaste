/// The single shared overlay renderer.
///
/// One [CustomPainter] draws the floating overlay for **every** platform
/// (macOS, Windows and — via issue 07 — Linux) and the website mirrors the same
/// math (issue 10). It reproduces the approved spike design
/// (`spike/lib/main.dart` `kFinalDesign` / `_drawPill`): a light tint-gradient
/// **capsule** with a painted soft shadow, an accent (teal) recording dot, an
/// accent timer, thin accent line-bars (the most recent few brighter), a small
/// dark stop square and a subtle inset accent progress timeline.
///
/// Every dimension, colour, gradient and timing comes from [OverlayDesignSpec]
/// — there are deliberately **no** design constants in this file. Calm-UI rules
/// (ADR 0002): no glows, no shimmer, no privacy badge.
///
/// The content layer — text, dot, waveform, stop square, timeline, status icons
/// — is always fully opaque. The chrome (fill gradient, shadow, border) uses
/// the intrinsic per-element opacity from [OverlayDesignSpec].
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_design_spec.dart';

/// Paints the overlay capsule and its per-state content from the SSOT spec.
class OverlayPainter extends CustomPainter {
  /// Creates a painter for one immutable overlay frame.
  const OverlayPainter({
    required this.state,
    required this.theme,
    required this.sizeSpec,
    required this.layout,
    required this.colors,
    required this.waveformBars,
    required this.timerText,
    required this.statusText,
    required this.progress,
    required this.dotPulse,
  });

  /// The visual state being rendered.
  final OverlayDesignState state;

  /// The resolved theme variant.
  final OverlayDesignTheme theme;

  /// Per-size box geometry (width/height/capsule radius), from the spec.
  final OverlaySizeSpec sizeSpec;

  /// Hand-tuned per-size content layout (spike values), from the spec.
  final OverlayLayoutSpec layout;

  /// Resolved theme colour set, from the spec.
  final OverlayThemeColors colors;

  /// Normalised waveform levels (`[0, 1]`), length [WaveformSpec.barCount].
  /// Empty outside the recording state (a flat faint waveform is synthesised
  /// from [OverlayDesignSpec.waveformRestLevel] for the transcribing state).
  final List<double> waveformBars;

  /// Pre-formatted recording timer (e.g. `0:12`).
  final String timerText;

  /// Active text: the label while transcribing, or the done/error message.
  final String statusText;

  /// Recording progress toward the max duration (0–1); 0 hides the timeline.
  final double progress;

  /// Recording-dot pulse phase (0–1), driven by the host widget's ticker.
  final double dotPulse;

  bool get _isRecording => state == OverlayDesignState.recording;

  @override
  void paint(Canvas canvas, Size size) {
    final pill = Rect.fromLTWH(
      OverlayDesignSpec.shadowPadding,
      OverlayDesignSpec.shadowPadding,
      sizeSpec.width,
      sizeSpec.height,
    );
    final radius = sizeSpec.capsuleRadius;
    final rrect = RRect.fromRectAndRadius(
      pill.deflate(1),
      Radius.circular(radius),
    );

    _drawShadow(canvas, rrect);
    _drawFill(canvas, rrect, pill);
    _drawBorder(canvas, rrect);

    // Content layer — clipped to the capsule, always fully opaque.
    canvas.save();
    canvas.clipRRect(rrect);
    _drawContent(canvas, pill);
    canvas.restore();
  }

  // ── Chrome ────────────────────────────────────────────────────────────────────

  void _drawShadow(Canvas canvas, RRect rrect) {
    canvas.drawRRect(
      rrect.shift(OverlayDesignSpec.shadowOffset),
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

  void _drawFill(Canvas canvas, RRect rrect, Rect pill) {
    const a = OverlayDesignSpec.fillOpacityFactor;
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.capsuleFillStart.withValues(alpha: a),
            colors.capsuleFillEnd.withValues(alpha: a),
          ],
        ).createShader(pill),
    );
  }

  void _drawBorder(Canvas canvas, RRect rrect) {
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = colors.capsuleBorder.withValues(
          alpha: colors.capsuleBorder.a,
        ),
    );
  }

  // ── Content (always opaque) ─────────────────────────────────────────────────

  void _drawContent(Canvas canvas, Rect pill) {
    final cy = pill.center.dy;
    final base = pill.left + layout.padH;

    _drawClose(canvas, Offset(base + layout.closeOffset, cy));

    // Leading glyph: pulsing accent dot (recording/transcribing) or the
    // done/error status icon.
    final leadCenter = Offset(base + layout.dotInset, cy);
    switch (state) {
      case OverlayDesignState.recording:
      case OverlayDesignState.transcribing:
        _drawDot(canvas, leadCenter);
      case OverlayDesignState.done:
        _drawCheckIcon(canvas, leadCenter, colors.success);
      case OverlayDesignState.error:
        _drawErrorIcon(canvas, leadCenter, colors.error);
    }

    // Active text colour. The approved spike has `accentTimer = false`: the
    // recording timer, the transcribing label and the done message all render
    // in the theme text (content) colour — not accent/success. Only the error
    // message stays semantically red. The dot/icons/waveform keep their colour.
    final textColor = switch (state) {
      OverlayDesignState.recording => colors.text,
      OverlayDesignState.transcribing => colors.text,
      OverlayDesignState.done => colors.text,
      OverlayDesignState.error => colors.error,
    };
    final textLeft = leadCenter.dx + layout.timerGap;
    final maxTextWidth = pill.right - layout.padH - textLeft;
    final textWidth = _drawText(
      canvas,
      _isRecording ? timerText : statusText,
      Offset(textLeft, cy),
      layout.timerFontSize,
      textColor,
      maxWidth: maxTextWidth,
    );

    // Waveform + stop square: recording (live) and transcribing (faint flat).
    if (state == OverlayDesignState.recording ||
        state == OverlayDesignState.transcribing) {
      final stopSize = layout.stopSize;
      final waveLeft = textLeft + textWidth + layout.waveStartGap;
      final waveRight = _isRecording
          ? pill.right - layout.padH - stopSize - layout.waveEndGap
          : pill.right - layout.padH;
      _drawWaveform(canvas, waveLeft, waveRight, cy, pill.height);

      if (_isRecording) {
        _drawStop(canvas, Offset(pill.right - layout.padH - stopSize / 2, cy));
      }
    }

    // Inset accent progress timeline (recording only).
    if (_isRecording && progress > 0) {
      _drawTimeline(canvas, pill);
    }
  }

  void _drawClose(Canvas canvas, Offset center) {
    final arm = layout.closeArm;
    final paint = Paint()
      ..color = colors.text.withValues(alpha: 0.7)
      ..strokeWidth = layout.closeStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center + Offset(-arm, -arm),
      center + Offset(arm, arm),
      paint,
    );
    canvas.drawLine(
      center + Offset(arm, -arm),
      center + Offset(-arm, arm),
      paint,
    );
  }

  void _drawDot(Canvas canvas, Offset center) {
    final min = OverlayDesignSpec.motion.dotPulseMinAlpha;
    final alpha = min + (1.0 - min) * dotPulse;
    canvas.drawCircle(
      center,
      layout.dotRadius,
      Paint()..color = colors.accent.withValues(alpha: alpha),
    );
  }

  void _drawStop(Canvas canvas, Offset center) {
    final s = layout.stopSize;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: s, height: s),
        const Radius.circular(OverlayDesignSpec.stopSquareRadius),
      ),
      Paint()
        ..color = colors.text.withValues(
          alpha: OverlayDesignSpec.stopSquareOpacity,
        ),
    );
  }

  void _drawWaveform(
    Canvas canvas,
    double left,
    double right,
    double cy,
    double pillHeight,
  ) {
    final waveW = right - left;
    if (waveW <= 20) return;
    final count = OverlayDesignSpec.waveform.barCount;
    final barW = waveW / count;
    final maxH = pillHeight * OverlayDesignSpec.waveformHeightFactor;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final level = _isRecording
          ? (i < waveformBars.length ? waveformBars[i].clamp(0.0, 1.0) : 0.0)
          : OverlayDesignSpec.waveformRestLevel;
      final h = level * maxH;
      final x = left + i * barW + barW / 2;
      final active = i > count - OverlayDesignSpec.waveformActiveCount;
      final alpha = _isRecording
          ? (active
                ? OverlayDesignSpec.waveformActiveOpacity
                : OverlayDesignSpec.waveformMutedLineOpacity)
          : OverlayDesignSpec.waveformInactiveStateOpacity;
      paint
        ..strokeWidth = math.max(
          layout.lineStrokeMin,
          barW * OverlayDesignSpec.waveformLineStrokeFactor,
        )
        ..color = colors.accent.withValues(alpha: alpha);
      canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), paint);
    }
  }

  void _drawTimeline(Canvas canvas, Rect pill) {
    final radius = sizeSpec.capsuleRadius;
    final lineY = pill.bottom - OverlayDesignSpec.timelineInsetBottom;
    final lineL = pill.left + radius;
    final lineR = pill.right - radius;
    final end = lineL + (lineR - lineL) * progress.clamp(0.0, 1.0);
    canvas.drawLine(
      Offset(lineL, lineY),
      Offset(end, lineY),
      Paint()
        ..strokeWidth = OverlayDesignSpec.timelineStrokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            colors.accent,
            colors.accent.withValues(
              alpha: OverlayDesignSpec.timelineEndOpacity,
            ),
          ],
        ).createShader(Rect.fromLTWH(lineL, lineY - 1, lineR - lineL, 2)),
    );
  }

  void _drawCheckIcon(Canvas canvas, Offset center, Color tint) {
    final r = sizeSpec.statusIconSize / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, sizeSpec.statusIconSize * 0.14)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = tint;
    final path = Path()
      ..moveTo(center.dx - r * 0.55, center.dy)
      ..lineTo(center.dx - r * 0.1, center.dy + r * 0.45)
      ..lineTo(center.dx + r * 0.6, center.dy - r * 0.5);
    canvas.drawPath(path, paint);
  }

  void _drawErrorIcon(Canvas canvas, Offset center, Color tint) {
    final r = sizeSpec.statusIconSize / 2;
    final stroke = math.max(1.5, sizeSpec.statusIconSize * 0.12);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = tint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - r * 0.45),
      Offset(center.dx, center.dy + r * 0.12),
      Paint()
        ..color = tint
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(center.dx, center.dy + r * 0.5),
      math.max(0.8, sizeSpec.statusIconSize * 0.06),
      Paint()..color = tint,
    );
  }

  /// Draws single-line [text] left-anchored at [leftCenter] and returns the
  /// laid-out width. Text is always fully opaque (accessibility).
  double _drawText(
    Canvas canvas,
    String text,
    Offset leftCenter,
    double fontSize,
    Color color, {
    double? maxWidth,
  }) {
    if (text.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: OverlayDesignSpec.primaryFontWeight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(
      maxWidth: maxWidth != null && maxWidth > 0 ? maxWidth : double.infinity,
    );
    tp.paint(canvas, Offset(leftCenter.dx, leftCenter.dy - tp.height / 2));
    return tp.width;
  }

  @override
  bool shouldRepaint(covariant OverlayPainter old) {
    return old.state != state ||
        old.theme != theme ||
        old.sizeSpec != sizeSpec ||
        old.layout != layout ||
        old.timerText != timerText ||
        old.statusText != statusText ||
        old.progress != progress ||
        old.dotPulse != dotPulse ||
        !identical(old.waveformBars, waveformBars);
  }
}

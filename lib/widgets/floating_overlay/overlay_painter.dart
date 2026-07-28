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
  ///
  /// [paintFill] and [paintContent] let the host widget split the draw into two
  /// independent layers for the state-transition crossfade: the fill layer
  /// (shadow + gradient capsule background) is drawn once, while only the
  /// content layer (dot, text, waveform, icons) is crossfaded. Drawing the
  /// semi-transparent fill twice at different opacities would darken the capsule
  /// during the transition; this flag pair prevents that.
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
    this.paintFill = true,
    this.paintContent = true,
    this.pillWidth,
    this.iconRevealFraction = 1.0,
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

  /// Whether to draw the capsule fill layer (shadow, gradient background,
  /// border). Defaults to `true`. Set `false` on content-only painters during
  /// state-transition crossfade so the fill is drawn exactly once.
  final bool paintFill;

  /// Whether to draw the content layer (dot, text, waveform, icons, timeline).
  /// Defaults to `true`. Set `false` on the background painter during
  /// state-transition crossfade so only the fill is drawn.
  final bool paintContent;

  /// Optional override for the rendered pill width in logical pixels (issue 10).
  ///
  /// When non-null the pill is drawn **centred** within [sizeSpec.width]:
  /// `left = shadowPadding + (sizeSpec.width − pillWidth) / 2`.
  /// When null the full [sizeSpec.width] is used (default steady-state).
  /// Height and corner radius are unaffected.
  final double? pillWidth;

  /// Reveal fraction (`[0, 1]`) for the done/error status icon, driven by the
  /// host widget's state-transition crossfade so the icon draws on as the
  /// new state fades in instead of appearing instantly fully formed. Defaults
  /// to `1.0` (fully drawn) for every steady-state paint — the settings
  /// preview and the outgoing crossfade layer never pass anything else.
  final double iconRevealFraction;

  bool get _isRecording => state == OverlayDesignState.recording;

  @override
  void paint(Canvas canvas, Size size) {
    // Dynamic pill width: when narrower than the full spec width the pill is
    // centred so that both sides shrink symmetrically. Content (dot, text,
    // waveform) is clipped to the pill and auto-reflowts via pill.left/right.
    final effectiveWidth = pillWidth ?? sizeSpec.width;
    final pill = Rect.fromLTWH(
      OverlayDesignSpec.shadowPadding + (sizeSpec.width - effectiveWidth) / 2,
      OverlayDesignSpec.shadowPadding,
      effectiveWidth,
      sizeSpec.height,
    );
    final radius = sizeSpec.capsuleRadius;
    final rrect = RRect.fromRectAndRadius(
      pill.deflate(1),
      Radius.circular(radius),
    );

    if (paintFill) {
      _drawShadow(canvas, rrect);
      _drawFill(canvas, rrect, pill);
      _drawGlassSheen(canvas, rrect, pill);
      _drawBorder(canvas, rrect);
    }

    if (paintContent) {
      // Content layer — clipped to the capsule, always fully opaque.
      canvas.save();
      canvas.clipRRect(rrect);
      _drawContent(canvas, pill);
      canvas.restore();
    }
  }

  // ── Chrome ────────────────────────────────────────────────────────────────────

  void _drawShadow(Canvas canvas, RRect rrect) {
    // Two-layer ambient depth (mirrors WpShadows.card elsewhere in the app):
    // a soft, wide-blur layer that reads as the capsule hovering, plus a
    // tight contact shadow that grounds it against the desktop directly
    // beneath it.
    canvas.drawRRect(
      rrect.shift(OverlayDesignSpec.contactShadowOffset),
      Paint()
        ..color = OverlayDesignSpec.shadowColor.withValues(
          alpha: OverlayDesignSpec.contactShadowOpacity,
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.contactShadowBlur,
        ),
    );
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

  /// Faux-glass sheen (task #38): a top-down white highlight plus a bright inner
  /// rim that reads as a glass edge, giving the translucent capsule its frosted
  /// feel without any OS blur. Cross-platform — drawn identically everywhere.
  ///
  /// A faint state-coloured undertone is blended into the lower stop (glass
  /// polish pass): the glass reads as picking up a hint of the current state's
  /// colour rather than staying neutral white-to-clear in every state — still
  /// bounded strictly inside the capsule shape, no blur, no glow.
  void _drawGlassSheen(Canvas canvas, RRect rrect, Rect pill) {
    const sheen = OverlayDesignSpec.glassSheenOpacity;
    final stateTint = OverlayDesignSpec.stateGradients[state]!.stops.first;
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: sheen),
            const Color(0x00FFFFFF),
            stateTint.withValues(
              alpha: OverlayDesignSpec.sheenStateTintOpacity,
            ),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(pill),
    );
    // Bright glass rim over the tinted border (drawn here so the border still
    // overlays it for the colour accent).
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0xFFFFFFFF).withValues(alpha: sheen * 0.9),
    );
  }

  /// Hairline capsule border, re-hued to the current state's leading accent
  /// colour (glass polish pass) — the same stroke the spike always drew, just
  /// no longer a single fixed accent tint for every state. Lets recording
  /// (red), transcribing (amber), done (green) and error (red) read apart
  /// from the capsule edge alone.
  void _drawBorder(Canvas canvas, RRect rrect) {
    final borderColor = OverlayDesignSpec.borderColorFor(state, colors);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = borderColor,
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
        _drawCheckIcon(canvas, leadCenter, colors.success, iconRevealFraction);
      case OverlayDesignState.error:
        _drawErrorIcon(canvas, leadCenter, colors.error, iconRevealFraction);
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
    final minAlpha = OverlayDesignSpec.motion.dotPulseMinAlpha;
    final minScale = OverlayDesignSpec.motion.dotPulseMinScale;
    final alpha = minAlpha + (1.0 - minAlpha) * dotPulse;
    final scale = minScale + (1.0 - minScale) * dotPulse;
    canvas.drawCircle(
      center,
      layout.dotRadius * scale,
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
    // Small bright lead dot pinpointing the exact current position, sharper
    // feedback than the fading line end alone (glass polish pass).
    canvas.drawCircle(
      Offset(end, lineY),
      OverlayDesignSpec.timelineLeadDotRadius,
      Paint()..color = colors.accent,
    );
  }

  /// Draws the done checkmark, revealing it stroke-first as [reveal] runs
  /// 0→1 (glass polish pass) so it draws on as the done state fades in
  /// instead of appearing instantly fully formed. `reveal = 1.0` (every
  /// steady-state paint) draws the complete glyph exactly as before.
  void _drawCheckIcon(Canvas canvas, Offset center, Color tint, double reveal) {
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
    if (reveal >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }
    final metrics = path.computeMetrics().toList();
    final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var remaining = totalLength * reveal.clamp(0.0, 1.0);
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = math.min(remaining, metric.length);
      canvas.drawPath(metric.extractPath(0, take), paint);
      remaining -= take;
    }
  }

  /// Draws the error icon as a calm fade-and-settle: scale runs
  /// [OverlayDesignSpec.errorIconRevealScaleStart] → 1.0 as [reveal] runs 0→1
  /// (glass polish pass), the same no-overshoot register the capsule's own
  /// appear spring uses, applied to a single icon instead. `reveal = 1.0`
  /// (every steady-state paint) draws the complete glyph at full scale,
  /// exactly as before.
  void _drawErrorIcon(Canvas canvas, Offset center, Color tint, double reveal) {
    final r = sizeSpec.statusIconSize / 2;
    final stroke = math.max(1.5, sizeSpec.statusIconSize * 0.12);
    final clamped = reveal.clamp(0.0, 1.0);
    const scaleStart = OverlayDesignSpec.errorIconRevealScaleStart;
    final scale = scaleStart + (1.0 - scaleStart) * clamped;
    final alpha = tint.a * clamped;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    final scaledTint = tint.withValues(alpha: alpha);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = scaledTint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - r * 0.45),
      Offset(center.dx, center.dy + r * 0.12),
      Paint()
        ..color = scaledTint
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(center.dx, center.dy + r * 0.5),
      math.max(0.8, sizeSpec.statusIconSize * 0.06),
      Paint()..color = scaledTint,
    );
    canvas.restore();
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
        old.paintFill != paintFill ||
        old.paintContent != paintContent ||
        old.pillWidth != pillWidth ||
        old.iconRevealFraction != iconRevealFraction ||
        !identical(old.waveformBars, waveformBars);
  }
}

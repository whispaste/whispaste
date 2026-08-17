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
class WpOverlayPainter extends CustomPainter {
  /// Creates a painter for one immutable overlay frame.
  ///
  /// [paintFill] and [paintContent] let the host widget split the draw into two
  /// independent layers for the state-transition crossfade: the fill layer
  /// (shadow + gradient capsule background) is drawn once, while only the
  /// content layer (dot, text, waveform, icons) is crossfaded. Drawing the
  /// semi-transparent fill twice at different opacities would darken the capsule
  /// during the transition; this flag pair prevents that.
  const WpOverlayPainter({
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
    this.glassPhase = 0.0,
    this.liquidMotion = 0.0,
    this.liquidLevel = 0.0,
    this.style = OverlayStyleVariant.glass,
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
  /// Empty outside the recording state — the transcribing state instead
  /// synthesises a travelling ripple via [transcribingBarLevel].
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

  /// Liquid-glass drift phase (`[0, 1)` loop), driven by the host's slow
  /// ticker. Phase 0 renders the exact static frame (reduced-motion + golden
  /// baseline); the sinusoidal modulation keeps every excursion within the
  /// researched ≤ 6 px premium-drift bound. Neutral white light only —
  /// a drifting highlight, never a sweeping shimmer band (ADR 0002).
  final double glassPhase;

  /// Master switch/scale (`[0, 1]`) for the liquid silhouette wobble. The
  /// host passes 1.0 while animating and 0.0 under reduced motion or in the
  /// static settings preview — 0.0 renders the perfectly rigid capsule
  /// (golden baseline).
  final double liquidMotion;

  /// Smoothed live audio level (`[0, 1]`) — adds the louder-speech
  /// deformation on top of the base "Windhauch" wobble (explicit maintainer
  /// wish, 2026-07-30 interview). 0 outside recording.
  final double liquidLevel;

  /// The chrome style to render — [OverlayStyleVariant.glass] (default) or
  /// [OverlayStyleVariant.solid]. Only affects [_drawFill]/[_drawGlassSheen];
  /// the shadow, border, content, waveform and liquid silhouette wobble are
  /// identical in both styles and for all three [sizeSpec] variants.
  final OverlayStyleVariant style;

  bool get _isRecording => state == OverlayDesignState.recording;

  @override
  void paint(Canvas canvas, Size size) {
    // Dynamic pill width: when narrower than the full spec width the pill is
    // centred so that both sides shrink symmetrically. Content (dot, text,
    // waveform) is clipped to the pill and auto-reflows via pill.left/right.
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

    // Liquid silhouette (Gummibärchen im Windhauch): the capsule outline is
    // deformed by two slow travelling waves; amplitude = base wobble plus an
    // audio-level share. 0 → a plain RRect path (rigid, golden baseline).
    final baseAmp =
        liquidMotion * OverlayDesignSpec.liquidWobbleBaseAmplitudePx;
    final audioAmp =
        liquidMotion *
        OverlayDesignSpec.liquidWobbleAudioAmplitudePx *
        liquidLevel.clamp(0.0, 1.0);
    final shape = _liquidShape(rrect, baseAmp, audioAmp);

    if (paintFill) {
      _drawShadow(canvas, shape);
      _drawFill(canvas, shape, pill);
      if (style == OverlayStyleVariant.glass) {
        _drawGlassSheen(canvas, shape, rrect, baseAmp, audioAmp, pill);
      }
      _drawBorder(canvas, shape);
    }

    if (paintContent) {
      // Content layer — clipped to the capsule, always fully opaque.
      canvas.save();
      canvas.clipPath(shape);
      _drawContent(canvas, pill);
      canvas.restore();
    }
  }

  /// Builds the (possibly liquid-deformed) capsule outline.
  ///
  /// Both amplitudes 0 returns the plain rigid capsule. Otherwise the
  /// perimeter is
  /// sampled into [OverlayDesignSpec.liquidWobbleSamples] equidistant points
  /// via [PathMetrics]; each point is displaced along its normal by two
  /// counter-travelling low-frequency waves (2 and 3 periods around the
  /// perimeter, 1 and 2 time-cycles per glass loop — integer cycles keep the
  /// motion seamless at the phase wrap), then closed with Catmull-Rom
  /// smoothing so the result reads as organic bulges, never jitter.
  Path _liquidShape(RRect base, double baseAmp, double audioAmp) {
    final basePath = Path()..addRRect(base);
    if (baseAmp <= 0 && audioAmp <= 0) return basePath;

    final metric = basePath.computeMetrics().first;
    final length = metric.length;
    const n = OverlayDesignSpec.liquidWobbleSamples;
    final points = List<Offset>.generate(n, (i) {
      final u = i / n;
      final tangent = metric.getTangentForOffset(u * length)!;
      final normal = Offset(tangent.vector.dy, -tangent.vector.dx);
      // Wind: two slow counter-travelling low-frequency waves.
      final wind =
          math.sin(2 * math.pi * (2 * u + glassPhase)) * 0.6 +
          math.sin(2 * math.pi * (3 * u - 2 * glassPhase) + 1.7) * 0.4;
      // Voice: its OWN faster, finer ripple (5 perimeter periods, 6 time-
      // cycles per loop) — reads as a distinct reaction to speech, not as
      // "more wind".
      final ripple = math.sin(2 * math.pi * (5 * u - 6 * glassPhase));
      return tangent.position + normal * (baseAmp * wind + audioAmp * ripple);
    }, growable: false);

    // Closed Catmull-Rom spline through the displaced points (uniform,
    // tension 0.5 → standard `(p2 − p0) / 6` cubic control points).
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  // ── Chrome ────────────────────────────────────────────────────────────────────

  void _drawShadow(Canvas canvas, Path shape) {
    // Two-layer ambient depth (mirrors WpShadows.card elsewhere in the app):
    // a soft, wide-blur layer that reads as the capsule hovering, plus a
    // tight contact shadow that grounds it against the desktop directly
    // beneath it.
    //
    // Knocked OUT under the capsule (Dock-glass pass, 2026-07-29): with the
    // near-clear fill the blurred shadow ink INSIDE the silhouette showed
    // through the glass and greyed it ("noch zu grau"). Clipping the shadow
    // to the exterior keeps the float depth while the glass body itself
    // stays clear.
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(shape.getBounds().inflate(48)),
        shape,
      ),
    );
    canvas.drawPath(
      shape.shift(OverlayDesignSpec.contactShadowOffset),
      Paint()
        ..color = OverlayDesignSpec.shadowColor.withValues(
          alpha: OverlayDesignSpec.contactShadowOpacity,
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.contactShadowBlur,
        ),
    );
    canvas.drawPath(
      shape.shift(OverlayDesignSpec.shadowOffset),
      Paint()
        ..color = OverlayDesignSpec.shadowColor.withValues(
          alpha: OverlayDesignSpec.shadowOpacity,
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.shadowBlur,
        ),
    );
    canvas.restore();
  }

  void _drawFill(Canvas canvas, Path shape, Rect pill) {
    if (style == OverlayStyleVariant.solid) {
      // Fully opaque brand fill — same gradient for all three sizes, no
      // per-size tuning (mirrors the glass fill's "one material" rule).
      canvas.drawPath(
        shape,
        Paint()
          ..shader = OverlayDesignSpec.solidFillGradient.createShader(pill),
      );
      return;
    }
    // ONE glass material for all three sizes (impeccable pass) — the sizes
    // must read as the same slab of glass, only smaller.
    const a = OverlayDesignSpec.fillOpacityFactor;
    canvas.drawPath(
      shape,
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

  /// Faux-glass sheen (task #38, refined in the Dock-glass polish pass): a
  /// top-down white highlight with a softer three-stop falloff, a faint
  /// counter-sheen rising from the bottom edge (light catching the lower glass
  /// rim — the macOS-Dock mood reference), plus a bright inner rim that reads
  /// as a glass edge. All without any OS blur; cross-platform — drawn
  /// identically everywhere. Neutral white-to-clear in every state (ADR 0002:
  /// no glow, no colour bleed) — the chrome stays state-neutral; state
  /// identity is carried by the content glyphs only.
  void _drawGlassSheen(
    Canvas canvas,
    Path shape,
    RRect baseRRect,
    double baseAmp,
    double audioAmp,
    Rect pill,
  ) {
    const sheen = OverlayDesignSpec.glassSheenOpacity;
    // Liquid-glass drift: one slow sinusoidal cycle moves the light layers a
    // few pixels; secondary modulations run at double frequency so all of
    // them are 0 at phase 0 (static baseline frame).
    final wave = math.sin(2 * math.pi * glassPhase);
    final breathe = math.sin(4 * math.pi * glassPhase);
    final drift = wave * OverlayDesignSpec.liquidSpecularDriftPx;
    // Top-down highlight on CURVED glass: the shader rect is pulled in from
    // the rounded end caps so the light tapers off horizontally instead of
    // running as a full-width band through the curves (Dock reference). The
    // sheen follows the specular drift at half parallax (depth cue).
    final capInset =
        sizeSpec.capsuleRadius * OverlayDesignSpec.glassSheenCapInsetFactor;
    final sheenRect = Rect.fromLTRB(
      pill.left + capInset,
      pill.top,
      pill.right - capInset,
      pill.bottom,
    ).shift(Offset(drift * OverlayDesignSpec.liquidSheenParallaxFactor, 0));
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: sheen),
            const Color(0xFFFFFFFF).withValues(alpha: sheen * 0.35),
            const Color(0x00FFFFFF),
          ],
          stops: OverlayDesignSpec.glassSheenStops,
        ).createShader(sheenRect),
    );
    // Hair-thin neutral inner shade above the bottom light — the "mass" of
    // the glass slab; without it the fill jumps straight into the bottom
    // sheen and the capsule reads flat.
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00000000),
            const Color(
              0xFF000000,
            ).withValues(alpha: OverlayDesignSpec.glassInnerShadeOpacity),
          ],
          stops: OverlayDesignSpec.glassInnerShadeStops,
        ).createShader(pill),
    );
    // Faint bottom counter-sheen — light catching the lower rim of the glass.
    const bottomSheen = sheen * OverlayDesignSpec.glassBottomSheenFactor;
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00FFFFFF),
            const Color(0xFFFFFFFF).withValues(alpha: bottomSheen),
          ],
          stops: OverlayDesignSpec.glassBottomSheenStops,
        ).createShader(pill),
    );
    // Fresnel edge treatment (Dock-glass research pass): with a near-clear
    // fill the EDGES carry the glass identity — glass reflects most at
    // grazing angles.
    //
    // 1) Soft inner Fresnel band just inside the rim: the refracting
    //    "thickness" of the slab, fading downward.
    canvas.drawPath(
      _liquidShape(
        baseRRect.deflate(OverlayDesignSpec.glassInnerRimInset),
        baseAmp * 0.8,
        audioAmp * 0.8,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = OverlayDesignSpec.glassInnerRimWidth
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(
              0xFFFFFFFF,
            ).withValues(alpha: OverlayDesignSpec.glassInnerRimOpacity),
            const Color(0x00FFFFFF),
          ],
        ).createShader(pill),
    );
    // 2) Crisp specular streak along the top edge — the Dock's signature
    //    reflection. Drifts ±12 px, breathes in length AND brightness with
    //    the liquid-glass phase (visibility pass 2026-07-30); still an
    //    anchored highlight, never a sweeping band (ADR 0002).
    final specularHalf =
        (pill.width * OverlayDesignSpec.glassSpecularWidthFactor) /
        2 *
        (1 + OverlayDesignSpec.liquidSpecularBreatheFactor * breathe);
    final specularY = pill.top + OverlayDesignSpec.glassSpecularInsetTop;
    final specularCx = pill.center.dx + drift;
    // Soft dark under-halo: the measured fix for light desktops — white on
    // near-white saturates to Δ0, so the streak brings its own local
    // contrast floor (same principle as the glyph shadows).
    canvas.drawLine(
      Offset(
        specularCx - specularHalf,
        specularY + OverlayDesignSpec.glassSpecularHaloOffsetY,
      ),
      Offset(
        specularCx + specularHalf,
        specularY + OverlayDesignSpec.glassSpecularHaloOffsetY,
      ),
      Paint()
        ..color = OverlayDesignSpec.glyphShadowColor.withValues(
          alpha: OverlayDesignSpec.glassSpecularHaloOpacity,
        )
        ..strokeWidth = OverlayDesignSpec.glassSpecularHaloStrokeWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.glassSpecularHaloBlurSigma,
        ),
    );
    canvas.drawLine(
      Offset(specularCx - specularHalf, specularY),
      Offset(specularCx + specularHalf, specularY),
      Paint()
        ..strokeWidth = OverlayDesignSpec.glassSpecularStrokeWidth
        ..strokeCap = StrokeCap.round
        ..shader =
            LinearGradient(
              colors: [
                const Color(0x00FFFFFF),
                const Color(0xFFFFFFFF).withValues(
                  alpha:
                      (OverlayDesignSpec.glassSpecularOpacity *
                              (1 +
                                  OverlayDesignSpec
                                          .liquidSpecularBrightBreatheFactor *
                                      breathe))
                          .clamp(0.0, 1.0),
                ),
                const Color(0x00FFFFFF),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(
              Rect.fromLTWH(
                pill.center.dx - specularHalf,
                specularY - 1,
                specularHalf * 2,
                2,
              ),
            ),
    );
    // 3) 1 px outer rim, lit from above: bright top edge fading to nearly
    //    off at the bottom — a uniform white outline would read as a stroke,
    //    not as edge light. Follows the liquid silhouette.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(
              alpha:
                  (OverlayDesignSpec.glassRimTopOpacity *
                          (1 +
                              OverlayDesignSpec.liquidRimBreatheFactor *
                                  breathe))
                      .clamp(0.0, 1.0),
            ),
            const Color(
              0xFFFFFFFF,
            ).withValues(alpha: OverlayDesignSpec.glassRimBottomOpacity),
          ],
        ).createShader(pill),
    );
  }

  /// Fixed accent hairline capsule border — deliberately state-NEUTRAL
  /// (maintainer decision, 2026-07-28): the former per-state re-hue read as a
  /// diffuse red/pink glow on the small translucent capsule, so the chrome
  /// (fill, sheen, border, shadow) carries no state colour anywhere. State
  /// identity lives only in the crisp content glyphs (dot, waveform, icons).
  void _drawBorder(Canvas canvas, Path shape) {
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = colors.capsuleBorder,
    );
  }

  // ── Content (always opaque) ─────────────────────────────────────────────────

  void _drawContent(Canvas canvas, Rect pill) {
    if (sizeSpec.minimalContent) {
      _drawMinimalContent(canvas, pill);
      return;
    }

    final cy = pill.center.dy;
    final base = pill.left + layout.padH;

    _drawClose(canvas, Offset(base + layout.closeOffset, cy));

    // Transcribing has its own shared composition (label in the amber
    // processing stream) — identical across all three sizes.
    if (state == OverlayDesignState.transcribing) {
      _drawTranscribing(canvas, pill);
      return;
    }

    // Leading glyph: pulsing accent dot (recording) or the done/error
    // status icon (transcribing returned above).
    final leadCenter = Offset(base + layout.dotInset, cy);
    switch (state) {
      case OverlayDesignState.recording:
        _drawDot(canvas, leadCenter);
      case OverlayDesignState.transcribing:
        break; // Handled by _drawTranscribing above.
      case OverlayDesignState.done:
        _drawCheckIcon(canvas, leadCenter, colors.success, iconRevealFraction);
      case OverlayDesignState.error:
        _drawErrorIcon(canvas, leadCenter, colors.error, iconRevealFraction);
    }

    // Universal-legibility scheme (2026-07-29): ALL text renders as white
    // glyphs with a dark outline (subtitle/map-label technique) so it stays
    // readable over any desktop behind the near-clear glass. State semantics
    // live in the dot and the done/error icons, not in text colour.
    const textColor = OverlayDesignSpec.contentGlyphFill;
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

    // Waveform + stop square (recording only — live bars).
    if (_isRecording) {
      final stopSize = layout.stopSize;
      final waveLeft = textLeft + textWidth + layout.waveStartGap;
      final waveRight = pill.right - layout.padH - stopSize - layout.waveEndGap;
      _drawWaveform(canvas, waveLeft, waveRight, cy, pill.height);
      _drawStop(canvas, Offset(pill.right - layout.padH - stopSize / 2, cy));
    }

    // Inset accent progress timeline (recording only).
    if (_isRecording && progress > 0) {
      _drawTimeline(canvas, pill);
    }
  }

  /// Mini (waveform-first) content: the waveform IS the overlay while
  /// recording — a small pulsing dot plus live bars spanning the remaining
  /// width. Transcribing renders the shared label-in-the-stream composition
  /// ([_drawTranscribing]) — the same one normal/compact paint, so all three
  /// sizes speak one language. Done/error collapse to a single centred
  /// status icon. No close glyph, no timer, no stop square. The thin
  /// progress timeline is kept: it is the only max-duration feedback.
  void _drawMinimalContent(Canvas canvas, Rect pill) {
    final cy = pill.center.dy;
    final base = pill.left + layout.padH;

    switch (state) {
      case OverlayDesignState.recording:
        final dotCenter = Offset(base + layout.dotInset, cy);
        _drawDot(canvas, dotCenter);
        final waveLeft = dotCenter.dx + layout.timerGap;
        final waveRight = pill.right - layout.padH;
        _drawWaveform(
          canvas,
          waveLeft,
          waveRight,
          cy,
          pill.height,
          maxHeight: sizeSpec.waveformMaxHeight,
        );
      case OverlayDesignState.transcribing:
        _drawTranscribing(canvas, pill);
      case OverlayDesignState.done:
        _drawCheckIcon(canvas, pill.center, colors.success, iconRevealFraction);
      case OverlayDesignState.error:
        _drawErrorIcon(canvas, pill.center, colors.error, iconRevealFraction);
    }

    if (_isRecording && progress > 0) {
      _drawTimeline(canvas, pill);
    }
  }

  /// The transcribing composition, shared by ALL three sizes (waveform+text
  /// pass, 2026-08-17): the amber rotating spinner leads, the localized
  /// status label follows, and the amber processing-ripple waveform spans
  /// the FULL remaining zone BEHIND the label. The bars directly beneath the
  /// label sink toward the rest baseline through a smoothstep notch envelope
  /// ([notchAttenuation]) — the stream visibly parts around the label and
  /// the travelling ripple flows through the notch, so text and waveform
  /// coexist without an ellipsis fight over the width (the label keeps its
  /// full measured width; the earlier text-only cut read as "nur reiner
  /// Text" on mini/compact).
  ///
  /// Paint cost stays hot-path-neutral: the label is laid out exactly once
  /// (the same single fill layout [_drawText] always did — it is built early
  /// only because the notch needs its width before the bars are painted),
  /// and the notch itself is one smoothstep per bar.
  void _drawTranscribing(Canvas canvas, Rect pill) {
    final cy = pill.center.dy;
    final base = pill.left + layout.padH;
    final spinnerCenter = Offset(base + layout.dotInset, cy);
    _drawSpinner(canvas, spinnerCenter);

    final textLeft = spinnerCenter.dx + layout.timerGap;
    final maxTextWidth = pill.right - layout.padH - textLeft;
    final baseStyle = _textStyle(layout.timerFontSize);
    final fillTp = statusText.isEmpty
        ? null
        : _layoutTextPainter(
            statusText,
            baseStyle.copyWith(color: OverlayDesignSpec.contentGlyphFill),
            maxTextWidth,
          );
    final textWidth = fillTp?.width ?? 0.0;

    _drawWaveform(
      canvas,
      textLeft,
      pill.right - layout.padH,
      cy,
      pill.height,
      maxHeight: sizeSpec.minimalContent ? sizeSpec.waveformMaxHeight : null,
      notchStart: textLeft - OverlayDesignSpec.transcribingWaveNotchPadPx,
      notchEnd:
          textLeft + textWidth + OverlayDesignSpec.transcribingWaveNotchPadPx,
    );

    if (fillTp != null) {
      _paintLaidOutText(
        canvas,
        statusText,
        fillTp,
        Offset(textLeft, cy),
        baseStyle,
        maxTextWidth,
      );
    }
  }

  void _drawClose(Canvas canvas, Offset center) {
    final arm = layout.closeArm;
    void strokes(Offset at, Paint paint) {
      canvas.drawLine(at + Offset(-arm, -arm), at + Offset(arm, arm), paint);
      canvas.drawLine(at + Offset(arm, -arm), at + Offset(-arm, arm), paint);
    }

    // Soft glyph shadow (final legibility scheme): blurred dark pass
    // beneath the white strokes — readable over any desktop.
    strokes(
      center + OverlayDesignSpec.glyphShadowOffset,
      Paint()
        ..color = OverlayDesignSpec.glyphShadowColor.withValues(
          alpha: OverlayDesignSpec.glyphShadowOpacity,
        )
        ..strokeWidth = layout.closeStroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.glyphShadowBlurSigma,
        ),
    );
    strokes(
      center,
      Paint()
        ..color = OverlayDesignSpec.contentGlyphFill
        ..strokeWidth = layout.closeStroke
        ..strokeCap = StrokeCap.round,
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

  /// Transcribing "working" glyph (state-distinction pass, 2026-08-17): a
  /// small rotating open arc over a faint full-circle track, in the state's
  /// own amber [OverlayThemeColors.transcribingAccent] — clearly a machine
  /// working, where the recording state's pulsing cyan dot is a microphone
  /// listening. Rotation rides the existing liquid-glass phase
  /// ([OverlayDesignSpec.transcribingSpinnerTurnsPerLoop] integer turns per
  /// loop → seamless at the phase wrap, no extra AnimationController, one
  /// arc + one circle of paint cost). Reduced-motion and the static settings
  /// preview rest at the phase-0 frame — a fully formed static spinner
  /// glyph, exactly like every other phase-driven motion in this painter.
  void _drawSpinner(Canvas canvas, Offset center) {
    final r =
        layout.dotRadius * OverlayDesignSpec.transcribingSpinnerRadiusFactor;
    final stroke = math.max(
      OverlayDesignSpec.transcribingSpinnerMinStrokePx,
      layout.dotRadius * OverlayDesignSpec.transcribingSpinnerStrokeFactor,
    );
    final rect = Rect.fromCircle(center: center, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // Faint closed track beneath the bright arc: anchors the glyph as a
    // spinner (not a stray crescent) over busy desktops.
    paint.color = colors.transcribingAccent.withValues(
      alpha: OverlayDesignSpec.transcribingSpinnerTrackOpacity,
    );
    canvas.drawCircle(center, r, paint);
    final start =
        2 *
            math.pi *
            OverlayDesignSpec.transcribingSpinnerTurnsPerLoop *
            glassPhase -
        math.pi / 2;
    paint.color = colors.transcribingAccent;
    canvas.drawArc(
      rect,
      start,
      OverlayDesignSpec.transcribingSpinnerSweep,
      false,
      paint,
    );
  }

  void _drawStop(Canvas canvas, Offset center) {
    final s = layout.stopSize;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: s, height: s),
      const Radius.circular(OverlayDesignSpec.stopSquareRadius),
    );
    // Soft glyph shadow (final legibility scheme) beneath the white square.
    canvas.drawRRect(
      rrect.shift(OverlayDesignSpec.glyphShadowOffset),
      Paint()
        ..color = OverlayDesignSpec.glyphShadowColor.withValues(
          alpha: OverlayDesignSpec.glyphShadowOpacity,
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          OverlayDesignSpec.glyphShadowBlurSigma,
        ),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = OverlayDesignSpec.contentGlyphFill.withValues(
          alpha: OverlayDesignSpec.stopSquareOpacity,
        ),
    );
  }

  /// Transcribing-state bar level: a fast travelling ripple over the flat
  /// [OverlayDesignSpec.waveformRestLevel] baseline, reusing the exact
  /// spatial/temporal ratio already established for the capsule's "voice"
  /// ripple (`_liquidShape`: 5 perimeter periods, 6 time-cycles per
  /// [OverlayDesignSpec.liquidDriftPeriod]) — the fastest existing motion in
  /// this painter, chosen because a transcription is typically only a few
  /// seconds long and needs to visibly move within that window, unlike the
  /// slow 8 s sheen drift the phase otherwise drives. Integer multipliers on
  /// [glassPhase] keep the motion seamless at the phase wrap (no jump when
  /// the driving [AnimationController] loops back to 0).
  ///
  /// Amplitude stays well under a live recording bar's headroom (see
  /// [OverlayDesignSpec.waveformTranscribingRippleAmplitude]) so the ripple
  /// reads as "processing", never as "still listening". Public and pure —
  /// no canvas needed — so it is directly unit-testable.
  @visibleForTesting
  static double transcribingBarLevel(int index, int count, double glassPhase) {
    final u = count <= 1 ? 0.0 : index / count;
    final ripple = math.sin(2 * math.pi * (5 * u - 6 * glassPhase));
    return OverlayDesignSpec.waveformRestLevel +
        OverlayDesignSpec.waveformTranscribingRippleAmplitude *
            (0.5 + 0.5 * ripple);
  }

  /// Notch envelope for the transcribing label-in-the-stream composition:
  /// attenuation factor (`[transcribingWaveNotchFloor, 1]`) applied to a
  /// bar's ripple amplitude at position [x]. `1.0` outside the label band
  /// `[start, end]`, [OverlayDesignSpec.transcribingWaveNotchFloor] inside
  /// it, joined by smoothstep shoulders of
  /// [OverlayDesignSpec.transcribingWaveNotchRampPx] on either side. Pure —
  /// directly unit-testable.
  @visibleForTesting
  static double notchAttenuation(double x, double start, double end) {
    final distOutside = x < start ? start - x : (x > end ? x - end : 0.0);
    final t = (distOutside / OverlayDesignSpec.transcribingWaveNotchRampPx)
        .clamp(0.0, 1.0);
    final smooth = t * t * (3 - 2 * t);
    const floor = OverlayDesignSpec.transcribingWaveNotchFloor;
    return floor + (1 - floor) * smooth;
  }

  void _drawWaveform(
    Canvas canvas,
    double left,
    double right,
    double cy,
    double pillHeight, {
    double? maxHeight,
    double? notchStart,
    double? notchEnd,
  }) {
    final waveW = right - left;
    if (waveW <= 20) return;
    final count = OverlayDesignSpec.waveform.barCount;
    final barW = waveW / count;
    // Mini passes an explicit maxHeight (sizeSpec.waveformMaxHeight) so the
    // waveform clears the bottom progress timeline in the 28 px pill; the
    // default keeps the spike's height-factor behaviour for normal/compact.
    final maxH =
        maxHeight ?? pillHeight * OverlayDesignSpec.waveformHeightFactor;
    // Mirrored-bar construction (Maintainer decision, 2026-07-29): fully
    // opaque filled capsules mirrored around the centre axis — hard, crisp
    // edges; no glow, no alpha wash. The "energy axis" gradient (bright
    // core at the centre line, shaded tips) is shared per bar class via one
    // shader across the wave zone, so every bar reads lit from its middle
    // and the light stays consistent while bars move.
    final zone = Rect.fromLTRB(left, cy - maxH / 2, right, cy + maxH / 2);
    // The live recording bars speak the cyan accent; the transcribing
    // processing ripple speaks the state's own amber accent — the waveform
    // keeps moving through the transition (no hard state cut) but its colour
    // says which phase owns it (state-distinction pass, 2026-08-17).
    final accent = _isRecording ? colors.accent : colors.transcribingAccent;
    final tip = Color.lerp(
      accent,
      const Color(0xFF000000),
      OverlayDesignSpec.waveformTipShadeFraction,
    )!;
    Shader coreShader(double coreLight) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        tip,
        Color.lerp(accent, const Color(0xFFFFFFFF), coreLight)!,
        tip,
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(zone);
    final mutedPaint = Paint()
      ..shader = coreShader(OverlayDesignSpec.waveformCoreMutedLightFraction);
    final activePaint = Paint()
      ..shader = coreShader(OverlayDesignSpec.waveformCoreActiveLightFraction);
    for (var i = 0; i < count; i++) {
      final x = left + i * barW + barW / 2;
      var rawLevel = _isRecording
          ? (i < waveformBars.length ? waveformBars[i].clamp(0.0, 1.0) : 0.0)
          : transcribingBarLevel(i, count, glassPhase);
      // Transcribing label notch: the ripple amplitude (never the rest
      // baseline) ducks beneath the status label so the stream parts around
      // the text instead of running through it.
      if (!_isRecording && notchStart != null && notchEnd != null) {
        rawLevel =
            OverlayDesignSpec.waveformRestLevel +
            (rawLevel - OverlayDesignSpec.waveformRestLevel) *
                notchAttenuation(x, notchStart, notchEnd);
      }
      // Perceptual display gamma: lifts quiet syllables so the waveform
      // dances instead of idling near the floor (display-only mapping).
      final level = _isRecording
          ? math.pow(rawLevel, OverlayDesignSpec.waveformLevelGamma).toDouble()
          : rawLevel;
      final active =
          _isRecording && i > count - OverlayDesignSpec.waveformActiveCount;
      // Playhead encoding: wider bar + hotter core — never a washed history.
      final wBar = math.max(
        layout.lineStrokeMin,
        barW *
            (active
                ? OverlayDesignSpec.waveformActiveBarFillFactor
                : OverlayDesignSpec.waveformBarFillFactor),
      );
      // Height floor: never below the bar's own width — a resting bar
      // becomes a perfect bead (circle), a speaking bar a capsule. Without
      // this the full round radius squashes short bars into horizontal
      // lozenges.
      final h = math.max(
        math.max(OverlayDesignSpec.waveform.minBarHeightPx, wBar),
        level * maxH,
      );
      final paint = active ? activePaint : mutedPaint;
      // The paint colour's alpha modulates the shader: fully opaque while
      // recording (maximum contrast), quieter for the decorative rest state.
      paint.color = const Color(0xFFFFFFFF).withValues(
        alpha: _isRecording
            ? (active
                  ? OverlayDesignSpec.waveformActiveOpacity
                  : OverlayDesignSpec.waveformMutedLineOpacity)
            : OverlayDesignSpec.waveformInactiveStateOpacity,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, cy), width: wBar, height: h),
          Radius.circular(wBar / 2),
        ),
        paint,
      );
    }
  }

  void _drawTimeline(Canvas canvas, Rect pill) {
    final radius = sizeSpec.capsuleRadius;
    // Per-size timeline metrics (impeccable layout pass): the shared absolute
    // inset/stroke collided with the waveform inside the 28 px mini pill.
    final lineY = pill.bottom - sizeSpec.timelineInsetBottom;
    final lineL = pill.left + radius;
    final lineR = pill.right - radius;
    final end = lineL + (lineR - lineL) * progress.clamp(0.0, 1.0);
    canvas.drawLine(
      Offset(lineL, lineY),
      Offset(end, lineY),
      Paint()
        ..strokeWidth = sizeSpec.timelineStrokeWidth
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
      sizeSpec.timelineLeadDotRadius,
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

  /// The shared single-line status/timer text style at [fontSize].
  TextStyle _textStyle(double fontSize) => TextStyle(
    fontFamily: 'Inter',
    fontSize: fontSize,
    fontWeight: OverlayDesignSpec.primaryFontWeight,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Lays [text] out single-line in [style], ellipsised at [maxWidth].
  TextPainter _layoutTextPainter(
    String text,
    TextStyle style,
    double? maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(
      maxWidth: maxWidth != null && maxWidth > 0 ? maxWidth : double.infinity,
    );
    return tp;
  }

  /// Paints an already laid-out [fillTp] left-anchored at [leftCenter],
  /// beneath the universal-legibility soft glyph shadow (a blurred dark pass
  /// of the same [text] that keeps the white glyphs readable over any
  /// desktop). Split from [_drawText] so [_drawTranscribing] can measure the
  /// label before the waveform is painted behind it, at the same total
  /// layout cost.
  void _paintLaidOutText(
    Canvas canvas,
    String text,
    TextPainter fillTp,
    Offset leftCenter,
    TextStyle baseStyle,
    double? maxWidth,
  ) {
    final origin = Offset(leftCenter.dx, leftCenter.dy - fillTp.height / 2);
    final shadowTp = _layoutTextPainter(
      text,
      baseStyle.copyWith(
        foreground: Paint()
          ..color = OverlayDesignSpec.glyphShadowColor.withValues(
            alpha: OverlayDesignSpec.glyphShadowOpacity,
          )
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            OverlayDesignSpec.glyphShadowBlurSigma,
          ),
      ),
      maxWidth,
    );
    shadowTp.paint(canvas, origin + OverlayDesignSpec.glyphShadowOffset);
    fillTp.paint(canvas, origin);
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
    final baseStyle = _textStyle(fontSize);
    final fillTp = _layoutTextPainter(
      text,
      baseStyle.copyWith(color: color),
      maxWidth,
    );
    _paintLaidOutText(canvas, text, fillTp, leftCenter, baseStyle, maxWidth);
    return fillTp.width;
  }

  @override
  bool shouldRepaint(covariant WpOverlayPainter old) {
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
        old.glassPhase != glassPhase ||
        old.liquidMotion != liquidMotion ||
        old.liquidLevel != liquidLevel ||
        old.style != style ||
        !identical(old.waveformBars, waveformBars);
  }
}

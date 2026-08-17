/// Single Source of Truth for the floating-overlay and floating-button look.
///
/// One Dart representation of every dimension, colour (dark/light),
/// typography, per-state layout, animation timing, waveform parameter and the
/// shared interaction constants. This spec is the **only** source — the native
/// window shells and the shared `CustomPainter` (issues 05/07/08) consume it;
/// no renderer and no widget defines its own constants any more.
///
/// Binding decisions baked in here (PRD §D4, ADR 0002):
/// - **No Privacy-Badge** — the concept is anti-vocabulary and is absent from
///   this model.
/// - State colours (recording/transcribing/done/error) and the cyan accent
///   (dark `#38D9F0` / light `#0887A8`) are taken from the current macOS values
///   and finalised here.
/// - The done gradient's middle stop is the canonical green `#30C065`.
/// - **Compact = scaled, not reduced.** The waveform bar count is identical for
///   both sizes (no 8-vs-30 split); compact content metrics are derived from
///   the normal spec by [OverlayDesignSpec.compactScale].
/// - **Mini = reduced by design.** The third size ([OverlaySizeSpec.mini]) is
///   the sanctioned exception: a waveform-first micro capsule with explicit
///   hand-tuned anchors, extra-translucent chrome and minimal content. The
///   waveform bar count stays identical across ALL sizes.
/// - **Calm UI** — no glows, no harsh effects; soft/slow timings.
/// - **Accessibility:** the opacity setting affects ONLY the pill fill
///   ([OverlayDesignSpec.fillOpacityFactor] × opacity); text, icons and the
///   waveform stay fully opaque. The recommended slider floor is
///   [OverlayDesignSpec.minRecommendedOpacity].
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'colors.dart' show WpColorsDark;

/// The four real recording states the overlay and button render.
///
/// Mirrors `OverlayVisualState` (recording/transcribing/done/error). There is
/// deliberately no `processing` state and no privacy badge.
enum OverlayDesignState { recording, transcribing, done, error }

/// The three overlay size variants.
///
/// - [normal]: the full pill (timer, waveform, close/stop, status text).
/// - [compact]: the same content scaled down ("scaled, not reduced").
/// - [mini]: the waveform-first variant — a small, extra-translucent capsule
///   whose content is deliberately REDUCED to (almost) only the waveform.
///   Status identity stays readable through the crisp content glyphs (pulsing
///   dot, live waveform, done/error status icons); timer text, close glyph
///   and stop square are omitted by design ([OverlaySizeSpec.minimalContent]).
enum OverlaySizeVariant {
  /// Full-size pill.
  normal,

  /// Scaled-down pill with identical content.
  compact,

  /// Waveform-first micro pill (extra translucent, minimal content).
  mini;

  /// Resolves a persisted/serialised name; unknown or null → [normal].
  static OverlaySizeVariant fromName(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => OverlaySizeVariant.normal,
  );
}

/// Theme variants the spec provides a complete colour set for.
enum OverlayDesignTheme { dark, light }

/// The two chrome styles the overlay pill can render.
///
/// [glass] is the default translucent no-blur "Dock glass" chrome. [solid] is
/// the fully opaque alternative (Settings: "Overlay-Stil") — same geometry,
/// same waveform, same liquid silhouette wobble, but the sheen/rim/specular
/// glass layers are skipped and the fill is the app's own [WpColorsDark.
/// frameGradient] instead of a near-clear tint. Applies identically to all
/// three [OverlaySizeVariant]s.
enum OverlayStyleVariant {
  glass,
  solid;

  /// Resolves a persisted/serialised name; unknown or null → [glass].
  static OverlayStyleVariant fromName(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => OverlayStyleVariant.glass,
  );
}

/// Supported anchor positions for the overlay window.
///
/// Mirrors the persisted `OverlayStartPosition`: a fixed top/bottom centre
/// anchor or the user's last dragged position.
enum OverlayAnchor { topCenter, bottomCenter, lastPosition }

/// A complete, theme-resolved colour set for one theme (dark or light).
///
/// Every field is non-null for both themes — the spec never leaves a theme
/// half-defined.
@immutable
class OverlayThemeColors {
  const OverlayThemeColors({
    required this.capsuleFillStart,
    required this.capsuleFillEnd,
    required this.capsuleBorder,
    required this.text,
    required this.accent,
    required this.success,
    required this.error,
    required this.recordingDot,
  });

  /// Top-left stop of the capsule's tint gradient fill (approved spike design:
  /// light `#F7FAFD`). The gradient runs top-left → bottom-right and is part of
  /// the translucent pill chrome scaled by the opacity setting.
  final Color capsuleFillStart;

  /// Bottom-right stop of the capsule's tint gradient fill (light `#E6EEF5`).
  final Color capsuleFillEnd;

  /// Accent-tinted hairline capsule border (light `#330887A8`).
  final Color capsuleBorder;

  /// Content ink — since the universal-legibility scheme (2026-07-29) no
  /// longer the glyph FILL but the dark OUTLINE around the white glyphs
  /// ([OverlayDesignSpec.contentGlyphFill]).
  final Color text;

  /// Cyan accent — spinner, waveform active bars, unlimited-progress line.
  final Color accent;

  /// Success colour — done check + message.
  final Color success;

  /// Error colour — error icon + message.
  final Color error;

  /// Recording dot — fixed across themes.
  final Color recordingDot;
}

/// A per-state accent gradient (2 or 3 colour stops).
///
/// Theme-independent: these sit on the pill surface and read in both themes.
@immutable
class OverlayStateGradient {
  const OverlayStateGradient(this.stops);

  /// Ordered colour stops, top-left → bottom-right.
  final List<Color> stops;
}

/// Waveform render parameters. Bar count is **shared** across sizes — compact
/// shows the same number of bars as normal, just shorter (PRD §D4).
@immutable
class WaveformSpec {
  const WaveformSpec({
    required this.barCount,
    required this.minBarHeightPx,
    required this.activeColorThreshold,
    required this.activeAccentOpacity,
    required this.mutedOpacity,
    required this.attackTimeConstantMs,
    required this.releaseTimeConstantMs,
  });

  /// Number of bars in the rendered snapshot — identical for both sizes.
  final int barCount;

  /// Hard floor for every bar in logical pixels.
  final double minBarHeightPx;

  /// A bar at or above this normalised level renders in the active accent
  /// tint; below it renders muted.
  final double activeColorThreshold;

  /// Opacity applied to the accent colour for active bars (accent tint).
  final double activeAccentOpacity;

  /// Opacity applied to the muted colour for inactive bars.
  final double mutedOpacity;

  /// Smoothing time constant (ms) for the **rising** edge of the live level —
  /// how fast a bar climbs when the speaker gets louder. Short, so loud onsets
  /// register promptly (volume-faithful amplitude).
  final double attackTimeConstantMs;

  /// Smoothing time constant (ms) for the **falling** edge of the live level —
  /// how fast a bar decays toward the floor during a pause. Longer than
  /// [attackTimeConstantMs] so a pause visibly fades the waveform to the min
  /// height instead of snapping flat (silence → nearly flat, no floor jitter).
  final double releaseTimeConstantMs;
}

/// All geometry and typography for one overlay size (normal, compact or mini).
///
/// `width`/`height`/`cornerRadius`/`padH` are deliberate per-size **anchors**.
/// All other (content) metrics of the compact variant are **derived** from the
/// normal variant by [OverlayDesignSpec.compactScale] — see
/// [OverlaySizeSpec.compact]. The mini variant is the sanctioned exception to
/// "scaled, not reduced": its content is REDUCED by design (waveform-first),
/// so its metrics are explicit hand-tuned anchors — see [OverlaySizeSpec.mini].
@immutable
class OverlaySizeSpec {
  const OverlaySizeSpec({
    required this.width,
    required this.height,
    required this.cornerRadius,
    required this.padH,
    required this.dotSize,
    required this.closeButtonSize,
    required this.stopButtonSize,
    required this.statusIconSize,
    required this.waveformMaxHeight,
    required this.waveformBarWidth,
    required this.waveformBarGap,
    required this.dotTextGap,
    required this.timerWaveformGap,
    required this.pillGap,
    required this.bottomProgressHeight,
    required this.timerFontSize,
    required this.primaryFontSize,
    this.minimalContent = false,
    this.timelineInsetBottom = OverlayDesignSpec.timelineInsetBottom,
    this.timelineStrokeWidth = OverlayDesignSpec.timelineStrokeWidth,
    this.timelineLeadDotRadius = OverlayDesignSpec.timelineLeadDotRadius,
  });

  // -- Box anchors (per-size, not scaled) ------------------------------------

  /// Pill width.
  final double width;

  /// Pill height.
  final double height;

  /// Pill corner radius. A compact pill is deliberately rounder than the
  /// normal pill (relative to its size), so this is an anchor, not scaled.
  final double cornerRadius;

  /// Horizontal inner padding (left/right).
  final double padH;

  // -- Content metrics (compact = normal × compactScale) ---------------------

  /// Recording state dot diameter.
  final double dotSize;

  /// Close (cancel-X) button diameter.
  final double closeButtonSize;

  /// Stop button diameter (recording only).
  final double stopButtonSize;

  /// Done/error status icon size.
  final double statusIconSize;

  /// Maximum waveform bar height.
  final double waveformMaxHeight;

  /// Waveform bar width.
  final double waveformBarWidth;

  /// Minimum gap between waveform bars.
  final double waveformBarGap;

  /// Gap between the dot and the following text.
  final double dotTextGap;

  /// Gap between the timer and the waveform.
  final double timerWaveformGap;

  /// Gap between the close button and the first content element.
  final double pillGap;

  /// Height of the bottom progress timeline.
  final double bottomProgressHeight;

  /// Recording timer font size (bold, tabular figures).
  final double timerFontSize;

  /// Primary label/done/error text font size.
  final double primaryFontSize;

  // -- Per-size derived chrome metrics (impeccable layout pass) --------------
  //
  // Glass material (fill alpha, sheen alpha) and the waveform alpha ladder
  // are deliberately NOT per-size any more: all three sizes share ONE glass
  // and ONE ladder ([OverlayDesignSpec.fillOpacityFactor] /
  // [OverlayDesignSpec.glassSheenOpacity] / the waveform*Opacity constants),
  // so the sizes read as one material — only geometry and content density
  // vary. The timeline metrics below scale per size because the shared
  // absolute values collided with the waveform inside the 28 px mini pill
  // (6 px inset = 21 % of mini's height vs. 9 % of normal's).

  /// Whether this size renders the reduced, waveform-first content set
  /// (mini): no close glyph, no timer/status text, no stop square; the
  /// waveform is the dominant element and done/error collapse to a centred
  /// status icon. State identity stays on the content glyphs (dot/icons).
  final bool minimalContent;

  /// Bottom inset of the progress timeline for this size.
  final double timelineInsetBottom;

  /// Stroke width of the progress timeline for this size.
  final double timelineStrokeWidth;

  /// Radius of the timeline's bright lead dot for this size.
  final double timelineLeadDotRadius;

  /// Capsule corner radius — the approved spike pill is a full capsule
  /// (`height / 2` → 32 normal, 20 compact, 17 mini), not the legacy
  /// [cornerRadius].
  double get capsuleRadius => height / 2;

  /// The full normal-size spec — the canonical base all compact values scale
  /// from. Dimensions finalised here per ADR 0002.
  static const OverlaySizeSpec normal = OverlaySizeSpec(
    width: 330,
    height: 64,
    cornerRadius: 18,
    padH: 22,
    dotSize: 8,
    closeButtonSize: 36,
    stopButtonSize: 36,
    statusIconSize: 16,
    waveformMaxHeight: 24,
    waveformBarWidth: 2.5,
    waveformBarGap: 1.5,
    dotTextGap: 8,
    timerWaveformGap: 18,
    pillGap: 14,
    bottomProgressHeight: 4,
    timerFontSize: 15,
    primaryFontSize: 13,
  );

  /// The compact spec: box anchors are explicit (220×40 r20, padH 16); every
  /// content metric is [OverlayDesignSpec.compactScale] × the normal value, so
  /// compact is a true scaling of normal rather than a separate hand-tuned set.
  /// Timeline metrics overridden (quality-parity pass, 2026-07-29): with the
  /// shared 6 px inset the 2.2 px lead dot (top edge y 31.8) touched the
  /// 24 px waveform zone (bars end y 32). Inset 5 / dot 1.8 → line at 35,
  /// dot 33.2..36.8, clear of the bars.
  static final OverlaySizeSpec compact = normal._scaledContent(
    OverlayDesignSpec.compactScale,
    width: 220,
    height: 40,
    cornerRadius: 20,
    padH: 16,
    timelineInsetBottom: 5.0,
    timelineLeadDotRadius: 1.8,
  );

  /// The mini spec — the waveform-first third size (Wispr-Flow-inspired, in
  /// WhisPaste's own design language: teal accent waveform, capsule chrome,
  /// fixed accent hairline border).
  ///
  /// Deliberately NOT derived via a scale factor: mini reduces content (no
  /// timer, no close glyph, no stop square), so a pure scaling of the normal
  /// metrics has nothing meaningful to scale. Every value here is an explicit
  /// hand-tuned anchor. Glass material and waveform alphas are the SHARED
  /// ones — one design language across all three sizes (impeccable pass).
  ///
  /// Geometry sanity (mirrored-bars pass, 2026-07-29): pill raised 28 → 34
  /// so the mirrored bars can show real amplitude (Maintainer: "in der
  /// Nano-Darstellung … ein bisschen höher"). Waveform 18 px centred in
  /// 34 px → bars span y 8..26; timeline at `34 − 4 = 30` with a 1.6 px lead
  /// dot (28.4..31.6) → 2.4 px clearance.
  static const OverlaySizeSpec mini = OverlaySizeSpec(
    width: 150,
    height: 34,
    cornerRadius: 17,
    padH: 12,
    dotSize: 5,
    closeButtonSize: 18,
    stopButtonSize: 18,
    statusIconSize: 14,
    waveformMaxHeight: 18,
    waveformBarWidth: 2.0,
    waveformBarGap: 1.5,
    dotTextGap: 6,
    timerWaveformGap: 8,
    pillGap: 8,
    bottomProgressHeight: 2,
    timerFontSize: 10,
    primaryFontSize: 9,
    minimalContent: true,
    timelineInsetBottom: 4.0,
    timelineStrokeWidth: 1.5,
    timelineLeadDotRadius: 1.6,
  );

  /// Returns a copy with all content metrics scaled by [s] and the box anchors
  /// overridden by the given values. [timelineInsetBottom] /
  /// [timelineLeadDotRadius] may be overridden where the shared absolute
  /// timeline metrics would collide with the waveform zone (see compact).
  OverlaySizeSpec _scaledContent(
    double s, {
    required double width,
    required double height,
    required double cornerRadius,
    required double padH,
    double? timelineInsetBottom,
    double? timelineLeadDotRadius,
  }) {
    return OverlaySizeSpec(
      width: width,
      height: height,
      cornerRadius: cornerRadius,
      padH: padH,
      dotSize: dotSize * s,
      closeButtonSize: closeButtonSize * s,
      stopButtonSize: stopButtonSize * s,
      statusIconSize: statusIconSize * s,
      waveformMaxHeight: waveformMaxHeight * s,
      waveformBarWidth: waveformBarWidth * s,
      waveformBarGap: waveformBarGap * s,
      dotTextGap: dotTextGap * s,
      timerWaveformGap: timerWaveformGap * s,
      pillGap: pillGap * s,
      bottomProgressHeight: bottomProgressHeight * s,
      timerFontSize: timerFontSize * s,
      primaryFontSize: primaryFontSize * s,
      timelineInsetBottom:
          timelineInsetBottom ?? OverlayDesignSpec.timelineInsetBottom,
      timelineLeadDotRadius:
          timelineLeadDotRadius ?? OverlayDesignSpec.timelineLeadDotRadius,
    );
  }
}

/// Hand-tuned per-size content layout, taken verbatim from the approved spike
/// (`spike/lib/main.dart` `_drawPill`). These offsets are deliberately **not**
/// derived from [OverlayDesignSpec.compactScale] — the spike spacing is its own
/// approved truth, so the painter reads it from here instead of carrying magic
/// numbers. All values are logical pixels relative to the pill box.
@immutable
class OverlayLayoutSpec {
  const OverlayLayoutSpec({
    required this.padH,
    required this.closeArm,
    required this.closeStroke,
    required this.closeOffset,
    required this.dotInset,
    required this.dotRadius,
    required this.timerGap,
    required this.timerFontSize,
    required this.waveStartGap,
    required this.waveEndGap,
    required this.stopSize,
    required this.lineStrokeMin,
  });

  /// Inner horizontal padding (left/right), from the pill edge.
  final double padH;

  /// Half-length of one stroke of the close (✕) glyph.
  final double closeArm;

  /// Close-glyph stroke width (spike `1.6` normal / `1.4` compact).
  final double closeStroke;

  /// Close-glyph centre, measured from `left + padH`.
  final double closeOffset;

  /// Recording-dot / status-icon centre, measured from `left + padH`.
  final double dotInset;

  /// Recording-dot radius.
  final double dotRadius;

  /// Gap from the dot centre to the timer/label left edge.
  final double timerGap;

  /// Timer/label font size (semibold).
  final double timerFontSize;

  /// Gap from the timer/label right edge to the waveform left edge.
  final double waveStartGap;

  /// Gap kept between the waveform right edge and the stop square.
  final double waveEndGap;

  /// Stop-square side length (recording only).
  final double stopSize;

  /// Minimum visual waveform bar width (the filled bar is the wider of this
  /// and `slot × waveformBarFillFactor`).
  final double lineStrokeMin;

  /// Normal-size layout (spike values, `_drawPill` non-compact branch).
  static const OverlayLayoutSpec normal = OverlayLayoutSpec(
    padH: 22,
    closeArm: 4.0,
    closeStroke: 1.6,
    closeOffset: 5,
    dotInset: 28,
    dotRadius: 4.5,
    timerGap: 16,
    timerFontSize: 14,
    waveStartGap: 18,
    waveEndGap: 16,
    stopSize: 12,
    lineStrokeMin: 2.0,
  );

  /// Compact-size layout (spike values, `_drawPill` compact branch).
  /// Wave gaps trimmed 12/10 → 10/8 (quality-parity pass, 2026-07-29): +4 px
  /// waveform width in the tightest size, so compact bars keep pace with
  /// normal/mini.
  static const OverlayLayoutSpec compact = OverlayLayoutSpec(
    padH: 16,
    closeArm: 3.5,
    closeStroke: 1.4,
    closeOffset: 5,
    dotInset: 20,
    dotRadius: 3.5,
    timerGap: 12,
    timerFontSize: 12,
    waveStartGap: 10,
    waveEndGap: 8,
    stopSize: 10,
    lineStrokeMin: 1.5,
  );

  /// Mini-size layout. The mini painter branch renders only dot + waveform
  /// (+ centred status icon for done/error), so the close/stop/timer values
  /// here are conservative fallbacks that are never drawn in practice.
  static const OverlayLayoutSpec mini = OverlayLayoutSpec(
    padH: 12,
    closeArm: 3.0,
    closeStroke: 1.2,
    closeOffset: 0,
    dotInset: 4,
    dotRadius: 2.5,
    timerGap: 8,
    timerFontSize: 10,
    waveStartGap: 8,
    waveEndGap: 0,
    stopSize: 8,
    lineStrokeMin: 1.5,
  );
}

/// Platform vibrancy material for the overlay native window.
///
/// Decided in Phase-0 spike (spike-notes.md 2026-06-29):
/// - macOS: `hudWindow` — real NSVisualEffectView blur, perf ~1 ms/frame avg.
/// - Windows: `acrylic` — flutter_acrylic Acrylic (pending Windows test).
/// - Linux / unknown: `flat` — tinted capsule fill, no OS-level blur.
enum OverlayVibrancyMaterial {
  /// macOS NSVisualEffectMaterial.hudWindow (Phase-0 approved, best optics).
  hudWindow,

  /// Windows Acrylic via flutter_acrylic (planned).
  acrylic,

  /// Windows Mica via flutter_acrylic (alternative to acrylic).
  mica,

  /// Tinted flat fill, no OS blur — Linux default / universal fallback.
  flat,
}

/// Platform-aware vibrancy material selection for the overlay window.
///
/// Consumed by the platform controllers (Swift / C++ / Linux) to configure
/// the native window's visual effect layer. The Flutter widget consumes
/// [forPlatform] to select the correct fill opacity.
@immutable
class OverlayVibrancySpec {
  const OverlayVibrancySpec({
    required this.macOS,
    required this.windows,
    required this.linux,
  });

  /// Material for macOS overlay windows.
  final OverlayVibrancyMaterial macOS;

  /// Material for Windows overlay windows.
  final OverlayVibrancyMaterial windows;

  /// Material for Linux overlay windows (always flat — no OS blur available).
  final OverlayVibrancyMaterial linux;

  /// Resolves the material for the given [platform] string
  /// (`'macos'`, `'windows'`, `'linux'`). Anything unknown → [flat].
  OverlayVibrancyMaterial forPlatform(String platform) => switch (platform) {
    'macos' => macOS,
    'windows' => windows,
    'linux' => linux,
    _ => OverlayVibrancyMaterial.flat,
  };
}

/// Signature arc motion parameters.
///
/// Govern the two animated events in the recording arc:
/// 1. **Appear**: capsule springs in from [appearScale] → 1.0 + opacity 0 → 1.
///    Curve = easeOutCubic (WpMotion.spring), no overshoot, gentle.
/// 2. **State-transition crossfade**: brief opacity fade between arc states.
///
/// All durations are subject to `MediaQuery.disableAnimations` — callers must
/// use `WpMotion.durationFor(context, duration)` so reduced-motion collapses
/// everything to Duration.zero (instant state change, no movement).
@immutable
class OverlayArcMotion {
  const OverlayArcMotion({
    required this.appearDuration,
    required this.appearCurve,
    required this.appearScale,
    required this.stateTransitionDuration,
    required this.stateTransitionCurve,
    required this.releaseOutDuration,
    this.statusRevealDuration = const Duration(milliseconds: 280),
  });

  /// Duration of the crossfade OUT of the recording state into transcribing.
  ///
  /// Longer than the generic [stateTransitionDuration] on purpose: the
  /// service feeds the waveform pipeline decaying samples for
  /// [OverlayDesignSpec.waveformReleaseOutMs] after that transition, and the
  /// outgoing (recording) crossfade layer is what paints them. A shorter
  /// crossfade drops that layer mid-decay and hands over to the flat rest
  /// waveform — the abrupt waveform stop reported on the mini overlay. Keep
  /// this equal to the release-out window.
  final Duration releaseOutDuration;

  /// Duration of the crossfade INTO the done/error end states (impeccable
  /// pass). The generic 150 ms crossfade left the done check — the emotional
  /// pay-off of the whole product — half-formed; 280 ms gives the stroke-
  /// first draw-on room to land while staying inside the calm soft-cap.
  /// Recording/transcribing transitions keep [stateTransitionDuration].
  final Duration statusRevealDuration;

  /// Duration of the capsule spring-in (appear).
  ///
  /// Phase-0 cap: Soft-Cap 300 ms / Hard-Cap 700 ms. Set to [smooth] (300 ms)
  /// so the perceived snap is ~250 ms.
  final Duration appearDuration;

  /// Easing for the spring-in. Must be non-overshooting.
  ///
  /// Phase-0 decision: easeOutCubic (mirrors `WpMotion.spring`).
  final Curve appearCurve;

  /// Initial scale from which the capsule springs in (e.g. 0.88 → 1.0).
  ///
  /// Subtle — the viewer notices movement, not a dramatic jump-cut.
  final double appearScale;

  /// Duration of the state-transition crossfade (recording→transcribing etc.).
  final Duration stateTransitionDuration;

  /// Easing for the state-transition crossfade.
  final Curve stateTransitionCurve;

  /// Gentle spring for the pill-width morph (issue 10 — dynamic pill growth).
  ///
  /// Critically-damped Gentle preset (mass=1, stiffness=170, damping=26 ≈ 2√170).
  /// No overshoot; a clean, soft width transition between recording-arc states.
  /// Identical parameters to [WpMotion.springDescription]; mirrored here so
  /// [OverlayDesignSpec] consumers need only one import.
  static const SpringDescription pillSpring = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 26,
  );
}

/// Calm animation timings. No glow, no shimmer — soft and slow by brand rule.
@immutable
class OverlayMotion {
  const OverlayMotion({
    required this.dotPulsePeriod,
    required this.dotPulseMinAlpha,
    required this.dotPulseMinScale,
  });

  /// Recording dot pulse period.
  final Duration dotPulsePeriod;

  /// Minimum alpha the recording dot dips to at the bottom of its pulse.
  final double dotPulseMinAlpha;

  /// Minimum scale the recording dot dips to at the bottom of its pulse
  /// (task #polish-cross-platform-glass). Paired with [dotPulseMinAlpha] so
  /// the pulse reads as a soft breathing motion rather than a flat opacity
  /// flicker — still calm, no size overshoot past 1.0.
  final double dotPulseMinScale;
}

/// Shared interaction constants for both overlay and button.
@immutable
class OverlayInteraction {
  const OverlayInteraction({
    required this.dragThresholdPx,
    required this.anchors,
    required this.screenEdgeMargin,
  });

  /// Pointer travel before a press becomes a drag (logical pixels). Identical
  /// for overlay and button on every platform.
  final double dragThresholdPx;

  /// Supported anchor positions.
  final List<OverlayAnchor> anchors;

  /// Margin kept from the screen edge when snapping to a fixed anchor.
  final double screenEdgeMargin;
}

/// Mic-glyph geometry for the floating button, expressed as **ratios of the
/// disc diameter** so the glyph scales identically across the settings-owned
/// button sizes (44/56/80). Every ratio is the approved spike value
/// (`spike/lib/main.dart` `_mic`, tuned at a 56 px disc) divided by 56, so a
/// 56 px disc reproduces the spike pixel-for-pixel and the painter carries no
/// magic numbers.
@immutable
class FloatingButtonMicSpec {
  const FloatingButtonMicSpec({
    required this.bodyWidthRatio,
    required this.bodyHeightRatio,
    required this.bodyRadiusRatio,
    required this.bodyCenterDyRatio,
    required this.arcRadiusRatio,
    required this.arcCenterDyRatio,
    required this.arcStartAngle,
    required this.arcSweepAngle,
    required this.strokeRatio,
    required this.stemTopDyRatio,
    required this.stemBottomDyRatio,
  });

  /// Mic-capsule body width ÷ diameter (spike `9` in a 56 disc).
  final double bodyWidthRatio;

  /// Mic-capsule body height ÷ diameter (spike `14`).
  final double bodyHeightRatio;

  /// Mic-capsule corner radius ÷ diameter (spike `4.5`).
  final double bodyRadiusRatio;

  /// Body-centre vertical offset from the disc centre ÷ diameter (spike `-4`,
  /// i.e. the capsule sits above centre).
  final double bodyCenterDyRatio;

  /// Cradle-arc radius ÷ diameter (spike `8.5`).
  final double arcRadiusRatio;

  /// Cradle-arc centre vertical offset from the disc centre ÷ diameter
  /// (spike `-1`).
  final double arcCenterDyRatio;

  /// Cradle-arc start angle in radians (spike `0.35`); scale-free.
  final double arcStartAngle;

  /// Cradle-arc sweep angle in radians (spike `π − 0.7`); scale-free.
  final double arcSweepAngle;

  /// Glyph stroke width ÷ diameter (spike `2`).
  final double strokeRatio;

  /// Stem top endpoint vertical offset ÷ diameter (spike `7.5`).
  final double stemTopDyRatio;

  /// Stem bottom endpoint vertical offset ÷ diameter (spike `11`).
  final double stemBottomDyRatio;

  /// The approved spike mic geometry (`_mic`), referenced to a 56 px disc.
  static const FloatingButtonMicSpec spike = FloatingButtonMicSpec(
    bodyWidthRatio: 9 / 56,
    bodyHeightRatio: 14 / 56,
    bodyRadiusRatio: 4.5 / 56,
    bodyCenterDyRatio: -4 / 56,
    arcRadiusRatio: 8.5 / 56,
    arcCenterDyRatio: -1 / 56,
    arcStartAngle: 0.35,
    arcSweepAngle: math.pi - 0.7,
    strokeRatio: 2 / 56,
    stemTopDyRatio: 7.5 / 56,
    stemBottomDyRatio: 11 / 56,
  );
}

/// Floating-button appearance — the V2 style (ADR 0002): a white disc with a
/// dark mic glyph and a hairline border. No accent ring, no glow.
///
/// The button diameter is fixed at [buttonDiameter] (56 dp) — the approved
/// design-token value. The former size picker (Small/Normal/Large) was removed
/// in issue 11 because the Zielgruppe does not benefit from micro-tuning the
/// button chrome. Per-state icon tinting reuses
/// [OverlayDesignSpec.stateGradients] (consumed in issue 08).
@immutable
class FloatingButtonSpec {
  /// Fixed button disc diameter in logical pixels (design-token value, ADR 0002).
  ///
  /// Formerly `FloatingButtonSize.normal.pixels` (56); the user-facing size
  /// picker was removed in issue 11. All rendering code should reference this
  /// constant instead of a hard-coded literal.
  static const double buttonDiameter = 56.0;

  const FloatingButtonSpec({
    required this.discColor,
    required this.discGradientEnd,
    required this.discFillOpacity,
    required this.iconColor,
    required this.borderColor,
    required this.borderWidth,
    required this.borderInset,
    required this.iconRatio,
    required this.hasGlow,
    required this.mic,
  });

  /// Disc fill gradient start — white (top-left), spike `Colors.white`.
  final Color discColor;

  /// Disc fill gradient end — `#EDF1F6` (bottom-right), spike value.
  final Color discGradientEnd;

  /// Base opacity of the disc fill gradient (spike `0.95`). The opacity setting
  /// scales the disc chrome (fill + shadow) by `discFillOpacity × opacity`; the
  /// mic glyph stays fully opaque (accessibility, mirrors the overlay).
  final double discFillOpacity;

  /// Idle mic glyph colour — dark `#101828`.
  final Color iconColor;

  /// Hairline border `#1A101828`.
  final Color borderColor;

  /// Border stroke width (logical pixels, pre-DPR).
  final double borderWidth;

  /// Border inset from the disc radius (spike draws the stroke at `r − 0.5`).
  final double borderInset;

  /// Glyph size as a fraction of the disc diameter (24 in a 56 disc).
  final double iconRatio;

  /// Always false — the V2 button has no glow/accent ring.
  final bool hasGlow;

  /// Mic-glyph geometry (ratios of the disc diameter).
  final FloatingButtonMicSpec mic;
}

/// The overlay/button design Single Source of Truth.
abstract final class OverlayDesignSpec {
  /// Factor by which every compact content metric is scaled down from normal.
  /// `2/3` maps the normal 24 px waveform to the compact 16 px and the normal
  /// 15 pt timer to the compact 10 pt.
  static const double compactScale = 2 / 3;

  /// Base alpha of the capsule's tint gradient fill.
  ///
  /// **Dock-glass decision (Maintainer, 2026-07-29):** lowered from `0.66` to
  /// `0.35` so the capsule reads as "im Grunde bloß ein Glaskörper drumrum" —
  /// like the macOS Dock. The researched no-blur glass recipe (Liquid-Glass /
  /// glassmorphism analyses): without a compositor blur the FILL cannot carry
  /// the glass identity — it only tints; the identity moves to the highlight
  /// layer (Fresnel rim light, inner edge band, specular top streak — see the
  /// glass constants below). Cross-platform (pure Dart in [WpOverlayPainter],
  /// identical on macOS/Windows/Linux); no OS-level blur is used.
  ///
  /// Trade-off, explicitly sanctioned: below the old text-safety product
  /// (`0.66 × opacity`), worst-case timer/status-text contrast now depends on
  /// the desktop behind the capsule. The content layer itself stays fully
  /// opaque, and the waveform/icons carry their own ≥3:1 guarantees.
  ///
  /// The opacity setting scales ONLY the translucent pill chrome (fill gradient,
  /// painted shadow, border) by `fillOpacityFactor × opacity`; the content layer
  /// (text, icons, dot, waveform, stop, timeline) always stays fully opaque
  /// (accessibility, ADR 0002).
  /// (0.35 → 0.22 → 0.14 across the Dock-glass rounds, 2026-07-29 —
  /// together with the shadow knock-out under the capsule, see
  /// [WpOverlayPainter], the pill now reads as a bare glass body. The content
  /// no longer depends on the fill at all: every dark-ink glyph became a
  /// white glyph with a dark outline — see [contentGlyphFill].)
  static const double fillOpacityFactor = 0.14;

  /// Fill gradient for [OverlayStyleVariant.solid] — reuses
  /// [WpColorsDark.frameGradient] verbatim (the same navy→violet arc the
  /// title bar/nav rail/status bar paint) so the "solid" overlay reads as cut
  /// from the same brand chrome rather than inventing a nearby blue.
  static const LinearGradient solidFillGradient = WpColorsDark.frameGradient;

  /// Alpha of the white glass sheen painted over the capsule fill (task #38):
  /// a top-down highlight that reads as light on curved glass. Lowered with
  /// the Dock-glass fill (0.40 → 0.28): over the much clearer capsule a
  /// strong white wash reads as milk, not glass.
  static const double glassSheenOpacity = 0.15;

  /// Fraction of [glassSheenOpacity] used for the faint counter-sheen rising
  /// from the capsule's bottom edge (glass polish pass, macOS-Dock mood
  /// reference): light catching the lower glass rim. Neutral white like
  /// every sheen — never state-tinted (ADR 0002).
  static const double glassBottomSheenFactor = 0.25;

  // -- Dock-glass refinement (impeccable layout pass, 2026-07-28) ------------
  //
  // The sheen now behaves like light on CURVED glass instead of a flat
  // vertical wash: the top highlight tapers away from the rounded end caps,
  // the bright rim is lit from above (fading toward the bottom), and a
  // hair-thin dark inner shade above the bottom counter-sheen gives the
  // glass physical thickness. All neutral white/black — no state colour in
  // the chrome, no OS blur, identical on every platform.

  /// Horizontal inset of the top-sheen gradient rect, as a fraction of the
  /// capsule radius — pulls the highlight off the rounded end caps so it
  /// reads as light on a curved surface, not a full-width band.
  static const double glassSheenCapInsetFactor = 0.35;

  /// Colour stops of the top-down sheen (bright → soft → clear).
  static const List<double> glassSheenStops = [0.0, 0.32, 0.55];

  /// Colour stops of the bottom counter-sheen (clear → faint white).
  static const List<double> glassBottomSheenStops = [0.78, 1.0];

  /// Alpha of the hair-thin neutral dark inner shade painted just above the
  /// bottom counter-sheen — the "mass" of the glass slab.
  static const double glassInnerShadeOpacity = 0.04;

  /// Colour stops of the inner bottom shade (clear → faint black).
  static const List<double> glassInnerShadeStops = [0.85, 1.0];

  // Fresnel edge treatment (Dock-glass research pass, 2026-07-29): glass
  // reflects most at grazing angles, so a believable no-blur glass body is
  // carried by its EDGES — a bright 1 px rim lit from above, a soft wider
  // inner band just inside it (the refracting "thickness" of the slab), and
  // one crisp specular streak along the top edge (the Dock's signature
  // reflection). All neutral white, all static — no shimmer, no state tint.

  /// Alpha of the 1 px outer rim at the TOP edge (absolute, no longer tied
  /// to the sheen — the rim now carries the glass identity).
  static const double glassRimTopOpacity = 0.55;

  /// Alpha of the 1 px outer rim at the BOTTOM edge.
  static const double glassRimBottomOpacity = 0.10;

  /// Stroke width of the soft inner Fresnel band just inside the rim.
  static const double glassInnerRimWidth = 2.5;

  /// Inset of the inner Fresnel band from the capsule edge.
  static const double glassInnerRimInset = 1.25;

  /// Peak alpha of the inner Fresnel band (fades to clear toward the bottom).
  static const double glassInnerRimOpacity = 0.10;

  // Specular streak — debugged 2026-07-30 after two invisible rounds.
  // Pixel measurement of rendered frames found TWO structural causes, not a
  // value problem: (1) over light desktops the alpha chain saturated (streak
  // row 250 vs. surroundings 250 — white on near-white, Δ0); (2) over dark
  // desktops the 1.2 px streak sat 1 px under the static bright rim and
  // perceptually fused with it (its drift read as nothing). Fixes: the
  // streak moved AWAY from the edge, got wider, and carries a soft dark
  // under-halo that guarantees local contrast on light backgrounds.

  /// Alpha of the crisp specular streak.
  static const double glassSpecularOpacity = 0.5;

  /// Stroke width of the specular streak (1.2 → 2.6: one hairline row could
  /// never read as a distinct reflection).
  static const double glassSpecularStrokeWidth = 2.6;

  /// Length of the specular streak as a fraction of the pill width.
  static const double glassSpecularWidthFactor = 0.55;

  /// Distance of the specular streak below the top edge (2.5 → 5.5: clear
  /// of the static rim, so its drift is distinguishable from the edge).
  static const double glassSpecularInsetTop = 5.5;

  /// Alpha of the soft dark under-halo beneath the streak — the local
  /// contrast floor that keeps the white streak visible over light desktops
  /// (measured: without it the streak is Δ0 on white).
  static const double glassSpecularHaloOpacity = 0.16;

  /// Blur sigma of the under-halo.
  static const double glassSpecularHaloBlurSigma = 2.0;

  /// Stroke width of the under-halo (wider than the streak).
  static const double glassSpecularHaloStrokeWidth = 5.0;

  /// Vertical offset of the under-halo below the streak.
  static const double glassSpecularHaloOffsetY = 1.5;

  // -- Liquid-glass drift (Maintainer-Wunsch 2026-07-29, research pass) ------
  //
  // The glass material itself moves — barely. Researched guidance (Liquid-
  // Glass web implementations, premium-shimmer practice): specular highlights
  // may DRIFT a few pixels, slowly ("specular highlight amplitude ≤ 6 px";
  // "a few-pixel highlight drift feels premium"), while a repeating bright
  // SWEEP reads as a loading shimmer — which ADR 0002 forbids. So: the
  // specular streak drifts sinusoidally ±[liquidSpecularDriftPx], the top
  // sheen follows at half parallax (layer-depth cue), and the rim light
  // breathes ±[liquidRimBreatheFactor]. Everything is phase-locked to one
  // slow [liquidDriftPeriod] cycle and neutral-white only. Phase 0 renders
  // EXACTLY the static frame — reduced-motion and the goldens live there.
  static const Duration liquidDriftPeriod = Duration(seconds: 8);

  /// Peak horizontal drift of the specular streak. Raised 6 → 12 px after
  /// live feedback ("überhaupt nicht sichtbar") — still an anchored
  /// highlight oscillating around its resting spot over a slow 8 s cycle,
  /// NOT a band traversing the surface (that would be the forbidden
  /// shimmer sweep; the boundary stays).
  static const double liquidSpecularDriftPx = 12.0;

  /// Fraction of the specular drift applied to the top sheen — the two
  /// light layers move at different speeds (micro-parallax = depth).
  static const double liquidSheenParallaxFactor = 0.5;

  /// Peak relative length-breathing of the specular streak (raised with the
  /// visibility pass).
  static const double liquidSpecularBreatheFactor = 0.18;

  /// Peak relative alpha-breathing of the specular streak — the drifting
  /// light also visibly brightens/dims across the cycle (0.35 base alpha
  /// swings ±25 %, still far from any flash).
  static const double liquidSpecularBrightBreatheFactor = 0.25;

  /// Peak relative alpha-breathing of the rim's top light (raised with the
  /// visibility pass).
  static const double liquidRimBreatheFactor = 0.15;

  // -- Liquid-glass silhouette wobble (Maintainer-Interview 2026-07-30) ------
  //
  // The capsule OUTLINE itself deforms — the "flüssiges Gummibärchen im
  // Windhauch": a continuous, barely-perceptible base undulation plus a
  // slightly stronger deformation on loud speech (audio level — explicitly
  // requested in the interview). Construction: the capsule perimeter is
  // sampled into [liquidWobbleSamples] equidistant points, each displaced
  // along its outward normal by two counter-travelling low-spatial-frequency
  // waves (2 and 3 periods around the perimeter; 1 and 2 time-cycles per
  // [liquidDriftPeriod] loop, so the motion is seamless at the wrap), then
  // closed with Catmull-Rom smoothing — organic bulges, never jitter.
  //
  // Calibration (round 2, "eingeschlossenes Wasser"): base ±1.2 px; the
  // audio share adds up to ±2.4 px at full level AND runs as its OWN wave
  // shape — a faster, finer ripple (5 perimeter periods, 6 time-cycles per
  // loop) so the voice reaction reads as a distinct component, not just
  // "more wind". Total ≤ 3.6 px, comfortably inside the 8 px
  // [shadowPadding] so the native window never clips. Reduced-motion and
  // the settings preview render the perfectly rigid capsule (amplitude 0).

  /// Base ("Windhauch") wobble amplitude in logical pixels.
  static const double liquidWobbleBaseAmplitudePx = 1.2;

  /// Additional ripple amplitude at full audio level (own, finer waveform —
  /// see [WpOverlayPainter]).
  static const double liquidWobbleAudioAmplitudePx = 2.4;

  /// Number of perimeter sample points (Catmull-Rom smoothed).
  static const int liquidWobbleSamples = 28;

  /// Recommended slider floor for the opacity setting (ADR 0002). Guidance
  /// for the USER opacity slider only — it scales the whole chrome by
  /// `fillOpacityFactor × opacity`. Since the Dock-glass decision
  /// (2026-07-29) the base [fillOpacityFactor] itself sits below the old
  /// text-safety product by explicit maintainer choice; this floor keeps the
  /// slider from thinning the glass body further into invisibility.
  static const double minRecommendedOpacity = 0.65;

  // -- Universal-legibility glyph scheme (final: soft shadow, 2026-07-30) ----
  //
  // The overlay floats over ARBITRARY desktop content, and the painter has
  // no backdrop sampling and no OS blur — so no single ink colour can work
  // on both light and dark desktops. All neutral glyphs (timer/status text,
  // close ✕, stop square) render WHITE over a soft blurred dark drop shadow
  // (subtitle technique; Maintainer-Entscheid nach dem Varianten-Vergleich —
  // softShadow schlug gradientScrim und hairlineOutline). The dot, waveform
  // and done/error icons keep their semantic mid-tone colours (mid-tones
  // hold ≥3:1 against both white and black extremes and need no shadow).

  /// Fill colour of all neutral content glyphs (text, close ✕, stop square).
  static const Color contentGlyphFill = Color(0xFFFFFFFF);

  /// Shadow ink beneath the white glyphs.
  static const Color glyphShadowColor = Color(0xFF14202E);

  /// Shadow alpha.
  static const double glyphShadowOpacity = 0.85;

  /// Gaussian blur sigma of the glyph shadow (soft, no hard ring).
  static const double glyphShadowBlurSigma = 1.75;

  /// Offset of the glyph shadow (slightly downward, like cast light).
  static const Offset glyphShadowOffset = Offset(0, 0.75);

  // -- Capsule chrome (painted shadow + capsule shape) -----------------------

  /// Painted soft-shadow colour (cross-platform, no OS blur). Alpha is applied
  /// at paint time as `shadowOpacity × opacity`.
  static const Color shadowColor = Color(0xFF000000);

  /// Painted-shadow opacity at full master opacity (spike `0.20`).
  static const double shadowOpacity = 0.20;

  /// Painted-shadow Gaussian blur sigma. Softened from the spike's `7.0`
  /// (cross-platform glass polish pass) so the capsule reads as hovering
  /// rather than sitting flush — mirrors the large-blur half of
  /// [WpShadows.card]'s two-layer ambient-depth language.
  static const double shadowBlur = 9.0;

  /// Painted-shadow offset (spike `(0, 3)`, i.e. cast downward).
  static const Offset shadowOffset = Offset(0, 3);

  /// Second, tight contact-shadow layer painted beneath [shadowBlur]/
  /// [shadowOpacity] (cross-platform glass polish pass) — the small-blur half
  /// of the same two-layer shadow language [WpShadows.card] already uses
  /// elsewhere in the app, so the overlay's depth matches the rest of the
  /// product instead of standing alone on a single soft shadow.
  static const double contactShadowOpacity = 0.12;

  /// Contact-shadow blur sigma — tight, grounds the capsule against the
  /// desktop directly beneath it.
  static const double contactShadowBlur = 2.0;

  /// Contact-shadow offset.
  static const Offset contactShadowOffset = Offset(0, 1);

  /// Padding reserved on every side of the pill inside the native window so the
  /// painted shadow is not clipped (spike: a 64 px pill in an 80 px window →
  /// 8 px each side). [windowSize] adds this; the native shells must match it.
  static const double shadowPadding = 8.0;

  /// Resolves the hand-tuned per-size layout (spike `_drawPill`).
  ///
  /// Legacy two-size convenience — new code paths that can carry a full
  /// [OverlaySizeVariant] use [layoutFor].
  static OverlayLayoutSpec layout({required bool compact}) => layoutFor(
    compact ? OverlaySizeVariant.compact : OverlaySizeVariant.normal,
  );

  /// Resolves the hand-tuned layout for [variant].
  static OverlayLayoutSpec layoutFor(OverlaySizeVariant variant) =>
      switch (variant) {
        OverlaySizeVariant.normal => OverlayLayoutSpec.normal,
        OverlaySizeVariant.compact => OverlayLayoutSpec.compact,
        OverlaySizeVariant.mini => OverlayLayoutSpec.mini,
      };

  /// Full native-window size for one pill = pill box + [shadowPadding] on every
  /// side. The pill itself is painted at `Offset(shadowPadding, shadowPadding)`.
  ///
  /// Legacy two-size convenience — see [windowSizeFor].
  static Size windowSize({required bool compact}) => windowSizeFor(
    compact ? OverlaySizeVariant.compact : OverlaySizeVariant.normal,
  );

  /// Full native-window size for [variant] = pill box + [shadowPadding] on
  /// every side. Normal `346 × 80`, compact `236 × 56`, mini `166 × 50` —
  /// the native shells must mirror these exactly.
  static Size windowSizeFor(OverlaySizeVariant variant) {
    final s = sizeFor(variant);
    return Size(s.width + 2 * shadowPadding, s.height + 2 * shadowPadding);
  }

  // -- Stop square (recording only) ------------------------------------------

  /// Stop-square corner radius (spike `2`).
  static const double stopSquareRadius = 2.0;

  /// Stop-square fill opacity over the content colour (spike `0.9`).
  static const double stopSquareOpacity = 0.9;

  // -- Bottom progress timeline (inset hairline) -----------------------------

  /// Timeline inset from the pill bottom edge (spike `bottom − 6`).
  static const double timelineInsetBottom = 6.0;

  /// Timeline stroke width (spike `2`).
  static const double timelineStrokeWidth = 2.0;

  /// Trailing-stop opacity of the timeline accent gradient (spike `0.25`).
  static const double timelineEndOpacity = 0.25;

  /// Radius of the small bright leading dot drawn at the current progress
  /// position on the timeline (cross-platform glass polish pass) — pinpoints
  /// "you are here" more precisely than the fading line end alone.
  static const double timelineLeadDotRadius = 2.2;

  // -- Waveform line rendering (thin accent lines) ---------------------------

  /// Number of trailing (most-recent) bars drawn in the bright active accent;
  /// the rest are drawn muted (spike `i > len − 5`).
  static const int waveformActiveCount = 5;

  // Mirrored-bar waveform (Maintainer decision, 2026-07-29): the bars are
  // FULLY OPAQUE filled capsules, mirrored around the centre axis
  // (Spotify/Voice-Memos register, in WhisPaste's own accent language) —
  // no alpha wash, no glow (explicitly rejected: "macht das nur
  // schwammiger"), hard crisp edges. Identity lives in the "energy axis":
  // every bar carries a vertical in-bar gradient that is brightest at the
  // centre line and shades toward the tips, so quiet bars still show a
  // bright core and loud bars grow dark-tipped amplitude. The recency
  // "playhead" (trailing bars) is encoded through a wider bar plus a hotter
  // core — never through washing the history out.

  /// Alpha of the recording bars — fully opaque, maximum contrast
  /// (accent `#0887A8` over worst-case white ≈ 4.2:1).
  static const double waveformActiveOpacity = 1.0;

  /// Alpha of the leading (history) bars while recording — also fully
  /// opaque; active vs. muted reads through width + core brightness.
  static const double waveformMutedLineOpacity = 1.0;

  /// Alpha of the flat waveform shown outside recording (decorative rest
  /// state, deliberately quieter than the live bars).
  static const double waveformInactiveStateOpacity = 0.5;

  /// Visual bar width as a fraction of the per-bar slot (the remainder is
  /// the gap) — chunky enough to read as a bar, open enough to stay a
  /// rhythm, never a solid block.
  static const double waveformBarFillFactor = 0.62;

  /// Slot fraction for the trailing active bars — the playhead is wider.
  static const double waveformActiveBarFillFactor = 0.74;

  /// Perceptual display gamma applied to the normalised level before it maps
  /// to bar height (`height ∝ level^gamma`). Speech spends most of its time
  /// at low normalised levels; the sub-linear curve lifts quiet syllables so
  /// the waveform dances instead of idling near the floor, while loud peaks
  /// still cap at the same maximum. Display-only — the pipeline's smoothing
  /// state stays untouched.
  static const double waveformLevelGamma = 0.65;

  /// White fraction mixed into the accent at the CENTRE of the bar gradient
  /// for the muted (history) bars — the "energy axis" core.
  static const double waveformCoreMutedLightFraction = 0.10;

  /// White fraction at the centre for the active trailing bars — the hotter
  /// playhead core.
  static const double waveformCoreActiveLightFraction = 0.35;

  /// Black fraction mixed into the accent at BOTH bar tips — mirrored
  /// shading that grounds the bars and adds contrast at the extremes.
  static const double waveformTipShadeFraction = 0.15;

  /// Fraction of the pill height the loudest bar may reach (spike `0.6`).
  static const double waveformHeightFactor = 0.60;

  /// Flat rest level used for the faint waveform outside recording (spike
  /// `0.06`).
  static const double waveformRestLevel = 0.06;

  /// Length of the waveform release-out that follows `recording →
  /// transcribing`, in milliseconds.
  ///
  /// Single source of truth for the two halves that have to agree on it:
  /// `FloatingOverlayService.releaseOutDurationMs` keeps ticking the pipeline
  /// with silence for exactly this long (so the bars decay instead of
  /// freezing), and [OverlayArcMotion.releaseOutDuration] keeps the content
  /// crossfade — the only path through which those decaying bars reach the
  /// canvas — alive for the same span. When the two drifted apart the
  /// waveform visibly snapped to the flat [waveformRestLevel] frame halfway
  /// through the decay.
  static const int waveformReleaseOutMs = 300;

  // -- Font weights (theme-wide, not scaled) ---------------------------------

  /// Recording timer weight (bold).
  static const FontWeight timerFontWeight = FontWeight.w700;

  /// Primary label/done/error weight (semibold).
  static const FontWeight primaryFontWeight = FontWeight.w600;

  /// Secondary/elapsed weight (regular).
  static const FontWeight secondaryFontWeight = FontWeight.w400;

  // -- Status-icon reveal (cross-platform glass polish pass) -----------------

  /// Initial scale of the error status icon's fade-in-and-settle entrance —
  /// the same calm, no-overshoot register as [OverlayArcMotion.appearScale],
  /// applied to a single icon instead of the whole capsule. Driven by the
  /// existing state-transition crossfade fraction; adds no new controller.
  static const double errorIconRevealScaleStart = 0.85;

  // -- Chrome neutrality (maintainer decision, 2026-07-28) -------------------
  //
  // The capsule CHROME (fill, sheen, border, shadow) is strictly state-
  // neutral: fill/sheen are the fixed tint gradient + white sheen, the border
  // is always the fixed accent hairline [OverlayThemeColors.capsuleBorder],
  // and the shadow is always neutral black. A per-state border re-hue
  // (formerly `borderColorFor`) was removed after live feedback: over a small
  // translucent capsule the red recording stroke read as a diffuse pink
  // "glow" — exactly the effect ADR 0002 forbids. State identity lives ONLY
  // in crisp content glyphs: the pulsing dot, the live waveform, the done
  // check (green) and the error icon/text (red).

  // -- Theme colours ---------------------------------------------------------

  /// The approved spike (`spike/lib/main.dart` `kFinalDesign`, mirrored by the
  /// web `web-parity-board`) defines a **single** capsule design — a light
  /// tint-gradient teal capsule — shown identically over light AND dark
  /// backgrounds. There is deliberately no separate dark capsule variant; the
  /// translucent fill carries the design over any desktop. So [light] holds the
  /// spike tokens and [dark] resolves to the exact same set (1:1 parity).
  ///
  /// Colours come verbatim from `kFinalDesign`: content `#14202E`,
  /// accent `#0887A8`, fill `#F7FAFD → #E6EEF5`, border `#330887A8`.
  static const OverlayThemeColors light = OverlayThemeColors(
    capsuleFillStart: Color(0xFFF7FAFD),
    capsuleFillEnd: Color(0xFFE6EEF5),
    capsuleBorder: Color(0x330887A8),
    text: Color(0xFF14202E),
    accent: Color(0xFF0887A8),
    success: Color(0xFF05875C),
    error: Color(0xFFCC1C1C),
    recordingDot: Color(0xFFFF5252),
  );

  /// Dark theme colour set — identical to [light]: the spike has one design.
  static const OverlayThemeColors dark = light;

  /// Resolves the colour set for [theme].
  static OverlayThemeColors colors(OverlayDesignTheme theme) =>
      theme == OverlayDesignTheme.dark ? dark : light;

  /// Convenience resolver for a boolean dark flag (matches the snapshot).
  static OverlayThemeColors colorsForDark(bool isDark) => isDark ? dark : light;

  // -- Per-state accent gradients --------------------------------------------

  /// Accent gradient per state. The done gradient's middle stop is the
  /// canonical green `#30C065`.
  static const Map<OverlayDesignState, OverlayStateGradient> stateGradients = {
    OverlayDesignState.recording: OverlayStateGradient([
      Color(0xFFEF4444),
      Color(0xFFDC2626),
    ]),
    OverlayDesignState.transcribing: OverlayStateGradient([
      Color(0xFFF59E0B),
      Color(0xFFD97706),
    ]),
    OverlayDesignState.done: OverlayStateGradient([
      Color(0xFF4ADE80),
      Color(0xFF30C065),
      Color(0xFF16A34A),
    ]),
    OverlayDesignState.error: OverlayStateGradient([
      Color(0xFFEF4444),
      Color(0xFFB91C1C),
    ]),
  };

  // -- Waveform --------------------------------------------------------------

  /// Waveform parameters. 22 bars, shared across both sizes.
  static const WaveformSpec waveform = WaveformSpec(
    barCount: 22,
    minBarHeightPx: 3.0,
    activeColorThreshold: 0.30,
    activeAccentOpacity: 0.85,
    mutedOpacity: 0.50,
    attackTimeConstantMs: 20,
    releaseTimeConstantMs: 300,
  );

  // -- Sizes -----------------------------------------------------------------

  /// Normal (full) pill spec.
  static const OverlaySizeSpec normalSize = OverlaySizeSpec.normal;

  /// Compact (small) pill spec — content derived from [normalSize].
  static final OverlaySizeSpec compactSize = OverlaySizeSpec.compact;

  /// Mini (waveform-first) pill spec — explicit anchors, minimal content.
  static const OverlaySizeSpec miniSize = OverlaySizeSpec.mini;

  /// Resolves the size spec for the compact flag.
  ///
  /// Legacy two-size convenience — see [sizeFor].
  static OverlaySizeSpec size({required bool compact}) =>
      compact ? compactSize : normalSize;

  /// Resolves the size spec for [variant].
  static OverlaySizeSpec sizeFor(OverlaySizeVariant variant) =>
      switch (variant) {
        OverlaySizeVariant.normal => normalSize,
        OverlaySizeVariant.compact => compactSize,
        OverlaySizeVariant.mini => miniSize,
      };

  // -- Motion ----------------------------------------------------------------

  /// Calm animation timings.
  static const OverlayMotion motion = OverlayMotion(
    dotPulsePeriod: Duration(milliseconds: 900),
    // Approved spike pulse range is 0.6 .. 1.0 (`0.6 + 0.4 × …`).
    dotPulseMinAlpha: 0.6,
    // Subtler than the alpha range — a soft breathing scale, not a resize.
    dotPulseMinScale: 0.88,
  );

  /// Signature recording-arc motion parameters (Phase-0, issue 09).
  ///
  /// - [OverlayArcMotion.appearDuration]: 300 ms (WpMotion.smooth soft-cap).
  /// - [OverlayArcMotion.appearCurve]: easeOutCubic (= WpMotion.spring).
  /// - [OverlayArcMotion.appearScale]: 0.88 — subtle spring-in, not dramatic.
  /// - [OverlayArcMotion.stateTransitionDuration]: 150 ms — calm crossfade.
  ///
  /// All durations are gated by `WpMotion.durationFor` in callers so that
  /// `MediaQuery.disableAnimations = true` collapses them to Duration.zero.
  static const OverlayArcMotion arc = OverlayArcMotion(
    appearDuration: Duration(milliseconds: 300),
    appearCurve: Curves.easeOutCubic, // WpMotion.spring — no overshoot
    appearScale: 0.88,
    stateTransitionDuration: Duration(milliseconds: 150),
    stateTransitionCurve: Curves.easeOut,
    releaseOutDuration: Duration(milliseconds: waveformReleaseOutMs),
  );

  // -- Vibrancy --------------------------------------------------------------

  /// Fill opacity used on platforms where no OS blur is available (flat
  /// fallback — Linux and any unsupported runtime). Higher than
  /// [fillOpacityFactor] because without a blur layer the capsule needs more
  /// opaque chrome to remain readable over any desktop background.
  static const double flatFallbackFillOpacity = 1.0;

  /// Platform-aware vibrancy material selection.
  ///
  /// macOS = `hudWindow` (Phase-0 GO, 1.0 ms avg, best optics confirmed).
  /// Windows = `acrylic` (pending Windows measurement).
  /// Linux = `flat` (no OS blur — tinted flat fill via [flatFallbackFillOpacity]).
  static const OverlayVibrancySpec vibrancy = OverlayVibrancySpec(
    macOS: OverlayVibrancyMaterial.hudWindow,
    windows: OverlayVibrancyMaterial.acrylic,
    linux: OverlayVibrancyMaterial.flat,
  );

  // -- Interaction -----------------------------------------------------------

  /// Shared drag/anchor constants.
  static const OverlayInteraction interaction = OverlayInteraction(
    dragThresholdPx: 3.0,
    anchors: [
      OverlayAnchor.topCenter,
      OverlayAnchor.bottomCenter,
      OverlayAnchor.lastPosition,
    ],
    screenEdgeMargin: 24,
  );

  // -- Dynamic pill-width (issue 10) -----------------------------------------

  /// Width ratio for the pill at each design state, relative to
  /// [OverlaySizeSpec.width].
  ///
  /// | State        | Ratio  | Normal px (≈) |
  /// |---|---|---|
  /// | recording    | 1.000  | 330           |
  /// | transcribing | 0.758  | 250           |
  /// | done         | 0.606  | 200           |
  /// | error        | 0.758  | 250           |
  ///
  /// Both normal (330) and compact (220) sizes scale automatically because the
  /// ratio is applied against [OverlaySizeSpec.width], not a literal pixel value.
  static double pillWidthRatio(OverlayDesignState state) => switch (state) {
    OverlayDesignState.recording => 1.0,
    OverlayDesignState.transcribing => 0.758,
    OverlayDesignState.done => 0.606,
    OverlayDesignState.error => 0.758,
  };

  /// Width ratio for a [OverlaySizeSpec.minimalContent] (mini) pill.
  ///
  /// While the waveform runs (recording/transcribing) mini keeps its full
  /// width. For the done/error end states the capsule shrinks around the
  /// single centred status icon (impeccable pass) — a 150 px capsule holding
  /// one 14 px glyph read as an empty shell, and the width-morph spring is
  /// the overlay's most elegant motion; mini now shares it.
  static double miniPillWidthRatio(OverlayDesignState state) => switch (state) {
    OverlayDesignState.recording => 1.0,
    OverlayDesignState.transcribing => 1.0,
    OverlayDesignState.done => 0.42,
    OverlayDesignState.error => 0.42,
  };

  /// Target pill width in logical pixels for [state] at the given [sizeSpec].
  ///
  /// Convenience wrapper: `sizeSpec.width × pillWidthRatio(state)` (mini:
  /// [miniPillWidthRatio]). Callers pass this directly as `pillWidth` to
  /// [WpOverlayPainter].
  static double pillWidthFor(
    OverlayDesignState state,
    OverlaySizeSpec sizeSpec,
  ) => sizeSpec.minimalContent
      ? sizeSpec.width * miniPillWidthRatio(state)
      : sizeSpec.width * pillWidthRatio(state);

  /// [pillWidthFor], grown just enough to fit [text] without an ellipsis —
  /// e.g. a long done/error status message that does not fit the narrow
  /// `done`/`error`/`transcribing` ratio widths (issue: overlay text
  /// truncated even though the native window has room, both on Windows and
  /// macOS). Clamped to [sizeSpec.width] (the `recording`-state/full width,
  /// which is also what [windowSize] sizes the native host window to) so the
  /// pill never exceeds the space the native shell actually reserves —
  /// pathologically long text still falls back to [WpOverlayPainter]'s
  /// ellipsis at that point.
  static double pillWidthForText(
    OverlayDesignState state,
    OverlaySizeSpec sizeSpec,
    OverlayLayoutSpec layout,
    String text,
  ) {
    final baseWidth = pillWidthFor(state, sizeSpec);
    // Mini renders no status text — nothing to grow for.
    if (sizeSpec.minimalContent) return baseWidth;
    if (text.isEmpty) return baseWidth;
    // Mirrors WpOverlayPainter._drawContent's textLeft/maxTextWidth geometry:
    // textLeft sits at padH + dotInset + timerGap from the pill's left edge,
    // and padH is reserved again on the right — solved for the pill width
    // that gives the measured text exactly enough room.
    final measuredTextWidth = _measureTextWidth(text, layout.timerFontSize);
    final requiredWidth =
        measuredTextWidth + 2 * layout.padH + layout.dotInset + layout.timerGap;
    return requiredWidth.clamp(baseWidth, sizeSpec.width);
  }

  /// Natural (untruncated) single-line width of [text] at [fontSize], using
  /// the same style [WpOverlayPainter._drawText] paints status/done/error text
  /// with (weight + tabular figures both affect layout width).
  static double _measureTextWidth(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: primaryFontWeight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  // -- Floating button -------------------------------------------------------

  /// V2 floating-button appearance.
  static const FloatingButtonSpec button = FloatingButtonSpec(
    discColor: Color(0xFFFFFFFF),
    discGradientEnd: Color(0xFFEDF1F6),
    discFillOpacity: 0.95,
    iconColor: Color(0xFF101828),
    borderColor: Color(0x1A101828),
    borderWidth: 1.0,
    borderInset: 0.5,
    iconRatio: 24 / 56,
    hasGlow: false,
    mic: FloatingButtonMicSpec.spike,
  );

  /// Full native-window size for a button disc of [diameter] = disc +
  /// [shadowPadding] on every side, so the painted soft shadow is not clipped
  /// (mirrors [windowSize] for the overlay). The disc centre is painted at
  /// `Offset(shadowPadding + diameter / 2, shadowPadding + diameter / 2)`.
  static Size buttonWindowSize(double diameter) =>
      Size(diameter + 2 * shadowPadding, diameter + 2 * shadowPadding);
}

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
/// - **Calm UI** — no glows, no harsh effects; soft/slow timings.
/// - **Accessibility:** the opacity setting affects ONLY the pill fill
///   ([OverlayDesignSpec.fillOpacityFactor] × opacity); text, icons and the
///   waveform stay fully opaque. The recommended slider floor is
///   [OverlayDesignSpec.minRecommendedOpacity].
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The four real recording states the overlay and button render.
///
/// Mirrors `OverlayVisualState` (recording/transcribing/done/error). There is
/// deliberately no `processing` state and no privacy badge.
enum OverlayDesignState { recording, transcribing, done, error }

/// Theme variants the spec provides a complete colour set for.
enum OverlayDesignTheme { dark, light }

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

  /// Primary text (timer, done/error message).
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

/// All geometry and typography for one overlay size (normal or compact).
///
/// `width`/`height`/`cornerRadius`/`padH` are deliberate per-size **anchors**.
/// All other (content) metrics of the compact variant are **derived** from the
/// normal variant by [OverlayDesignSpec.compactScale] — see
/// [OverlaySizeSpec.compact].
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
    required this.spinnerSize,
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
    required this.secondaryFontSize,
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

  /// Transcribing spinner diameter.
  final double spinnerSize;

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

  /// Secondary (elapsed during transcribing) text font size.
  final double secondaryFontSize;

  /// Capsule corner radius — the approved spike pill is a full capsule
  /// (`height / 2` → 32 normal, 20 compact), not the legacy [cornerRadius].
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
    spinnerSize: 16,
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
    secondaryFontSize: 12,
  );

  /// The compact spec: box anchors are explicit (220×40 r20, padH 16); every
  /// content metric is [OverlayDesignSpec.compactScale] × the normal value, so
  /// compact is a true scaling of normal rather than a separate hand-tuned set.
  static final OverlaySizeSpec compact = normal._scaledContent(
    OverlayDesignSpec.compactScale,
    width: 220,
    height: 40,
    cornerRadius: 20,
    padH: 16,
  );

  /// Returns a copy with all content metrics scaled by [s] and the box anchors
  /// overridden by the given values.
  OverlaySizeSpec _scaledContent(
    double s, {
    required double width,
    required double height,
    required double cornerRadius,
    required double padH,
  }) {
    return OverlaySizeSpec(
      width: width,
      height: height,
      cornerRadius: cornerRadius,
      padH: padH,
      dotSize: dotSize * s,
      closeButtonSize: closeButtonSize * s,
      stopButtonSize: stopButtonSize * s,
      spinnerSize: spinnerSize * s,
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
      secondaryFontSize: secondaryFontSize * s,
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

  /// Minimum waveform line stroke width (the line is the thicker of this and
  /// `barWidth × waveformLineStrokeFactor`).
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
  static const OverlayLayoutSpec compact = OverlayLayoutSpec(
    padH: 16,
    closeArm: 3.5,
    closeStroke: 1.4,
    closeOffset: 5,
    dotInset: 20,
    dotRadius: 3.5,
    timerGap: 12,
    timerFontSize: 12,
    waveStartGap: 12,
    waveEndGap: 10,
    stopSize: 10,
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
  });

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
}

/// Calm animation timings. No glow, no shimmer — soft and slow by brand rule.
@immutable
class OverlayMotion {
  const OverlayMotion({
    required this.dotPulsePeriod,
    required this.dotPulseMinAlpha,
  });

  /// Recording dot pulse period.
  final Duration dotPulsePeriod;

  /// Minimum alpha the recording dot dips to at the bottom of its pulse.
  final double dotPulseMinAlpha;
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

  /// Base alpha of the capsule's tint gradient fill (approved spike value
  /// `0.92`). The opacity setting scales ONLY the translucent pill chrome
  /// (fill gradient, painted shadow, border) by `fillOpacityFactor × opacity`;
  /// the content layer (text, icons, dot, waveform, stop, timeline) always
  /// stays fully opaque (accessibility, ADR 0002).
  static const double fillOpacityFactor = 0.92;

  /// Recommended slider floor for the opacity setting — below this white text
  /// over a worst-case white background drops under WCAG AA (ADR 0002).
  static const double minRecommendedOpacity = 0.65;

  // -- Capsule chrome (painted shadow + capsule shape) -----------------------

  /// Painted soft-shadow colour (cross-platform, no OS blur). Alpha is applied
  /// at paint time as `shadowOpacity × opacity`.
  static const Color shadowColor = Color(0xFF000000);

  /// Painted-shadow opacity at full master opacity (spike `0.20`).
  static const double shadowOpacity = 0.20;

  /// Painted-shadow Gaussian blur sigma (spike `MaskFilter.blur(normal, 7)`).
  static const double shadowBlur = 7.0;

  /// Painted-shadow offset (spike `(0, 3)`, i.e. cast downward).
  static const Offset shadowOffset = Offset(0, 3);

  /// Padding reserved on every side of the pill inside the native window so the
  /// painted shadow is not clipped (spike: a 64 px pill in an 80 px window →
  /// 8 px each side). [windowSize] adds this; the native shells must match it.
  static const double shadowPadding = 8.0;

  /// Resolves the hand-tuned per-size layout (spike `_drawPill`).
  static OverlayLayoutSpec layout({required bool compact}) =>
      compact ? OverlayLayoutSpec.compact : OverlayLayoutSpec.normal;

  /// Full native-window size for one pill = pill box + [shadowPadding] on every
  /// side. The pill itself is painted at `Offset(shadowPadding, shadowPadding)`.
  static Size windowSize({required bool compact}) {
    final s = size(compact: compact);
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

  // -- Waveform line rendering (thin accent lines) ---------------------------

  /// Number of trailing (most-recent) bars drawn in the bright active accent;
  /// the rest are drawn muted (spike `i > len − 5`).
  static const int waveformActiveCount = 5;

  /// Accent alpha for the active trailing bars (spike `0.95`).
  static const double waveformActiveOpacity = 0.95;

  /// Accent alpha for the muted leading bars while recording (spike `0.5`).
  static const double waveformMutedLineOpacity = 0.50;

  /// Accent alpha for the flat waveform shown outside recording (spike `0.3`).
  static const double waveformInactiveStateOpacity = 0.30;

  /// Fraction of the pill height the loudest bar may reach (spike `0.6`).
  static const double waveformHeightFactor = 0.60;

  /// Line stroke width as a fraction of the per-bar column width (spike `0.5`).
  static const double waveformLineStrokeFactor = 0.5;

  /// Flat rest level used for the faint waveform outside recording (spike
  /// `0.06`).
  static const double waveformRestLevel = 0.06;

  // -- Font weights (theme-wide, not scaled) ---------------------------------

  /// Recording timer weight (bold).
  static const FontWeight timerFontWeight = FontWeight.w700;

  /// Primary label/done/error weight (semibold).
  static const FontWeight primaryFontWeight = FontWeight.w600;

  /// Secondary/elapsed weight (regular).
  static const FontWeight secondaryFontWeight = FontWeight.w400;

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

  /// Resolves the size spec for the compact flag (matches the snapshot).
  static OverlaySizeSpec size({required bool compact}) =>
      compact ? compactSize : normalSize;

  // -- Motion ----------------------------------------------------------------

  /// Calm animation timings.
  static const OverlayMotion motion = OverlayMotion(
    dotPulsePeriod: Duration(milliseconds: 900),
    // Approved spike pulse range is 0.6 .. 1.0 (`0.6 + 0.4 × …`).
    dotPulseMinAlpha: 0.6,
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

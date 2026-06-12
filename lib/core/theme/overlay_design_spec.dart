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
    required this.surface,
    required this.text,
    required this.secondaryText,
    required this.border,
    required this.accent,
    required this.success,
    required this.error,
    required this.waveformMuted,
    required this.recordingDot,
  });

  /// Pill background fill (before the fill-opacity factor is applied).
  final Color surface;

  /// Primary text (timer, done/error message).
  final Color text;

  /// Secondary/muted text (elapsed time during transcribing).
  final Color secondaryText;

  /// Hairline pill border (already carries its low alpha).
  final Color border;

  /// Cyan accent — spinner, waveform active bars, unlimited-progress line.
  final Color accent;

  /// Success colour — done check + message.
  final Color success;

  /// Error colour — error icon + message.
  final Color error;

  /// Muted waveform bar colour (bars below the active threshold).
  final Color waveformMuted;

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

/// Calm animation timings. No glow, no shimmer — soft and slow by brand rule.
@immutable
class OverlayMotion {
  const OverlayMotion({
    required this.dotPulsePeriod,
    required this.spinnerPeriod,
    required this.stateTransition,
    required this.frameRateFps,
    required this.dotPulseMinAlpha,
  });

  /// Recording dot pulse period.
  final Duration dotPulsePeriod;

  /// Transcribing spinner rotation period.
  final Duration spinnerPeriod;

  /// State-change cross-fade duration.
  final Duration stateTransition;

  /// Redraw rate for animated elements.
  final int frameRateFps;

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

/// Floating-button appearance — the V2 style (ADR 0002): a white disc with a
/// dark mic glyph and a hairline border. No accent ring, no glow.
///
/// Button **sizes** are settings-owned (`FloatingButtonSize`: 44/56/80) and are
/// intentionally not redefined here. Per-state icon tinting reuses
/// [OverlayDesignSpec.stateGradients] (consumed in issue 08).
@immutable
class FloatingButtonSpec {
  const FloatingButtonSpec({
    required this.discColor,
    required this.iconColor,
    required this.borderColor,
    required this.borderWidth,
    required this.iconRatio,
    required this.hasGlow,
    required this.stateTransition,
  });

  /// Disc fill — white.
  final Color discColor;

  /// Idle mic glyph colour — dark `#101828`.
  final Color iconColor;

  /// Hairline border `#1A101828`.
  final Color borderColor;

  /// Border stroke width (logical pixels, pre-DPR).
  final double borderWidth;

  /// Glyph size as a fraction of the disc diameter (24 in a 56 disc).
  final double iconRatio;

  /// Always false — the V2 button has no glow/accent ring.
  final bool hasGlow;

  /// State-change cross-fade duration.
  final Duration stateTransition;
}

/// The overlay/button design Single Source of Truth.
abstract final class OverlayDesignSpec {
  /// Factor by which every compact content metric is scaled down from normal.
  /// `2/3` maps the normal 24 px waveform to the compact 16 px and the normal
  /// 15 pt timer to the compact 10 pt.
  static const double compactScale = 2 / 3;

  /// The opacity setting multiplies ONLY the pill fill by this factor. Text,
  /// icons and the waveform always stay fully opaque (accessibility, ADR 0002).
  static const double fillOpacityFactor = 0.96;

  /// Recommended slider floor for the opacity setting — below this white text
  /// over a worst-case white background drops under WCAG AA (ADR 0002).
  static const double minRecommendedOpacity = 0.65;

  // -- Font weights (theme-wide, not scaled) ---------------------------------

  /// Recording timer weight (bold).
  static const FontWeight timerFontWeight = FontWeight.w700;

  /// Primary label/done/error weight (semibold).
  static const FontWeight primaryFontWeight = FontWeight.w600;

  /// Secondary/elapsed weight (regular).
  static const FontWeight secondaryFontWeight = FontWeight.w400;

  // -- Theme colours ---------------------------------------------------------

  /// Dark theme colour set.
  static const OverlayThemeColors dark = OverlayThemeColors(
    surface: Color(0xFF141926),
    text: Color(0xFFF0F4FA),
    secondaryText: Color(0xFF8A99B2),
    border: Color(0x14FFFFFF),
    accent: Color(0xFF38D9F0),
    success: Color(0xFF36D98B),
    error: Color(0xFFFF7B7B),
    waveformMuted: Color(0xFF8A99B2),
    recordingDot: Color(0xFFFF5252),
  );

  /// Light theme colour set.
  static const OverlayThemeColors light = OverlayThemeColors(
    surface: Color(0xFFF0F3F7),
    text: Color(0xFF101828),
    secondaryText: Color(0xFF5B697E),
    border: Color(0x140F172A),
    accent: Color(0xFF0887A8),
    success: Color(0xFF05875C),
    error: Color(0xFFCC1C1C),
    waveformMuted: Color(0xFF5B697E),
    recordingDot: Color(0xFFFF5252),
  );

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
    spinnerPeriod: Duration(milliseconds: 750),
    stateTransition: Duration(milliseconds: 200),
    frameRateFps: 30,
    dotPulseMinAlpha: 0.45,
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
    iconColor: Color(0xFF101828),
    borderColor: Color(0x1A101828),
    borderWidth: 1.0,
    iconRatio: 24 / 56,
    hasGlow: false,
    stateTransition: Duration(milliseconds: 200),
  );
}

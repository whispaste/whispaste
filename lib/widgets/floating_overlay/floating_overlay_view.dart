/// The Flutter overlay content hosted by every platform's thin window shell.
///
/// In ADR 0002 (Approach 1 / Variant B) the native window shells stop drawing
/// and become lifecycle-only hosts for this widget. It takes a fully-resolved
/// [FloatingOverlaySnapshot] (localized, themed, formatted by
/// `FloatingOverlayService`) plus the live waveform levels, drives the calm
/// accent-dot pulse, and feeds the shared [OverlayPainter] that reproduces the
/// approved spike capsule design.
///
/// ## Signature recording arc (issue 09 — C1a)
///
/// The overlay animates the full recording arc:
///
/// ```
/// Standby (visible=false) → Recording (spring-in, live waveform) →
/// Transcribing → Done (paste-confirmation) → hidden by native shell
/// ```
///
/// State transitions are **calm** (instant painter redraw); the wow-moment is
/// exclusively the capsule **appear** spring (scale 0.88→1.0 + opacity 0→1,
/// easeOutCubic 300 ms). No scattered/decorative motion anywhere else.
///
/// **Reduced-motion**: all animations gate on `MediaQuery.disableAnimations`.
/// When true the appear is instant (Duration.zero), the dot pulse is skipped,
/// and `pumpAndSettle` completes without hanging.
///
/// ## Vibrancy
///
/// The native window layer (macOS `NSVisualEffectView hudWindow`, Windows
/// Acrylic, Linux flat) is configured by the platform controller. The Flutter
/// layer renders the tinted capsule on top; on Linux/flat the capsule fill uses
/// [OverlayDesignSpec.flatFallbackFillOpacity] for readability without blur.
/// The vibrancy spec ([OverlayDesignSpec.vibrancy]) is the SSOT for which
/// material each platform requests.
///
/// ## Native window sizing
///
/// The widget renders at [OverlayDesignSpec.windowSize] — the pill box **plus**
/// [OverlayDesignSpec.shadowPadding] on every side, so the painted soft shadow
/// is not clipped. The pill itself sits at
/// `Offset(shadowPadding, shadowPadding)` inside that box. The native shells
/// (phase 2, hardware-in-the-loop) must size their transparent window to this
/// same total — normal `346 × 80`, compact `236 × 56` — and not to the bare
/// pill, or the shadow is cut off.
///
/// All design values come from [OverlayDesignSpec]; this widget contributes no
/// constants of its own and renders no privacy badge.
library;

import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_design_spec.dart';
import '../../services/floating_overlay/floating_overlay_controller_interface.dart';
import 'overlay_painter.dart';

/// Hosts the shared [OverlayPainter] and drives the recording-arc animations.
class FloatingOverlayView extends StatefulWidget {
  /// Creates the overlay view for one [snapshot].
  const FloatingOverlayView({
    super.key,
    required this.snapshot,
    this.waveformBars = const [],
    this.animate = true,
  });

  /// Fully-resolved render state.
  final FloatingOverlaySnapshot snapshot;

  /// Live normalised waveform levels (length [WaveformSpec.barCount]).
  final List<double> waveformBars;

  /// Whether to run the calm accent-dot pulse. The live overlay animates; a
  /// static preview (e.g. the Settings page) passes `false` so the widget
  /// settles — a perpetual animation never lets `pumpAndSettle` complete.
  final bool animate;

  /// Maps the runtime visual state onto the design-spec state.
  static OverlayDesignState designStateFor(OverlayVisualState s) => switch (s) {
    OverlayVisualState.recording => OverlayDesignState.recording,
    OverlayVisualState.transcribing => OverlayDesignState.transcribing,
    OverlayVisualState.done => OverlayDesignState.done,
    OverlayVisualState.error => OverlayDesignState.error,
  };

  /// Maps the snapshot's dark flag onto the design-spec theme.
  static OverlayDesignTheme themeFor(bool isDark) =>
      isDark ? OverlayDesignTheme.dark : OverlayDesignTheme.light;

  /// Builds the spec-sourced [OverlayPainter] for [snapshot].
  ///
  /// The whole painter configuration is derived from [OverlayDesignSpec] here —
  /// nothing platform-local feeds the renderer (issue 05 AC1). Exposed
  /// statically so the wiring is directly unit-testable.
  static OverlayPainter painterFor({
    required FloatingOverlaySnapshot snapshot,
    List<double> waveformBars = const [],
    double dotPulse = 1.0,
  }) {
    final theme = themeFor(snapshot.isDark);
    final designState = designStateFor(snapshot.state);
    return OverlayPainter(
      state: designState,
      theme: theme,
      sizeSpec: OverlayDesignSpec.size(compact: snapshot.compact),
      layout: OverlayDesignSpec.layout(compact: snapshot.compact),
      colors: OverlayDesignSpec.colors(theme),
      waveformBars: snapshot.state == OverlayVisualState.recording
          ? waveformBars
          : const [],
      timerText: snapshot.elapsed,
      statusText:
          snapshot.doneMessage ?? snapshot.errorMessage ?? snapshot.label,
      progress: snapshot.progress,
      dotPulse: dotPulse,
    );
  }

  @override
  State<FloatingOverlayView> createState() => _FloatingOverlayViewState();
}

class _FloatingOverlayViewState extends State<FloatingOverlayView>
    with TickerProviderStateMixin {
  // -- Dot pulse (accent dot during recording / transcribing) ------------------

  late final AnimationController _dot;

  // -- Appear spring (standby → recording spring-in) ---------------------------

  /// Drives the appear animation: opacity 0→1 and scale [_appearStart]→1.0.
  ///
  /// Initialised to 1.0 when [snapshot.visible] is already true at mount
  /// time (e.g. settings preview, render-engine re-connects). Initialised
  /// to 0.0 when the snapshot is hidden so the first `visible=true` push
  /// triggers the spring from the standby state.
  late final AnimationController _appear;

  /// Whether reduced-motion is active (mirrors `MediaQuery.disableAnimations`).
  /// Updated in [didChangeDependencies].
  bool _reducedMotion = false;

  /// Set to true after the first [didChangeDependencies] call so that
  /// subsequent calls with the same [_reducedMotion] value are no-ops.
  /// Without this flag the initial call (both sides are `false`) would
  /// short-circuit and never start the dot pulse.
  bool _motionInitialized = false;

  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _dot = AnimationController(
      vsync: this,
      duration: OverlayDesignSpec.motion.dotPulsePeriod,
      value: 1.0,
    );

    _appear = AnimationController(
      vsync: this,
      duration: OverlayDesignSpec.arc.appearDuration,
      // If already visible at mount, show immediately (no spring-in needed).
      value: widget.snapshot.visible ? 1.0 : 0.0,
    );
    // Dot pulse is started in didChangeDependencies once we have a context
    // and know the reduced-motion preference.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nowDisabled = MediaQuery.of(context).disableAnimations;
    // Always apply on the very first call so the dot pulse (or its absence)
    // is established at mount time — the early return would skip that.
    if (nowDisabled == _reducedMotion && _motionInitialized) return;
    _reducedMotion = nowDisabled;
    _motionInitialized = true;
    _applyReducedMotion();
  }

  void _applyReducedMotion() {
    if (_reducedMotion) {
      // Collapse all animations to their final values immediately.
      _dot.stop();
      _dot.value = 1.0;
      _appear.stop();
      _appear.value = widget.snapshot.visible ? 1.0 : 0.0;
    } else if (widget.animate) {
      // Resume the dot pulse now that reduced-motion is off.
      _dot.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(FloatingOverlayView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Appear / dismiss when visibility changes.
    if (widget.snapshot.visible != oldWidget.snapshot.visible) {
      if (widget.snapshot.visible) {
        _triggerAppear();
      } else {
        // Native window handles the visual hide; snap the controller to 0 so
        // the next appear starts from the correct initial value.
        _appear.value = 0.0;
      }
    }

    // Handle changes to the animate flag (e.g. settings preview ↔ live overlay).
    if (widget.animate != oldWidget.animate) {
      if (widget.animate && !_reducedMotion) {
        _dot.repeat(reverse: true);
      } else {
        _dot.stop();
        _dot.value = 1.0;
      }
    }
  }

  /// Springs the capsule in: opacity 0→1, scale [appearScale]→1.0.
  ///
  /// Duration collapses to zero when reduced-motion is active, making the
  /// appear instant (no movement, just a cut).
  void _triggerAppear() {
    final duration = _reducedMotion
        ? Duration.zero
        : OverlayDesignSpec.arc.appearDuration;
    _appear.animateTo(
      1.0,
      duration: duration,
      curve: OverlayDesignSpec.arc.appearCurve,
    );
  }

  @override
  void dispose() {
    _dot.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = OverlayDesignSpec.windowSize(
      compact: widget.snapshot.compact,
    );
    final appearScale = OverlayDesignSpec.arc.appearScale;

    return RepaintBoundary(
      child: SizedBox(
        width: window.width,
        height: window.height,
        child: AnimatedBuilder(
          animation: Listenable.merge([_dot, _appear]),
          builder: (context, child) {
            final t = _appear.value;
            // Scale: appearScale → 1.0; calm, sub-1.0 start, no overshoot.
            final scale = appearScale + (1.0 - appearScale) * t;
            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: t,
                child: CustomPaint(
                  size: window,
                  painter: FloatingOverlayView.painterFor(
                    snapshot: widget.snapshot,
                    waveformBars: widget.waveformBars,
                    dotPulse: _dot.value,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

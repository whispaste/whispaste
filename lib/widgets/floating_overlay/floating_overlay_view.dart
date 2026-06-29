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

import 'package:flutter/physics.dart';
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
  ///
  /// [paintFill] and [paintContent] are forwarded to [OverlayPainter] to enable
  /// split-layer rendering during the state-transition crossfade (issue 09).
  static OverlayPainter painterFor({
    required FloatingOverlaySnapshot snapshot,
    List<double> waveformBars = const [],
    double dotPulse = 1.0,
    bool paintFill = true,
    bool paintContent = true,
    double? pillWidth,
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
      paintFill: paintFill,
      paintContent: paintContent,
      pillWidth: pillWidth,
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

  // -- Pill-width spring (dynamic pill growth — issue 10) ----------------------

  /// Drives the pill-width morph from 0 (fromWidth) → 1 (toWidth) via a
  /// [SpringSimulation] on each state transition.
  ///
  /// Actual width = `_pillFromWidth + (_pillToWidth - _pillFromWidth) × value`.
  /// Starts at 1.0 so the initial mount shows no animation.
  late final AnimationController _pillWidth;

  /// Source width (logical px) at the start of the current spring.
  double _pillFromWidth = 0.0;

  /// Target width (logical px) for the current spring.
  double _pillToWidth = 0.0;

  /// Animated pill width at the current controller value.
  double get _currentPillWidth =>
      _pillFromWidth + (_pillToWidth - _pillFromWidth) * _pillWidth.value;

  // -- State-transition crossfade (recording → transcribing → done/error) ------

  /// Drives the 150 ms content-only crossfade between recording-arc states.
  ///
  /// Advances from 0 → 1 on each visible state change. During the transition
  /// the outgoing content paints at opacity `1 − t` and the incoming content at
  /// opacity `t`; the capsule fill is drawn once (background-only painter) so
  /// the semi-transparent gradient does not double-darken.
  ///
  /// Starts at 1.0 so the initial mount shows no crossfade.
  late final AnimationController _stateTransition;

  /// The snapshot being faded out during an active state-transition crossfade.
  /// Null when no crossfade is in flight.
  FloatingOverlaySnapshot? _outgoing;

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

    _stateTransition = AnimationController(
      vsync: this,
      duration: OverlayDesignSpec.arc.stateTransitionDuration,
      // Start at 1.0: no crossfade is happening at mount.
      value: 1.0,
    );

    // Pill-width spring controller: value in [0, 1] maps fromWidth → toWidth.
    // Initialise to the target width for the current state so no animation
    // fires on mount (value=1.0 → _currentPillWidth = _pillToWidth = target).
    final initialDesignState = FloatingOverlayView.designStateFor(
      widget.snapshot.state,
    );
    final initialSizeSpec = OverlayDesignSpec.size(
      compact: widget.snapshot.compact,
    );
    final initialWidth = OverlayDesignSpec.pillWidthFor(
      initialDesignState,
      initialSizeSpec,
    );
    _pillFromWidth = initialWidth;
    _pillToWidth = initialWidth;
    _pillWidth = AnimationController(vsync: this, value: 1.0);

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
      // Snap any in-flight crossfade to its final state.
      _stateTransition.stop();
      _stateTransition.value = 1.0;
      // Clear outgoing snapshot; the AnimatedBuilder rebuilds via
      // _stateTransition notification and renders the normal single painter.
      _outgoing = null;
      // Snap pill width to the current state's target immediately.
      final sizeSpec = OverlayDesignSpec.size(compact: widget.snapshot.compact);
      final designState = FloatingOverlayView.designStateFor(
        widget.snapshot.state,
      );
      final targetWidth = OverlayDesignSpec.pillWidthFor(designState, sizeSpec);
      _pillFromWidth = targetWidth;
      _pillToWidth = targetWidth;
      _pillWidth.stop();
      _pillWidth.value = 1.0;
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
    } else if (widget.snapshot.visible &&
        _appear.status == AnimationStatus.dismissed) {
      // Re-show guard: a visible snapshot arrived but the appear controller is
      // still at rest 0 — so the capsule would paint fully transparent
      // (Opacity 0) even though the native panel is ordered front. This happens
      // on the second and later recordings: the hide snapshot snaps `_appear`
      // to 0, and the subsequent visible snapshot does not always register as a
      // `visible` transition here (the render engine coalesces the hide→show
      // pair, or re-attaches with the main engine already considering the
      // overlay visible). Without this, the overlay was invisible on every
      // recording after the first. Trigger the appear so the capsule fades in.
      _triggerAppear();
    }

    // State-transition crossfade + pill-width spring:
    // recording → transcribing → done/error.
    //
    // Only fires on an authentic visible-state change — not on appear/disappear
    // (those are handled by _appear).
    if (widget.snapshot.state != oldWidget.snapshot.state &&
        widget.snapshot.visible &&
        oldWidget.snapshot.visible) {
      // Crossfade: content-only opacity fade (skipped under reduced-motion).
      if (!_reducedMotion) {
        setState(() {
          _outgoing = oldWidget.snapshot;
        });
        _stateTransition.forward(from: 0).then((_) {
          if (mounted) {
            setState(() {
              _outgoing = null;
            });
          }
        });
      }
      // Pill-width spring: morphs width to the new state's target.
      // Reduced-motion is handled inside _startPillSpring (snap, not spring).
      _startPillSpring(
        FloatingOverlayView.designStateFor(widget.snapshot.state),
      );
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

  /// Springs the pill width to the target for [newState].
  ///
  /// Captures the current animated width and velocity so that interrupted
  /// transitions continue smoothly without a visual snap. Under reduced-motion
  /// the target width is applied instantly (no spring).
  void _startPillSpring(OverlayDesignState newState) {
    final sizeSpec = OverlayDesignSpec.size(compact: widget.snapshot.compact);
    final targetWidth = OverlayDesignSpec.pillWidthFor(newState, sizeSpec);
    final currentWidth = _currentPillWidth;

    if (_reducedMotion) {
      _pillFromWidth = targetWidth;
      _pillToWidth = targetWidth;
      _pillWidth.stop();
      _pillWidth.value = 1.0;
      return;
    }

    // Preserve pixel velocity across interruptions so the spring feels
    // continuous when a state change arrives mid-animation.
    final pixelVelocity = _pillWidth.velocity * (_pillToWidth - _pillFromWidth);

    _pillFromWidth = currentWidth;
    _pillToWidth = targetWidth;

    final span = targetWidth - currentWidth;
    // Map pixel velocity into the [0, 1] controller space.
    final initialVelocity = span.abs() > 0.01 ? pixelVelocity / span : 0.0;

    _pillWidth.animateWith(
      SpringSimulation(OverlayArcMotion.pillSpring, 0.0, 1.0, initialVelocity),
    );
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
    _stateTransition.dispose();
    _pillWidth.dispose();
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
          animation: Listenable.merge([
            _dot,
            _appear,
            _stateTransition,
            _pillWidth,
          ]),
          builder: (context, child) {
            final t = _appear.value;
            // Scale: appearScale → 1.0; calm, sub-1.0 start, no overshoot.
            final scale = appearScale + (1.0 - appearScale) * t;

            // Animated pill width — shared across all painters in this frame so
            // all crossfade layers morph in perfect sync.
            final animatedPillWidth = _currentPillWidth;

            final outgoing = _outgoing;
            Widget content;
            if (outgoing != null && _stateTransition.value < 1.0) {
              // State-transition crossfade in flight.
              //
              // The fill is drawn once (background-only painter) to avoid
              // double-compositing the semi-transparent glass gradient.
              // Only the content layers are crossfaded at opposite opacities.
              // All three layers use the same animatedPillWidth so the pill
              // border and content always match during the crossfade.
              final ct = OverlayDesignSpec.arc.stateTransitionCurve.transform(
                _stateTransition.value,
              );
              content = Stack(
                children: [
                  // Layer 1: capsule background for the incoming state (fill only).
                  CustomPaint(
                    size: window,
                    painter: FloatingOverlayView.painterFor(
                      snapshot: widget.snapshot,
                      waveformBars: widget.waveformBars,
                      dotPulse: _dot.value,
                      paintFill: true,
                      paintContent: false,
                      pillWidth: animatedPillWidth,
                    ),
                  ),
                  // Layer 2: outgoing state content fading out.
                  Opacity(
                    opacity: 1.0 - ct,
                    child: CustomPaint(
                      size: window,
                      painter: FloatingOverlayView.painterFor(
                        snapshot: outgoing,
                        waveformBars: widget.waveformBars,
                        dotPulse: _dot.value,
                        paintFill: false,
                        paintContent: true,
                        pillWidth: animatedPillWidth,
                      ),
                    ),
                  ),
                  // Layer 3: incoming state content fading in.
                  Opacity(
                    opacity: ct,
                    child: CustomPaint(
                      size: window,
                      painter: FloatingOverlayView.painterFor(
                        snapshot: widget.snapshot,
                        waveformBars: widget.waveformBars,
                        dotPulse: _dot.value,
                        paintFill: false,
                        paintContent: true,
                        pillWidth: animatedPillWidth,
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // Steady state: single painter, full fill + content.
              content = CustomPaint(
                size: window,
                painter: FloatingOverlayView.painterFor(
                  snapshot: widget.snapshot,
                  waveformBars: widget.waveformBars,
                  dotPulse: _dot.value,
                  pillWidth: animatedPillWidth,
                ),
              );
            }

            return Transform.scale(
              scale: scale,
              child: Opacity(opacity: t, child: content),
            );
          },
        ),
      ),
    );
  }
}

/// The Flutter overlay content hosted by every platform's thin window shell.
///
/// In ADR 0002 (Approach 1 / Variant B) the native window shells stop drawing
/// and become lifecycle-only hosts for this widget. It takes a fully-resolved
/// [FloatingOverlaySnapshot] (localized, themed, formatted by
/// `FloatingOverlayService`) plus the live waveform levels, drives the calm
/// accent-dot pulse, and feeds the shared [OverlayPainter] that reproduces the
/// approved spike capsule design.
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

/// Hosts the shared [OverlayPainter] and runs its animation.
class FloatingOverlayView extends StatefulWidget {
  /// Creates the overlay view for one [snapshot].
  const FloatingOverlayView({
    super.key,
    required this.snapshot,
    this.waveformBars = const [],
    this.opacity = 1.0,
  });

  /// Fully-resolved render state.
  final FloatingOverlaySnapshot snapshot;

  /// Live normalised waveform levels (length [WaveformSpec.barCount]).
  final List<double> waveformBars;

  /// Master opacity (0–1). Only the pill chrome is dimmed; see [OverlayPainter].
  final double opacity;

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
    double opacity = 1.0,
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
      masterOpacity: opacity,
      dotPulse: dotPulse,
    );
  }

  @override
  State<FloatingOverlayView> createState() => _FloatingOverlayViewState();
}

class _FloatingOverlayViewState extends State<FloatingOverlayView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dot;

  @override
  void initState() {
    super.initState();
    _dot = AnimationController(
      vsync: this,
      duration: OverlayDesignSpec.motion.dotPulsePeriod,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = OverlayDesignSpec.windowSize(
      compact: widget.snapshot.compact,
    );
    return RepaintBoundary(
      child: SizedBox(
        width: window.width,
        height: window.height,
        child: AnimatedBuilder(
          animation: _dot,
          builder: (context, child) {
            return CustomPaint(
              size: window,
              painter: FloatingOverlayView.painterFor(
                snapshot: widget.snapshot,
                waveformBars: widget.waveformBars,
                opacity: widget.opacity,
                dotPulse: _dot.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

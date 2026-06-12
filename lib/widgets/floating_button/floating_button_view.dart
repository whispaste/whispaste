/// The Flutter floating-button content hosted by every platform's thin window
/// shell.
///
/// In ADR 0002 the native button window shells stop drawing and become
/// lifecycle-only hosts for this widget (the native conversion is issue 08b,
/// hardware-in-the-loop). It takes the button's [FloatingButtonVisualState],
/// the resolved dark flag, the settings-owned disc diameter and the master
/// opacity, then feeds the shared [FloatingButtonPainter] that reproduces the
/// approved spike V2 button (white disc, dark mic, hairline border — no glow).
///
/// ## Native window sizing
///
/// The widget renders at [OverlayDesignSpec.buttonWindowSize] — the disc plus
/// [OverlayDesignSpec.shadowPadding] on every side, so the painted soft shadow
/// is not clipped. The native shell must size its transparent window to this
/// same total, not to the bare disc.
///
/// All design values come from [OverlayDesignSpec]; this widget contributes no
/// constants of its own and renders no glow/accent ring.
library;

import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_design_spec.dart';
import '../../services/floating_button/floating_button_controller_interface.dart';
import 'floating_button_painter.dart';

/// Hosts the shared [FloatingButtonPainter].
class FloatingButtonView extends StatelessWidget {
  /// Creates the button view.
  ///
  /// There is deliberately no `isDark` parameter: the V2 disc (white disc, dark
  /// mic) is theme-independent by design, so it renders identically in dark and
  /// light. The dark-mode sync the issue asks for lives one layer up — the
  /// service resolves `isDark` via the shared `resolveFloatingSurfaceIsDark`
  /// (same path as the overlay) and forwards it to the native shell.
  const FloatingButtonView({
    super.key,
    required this.state,
    this.diameter = 56,
  });

  /// Current button visual state (idle / recording / … / disabled).
  final FloatingButtonVisualState state;

  /// Disc diameter in logical pixels (settings-owned: 44 / 56 / 80).
  final double diameter;

  /// Maps a button visual state onto the design-spec state that owns its mic
  /// tint gradient, or null for states with no gradient (idle/disabled).
  static OverlayDesignState? designStateFor(FloatingButtonVisualState s) =>
      switch (s) {
        FloatingButtonVisualState.recording => OverlayDesignState.recording,
        FloatingButtonVisualState.transcribing =>
          OverlayDesignState.transcribing,
        FloatingButtonVisualState.done => OverlayDesignState.done,
        FloatingButtonVisualState.error => OverlayDesignState.error,
        FloatingButtonVisualState.idle => null,
        FloatingButtonVisualState.disabled => null,
      };

  /// Per-state mic-tint gradient stops from the SSOT, or null for idle/disabled.
  static List<Color>? iconGradientFor(FloatingButtonVisualState s) {
    final design = designStateFor(s);
    if (design == null) return null;
    return OverlayDesignSpec.stateGradients[design]?.stops;
  }

  /// Builds the spec-sourced [FloatingButtonPainter] for the given inputs.
  ///
  /// The whole painter configuration is derived from [OverlayDesignSpec] here —
  /// nothing platform-local feeds the renderer. Exposed statically so the
  /// wiring is directly unit-testable (mirrors `FloatingOverlayView.painterFor`).
  static FloatingButtonPainter painterFor({
    required FloatingButtonVisualState state,
    double diameter = 56,
  }) {
    return FloatingButtonPainter(
      spec: OverlayDesignSpec.button,
      diameter: diameter,
      iconColor: OverlayDesignSpec.button.iconColor,
      iconGradient: iconGradientFor(state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final window = OverlayDesignSpec.buttonWindowSize(diameter);
    return RepaintBoundary(
      child: SizedBox(
        width: window.width,
        height: window.height,
        child: CustomPaint(
          size: window,
          painter: painterFor(state: state, diameter: diameter),
        ),
      ),
    );
  }
}

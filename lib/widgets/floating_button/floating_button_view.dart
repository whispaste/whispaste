/// The Flutter floating-button content hosted by every platform's thin window
/// shell.
///
/// In ADR 0002 the native button window shells stop drawing and become
/// lifecycle-only hosts for this widget (the native conversion is issue 08b,
/// hardware-in-the-loop). It takes the button's [FloatingButtonVisualState],
/// the resolved dark flag, the settings-owned disc diameter and the master
/// opacity, then feeds the shared [WpFloatingButtonPainter] that reproduces the
/// approved spike V2 button (white disc, dark mic, hairline border — no light effect).
///
/// ## Native window sizing
///
/// The widget renders at [OverlayDesignSpec.buttonWindowSize] — the disc plus
/// [OverlayDesignSpec.shadowPadding] on every side, so the painted soft shadow
/// is not clipped. The native shell must size its transparent window to this
/// same total, not to the bare disc.
///
/// All design values come from [OverlayDesignSpec]; this widget contributes no
/// constants of its own and renders no light effect. While recording, the mic
/// becomes a stop square and the wave-coloured ring sits outside the disc
/// (BTN-REC), without changing the footprint.
/// ## Idle capsule
///
/// With `overlay_button_idle_capsule` on, the idle button is a slim capsule
/// ([IdleCapsule]) that opens to the pill on hover. The render engine asks the
/// shell for the content size of the current form ([contentSizeFor]); the
/// shell adds the shadow padding and resizes its window from the origin, so
/// the capsule keeps its on-screen corner. [capsuleAlignment] pins the
/// capsule to that corner while the window and the pill animate.
library;

import 'package:flutter/widgets.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/overlay_customization.dart';
import '../../core/theme/overlay_design_spec.dart';
import '../../services/floating_button/floating_button_controller_interface.dart';
import '../../services/floating_button/idle_capsule.dart';
import 'floating_button_painter.dart';

/// Hosts the shared [WpFloatingButtonPainter].
///
/// The disc, the mic ink and the recording ring follow the same
/// [OverlayBackground] and [OverlayWave] presets as the recording pill
/// (ticket, ADR 0024).
class WpFloatingButtonView extends StatelessWidget {
  /// Creates the button view.
  const WpFloatingButtonView({
    super.key,
    required this.state,
    this.diameter = 56,
    this.background = OverlayBackground.marine,
    this.wave = OverlayWave.cyan,
    this.look = FloatingButtonLook.defaults,
    this.capsuleExpanded = false,
    this.capsuleAlignment = Alignment.topLeft,
    this.animate = true,
  });

  /// Whether the idle capsule shows its pill (hover) form. Only read while the
  /// capsule applies, see [isCapsule].
  final bool capsuleExpanded;

  /// The corner the capsule stays pinned to while the window grows. The shell
  /// grows the window away from its origin corner, so this is that corner.
  final AlignmentGeometry capsuleAlignment;

  /// False switches the capsule size change to an instant jump ("reduce
  /// motion"); the disc never animates.
  final bool animate;

  /// Current button visual state (idle / recording / … / disabled).
  final FloatingButtonVisualState state;

  /// Disc diameter in logical pixels (settings-owned: 44 / 56 / 80).
  final double diameter;

  /// Background preset of the disc (ticket).
  final OverlayBackground background;

  /// Wave colour preset: the ring while recording (ticket).
  final OverlayWave wave;

  /// Shape, recording ring and resting opacity (ticket). The size is
  /// [diameter].
  final FloatingButtonLook look;

  /// Whether the idle capsule applies: the setting is on and the button is
  /// idle. Recording, transcribing, done and error keep the full disc, so the
  /// stop control and the result are never hidden in the capsule.
  static bool isCapsule({
    required FloatingButtonVisualState state,
    required FloatingButtonLook look,
  }) => look.idleCapsule && state == FloatingButtonVisualState.idle;

  /// Logical content size of the native window for the current form: the disc
  /// diameter, or the capsule / pill size. The shell adds the shadow padding.
  static Size contentSizeFor({
    required FloatingButtonVisualState state,
    required double diameter,
    required FloatingButtonLook look,
    required bool expanded,
  }) {
    if (!isCapsule(state: state, look: look)) {
      return Size(diameter, diameter);
    }
    return expanded
        ? const Size(IdleCapsule.hoverWidth, IdleCapsule.hoverHeight)
        : const Size(IdleCapsule.idleWidth, IdleCapsule.idleHeight);
  }

  /// Maps a button visual state onto the design-spec state that owns its mic
  /// tint, or null for states with no tint (idle/disabled).
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

  /// Per-state mic colour stops for the resolved [colors] of a background, or
  /// null for idle/disabled (which paint the ink colour instead).
  static List<Color>? iconGradientFor(
    FloatingButtonVisualState s,
    OverlayThemeColors colors,
  ) {
    final design = designStateFor(s);
    if (design == null) return null;
    return OverlayDesignSpec.glyphStopsFor(design, colors);
  }

  /// Builds the spec-sourced [WpFloatingButtonPainter] for the given inputs.
  ///
  /// Nothing platform-local feeds the renderer: the colours come from the
  /// presets through [OverlayDesignSpec]. Exposed statically so the wiring is
  /// directly unit-testable (mirrors `WpFloatingOverlayView.painterFor`).
  static WpFloatingButtonPainter painterFor({
    required FloatingButtonVisualState state,
    double diameter = 56,
    OverlayBackground background = OverlayBackground.marine,
    OverlayWave wave = OverlayWave.cyan,
    FloatingButtonLook look = FloatingButtonLook.defaults,
    double? capsuleWidth,
    bool showGlyph = true,
  }) {
    final colors = OverlayDesignSpec.colorsFor(
      background: background,
      wave: wave,
    );
    return WpFloatingButtonPainter(
      spec: OverlayDesignSpec.buttonSpecFor(
        colors,
        ringed: look.ring && state == FloatingButtonVisualState.recording,
      ),
      diameter: diameter,
      iconColor: colors.ink,
      iconGradient: iconGradientFor(state, colors),
      square: look.square,
      stopSquare: state == FloatingButtonVisualState.recording,
      capsuleWidth: capsuleWidth,
      showGlyph: showGlyph,
    );
  }

  @override
  Widget build(BuildContext context) {
    final idle = state == FloatingButtonVisualState.idle;
    Widget button;
    if (isCapsule(state: state, look: look)) {
      button = _capsule(context, idle: idle);
    } else {
      final window = OverlayDesignSpec.buttonWindowSize(diameter);
      button = Opacity(
        // Resting opacity applies only while idle; a recording or a result is
        // always shown at full strength.
        opacity: idle ? look.idleAlpha : 1.0,
        child: RepaintBoundary(
          child: SizedBox(
            width: window.width,
            height: window.height,
            child: CustomPaint(
              size: window,
              painter: painterFor(
                state: state,
                diameter: diameter,
                background: background,
                wave: wave,
                look: look,
              ),
            ),
          ),
        ),
      );
    }
    // While recording the button is a stop control (BTN-REC). The label comes
    // from the ARB; the bare widget (tests without localizations) stays silent.
    final stopLabel = state == FloatingButtonVisualState.recording
        ? Localizations.of<L10n>(context, L10n)?.dockStopDictation
        : null;
    if (stopLabel != null) {
      button = Semantics(button: true, label: stopLabel, child: button);
    }
    return button;
  }

  /// The idle capsule: rest and pill share one widget; the size eases between
  /// them (instant under reduce motion) and the mic shows once the pill is
  /// open far enough to hold it.
  Widget _capsule(BuildContext context, {required bool idle}) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animated = animate && !reduceMotion;
    return Opacity(
      opacity: idle ? look.idleAlpha : 1.0,
      child: RepaintBoundary(
        child: Align(
          alignment: capsuleAlignment,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: capsuleExpanded ? 1.0 : 0.0),
            duration: animated
                ? const Duration(milliseconds: 180)
                : Duration.zero,
            curve: Curves.easeOut,
            builder: (context, t, _) {
              const pad = OverlayDesignSpec.shadowPadding;
              final w =
                  IdleCapsule.idleWidth +
                  (IdleCapsule.hoverWidth - IdleCapsule.idleWidth) * t;
              final h =
                  IdleCapsule.idleHeight +
                  (IdleCapsule.hoverHeight - IdleCapsule.idleHeight) * t;
              return SizedBox(
                width: w + 2 * pad,
                height: h + 2 * pad,
                child: CustomPaint(
                  size: Size(w + 2 * pad, h + 2 * pad),
                  painter: painterFor(
                    state: state,
                    diameter: h,
                    background: background,
                    wave: wave,
                    look: look,
                    capsuleWidth: w,
                    showGlyph: t > 0.5,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

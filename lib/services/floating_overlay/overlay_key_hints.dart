import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;

import '../../core/theme/overlay_design_spec.dart'
    show OverlaySizeVariant, contrastRatio;

/// The small key hints inside the normal recording pill: the stop hotkey
/// next to the stop square and the cancel key next to the close glyph.
///
/// The hints name the keys, the glyphs name the actions. They are drawn only
/// in the normal size while the microphone is live, and the painter drops them
/// when the waveform would be squeezed below [minWaveWidth]. Colour is the
/// preset ink, dimmed only as far as the 3:1 floor allows (see [inkFor]).
@immutable
class OverlayKeyHints {
  const OverlayKeyHints({required this.stop, this.cancel});

  /// Restores the hints from their snapshot strings; null when no stop hint
  /// was sent, which is how the snapshot says "no hints".
  static OverlayKeyHints? fromStrings({String? stop, String? cancel}) {
    if (stop == null || stop.isEmpty) return null;
    return OverlayKeyHints(
      stop: stop,
      cancel: (cancel == null || cancel.isEmpty) ? null : cancel,
    );
  }

  /// The active dictation hotkey as shown to the user, e.g. `⌥ Space`.
  final String stop;

  /// The cancel key label, e.g. `Esc`. Null hides the cancel hint, for
  /// example when the cancel glyph itself is switched off.
  final String? cancel;

  /// Font size of both hints, in logical pixels.
  static const double fontSize = 10;

  /// Gap between a hint and the glyph or the waveform it sits next to.
  static const double gap = 5;

  /// Narrowest waveform that still reads as live. Below it the hints go away
  /// so the level meter keeps its room.
  static const double minWaveWidth = 40;

  /// Dimming steps tried from the lightest to full ink. The first step whose
  /// result keeps 3:1 against the fill wins.
  static const List<double> _alphaSteps = [0.6, 0.7, 0.8, 0.9, 1.0];

  /// Whether the hints show for this [size] and live recording state. Only
  /// the normal size carries them; compact and mini have no room.
  static bool showsFor({
    required OverlaySizeVariant size,
    required bool live,
  }) => size == OverlaySizeVariant.normal && live;

  /// Builds the hints for a live recording, or null when they do not show.
  /// [cancelLabel] is passed only when the cancel glyph is shown.
  static OverlayKeyHints? forRecording({
    required OverlaySizeVariant size,
    required bool live,
    required String stopLabel,
    String? cancelLabel,
  }) {
    if (!showsFor(size: size, live: live)) return null;
    return fromStrings(stop: stopLabel, cancel: cancelLabel);
  }

  /// The ink for the hints on [fill]: the lightest dimming step of [ink]
  /// whose blend keeps 3:1, else full ink.
  static Color inkFor({required Color ink, required Color fill}) {
    for (final alpha in _alphaSteps) {
      final blended = Color.alphaBlend(ink.withValues(alpha: alpha), fill);
      if (contrastRatio(blended, fill) >= 3.0) {
        return ink.withValues(alpha: alpha);
      }
    }
    return ink;
  }

  /// Whether a waveform of [width] keeps enough room for the hints to show.
  static bool fitsWave(double width) => width >= minWaveWidth;

  @override
  bool operator ==(Object other) =>
      other is OverlayKeyHints && other.stop == stop && other.cancel == cancel;

  @override
  int get hashCode => Object.hash(stop, cancel);
}

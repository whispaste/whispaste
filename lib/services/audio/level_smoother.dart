/// Attack/release smoothing of a live level, shared by every waveform.
///
/// A rising level follows quickly ([WaveformSpec.attackTimeConstantMs]) so
/// peaks stay visible; a falling level decays over
/// [WaveformSpec.releaseTimeConstantMs] so a pause fades instead of snapping.
/// The floating overlay ([WaveformPipeline]) and the onboarding microphone
/// test ([MicProbe]) both smooth through this class, so the same speech moves
/// both waveforms the same way.
///
/// Deterministic: time comes in as a delta, never from a clock.
library;

import 'dart:math' as math;

import '../../core/theme/overlay_design_spec.dart';

class LevelSmoother {
  LevelSmoother({WaveformSpec? spec})
    : _spec = spec ?? OverlayDesignSpec.waveform;

  final WaveformSpec _spec;

  double _value = 0.0;

  /// The current smoothed level.
  double get value => _value;

  /// Moves the smoothed level toward [target] for an elapsed [deltaMs] and
  /// returns it. A non-positive delta leaves the level unchanged.
  double step(double target, double deltaMs) {
    if (deltaMs <= 0) return _value;
    final tau = target > _value
        ? _spec.attackTimeConstantMs
        : _spec.releaseTimeConstantMs;
    if (tau <= 0) {
      _value = target;
    } else {
      _value += (target - _value) * (1.0 - math.exp(-deltaMs / tau));
    }
    return _value;
  }

  /// Back to rest.
  void reset() => _value = 0.0;
}

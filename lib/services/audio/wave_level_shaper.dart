/// Display shaping of the live level: spreads normal speech over the whole
/// height of a waveform, whatever the microphone's gain.
///
/// The shared curve ([SpeechLevelMapper]) is fixed and also drives the silence
/// guards, so it must not change. Seen as a picture it has a flaw: speech from
/// a typical microphone sits between 0.6 and 0.9, a narrow strip near the top,
/// and a quiet microphone sits in a strip near the bottom. The shaper reads
/// the mapped level and re-scales it against two slow references of the
/// current recording:
///
/// - the **speech reference**: the level of the active frames, followed by a
///   slow average (1 s up, 2.5 s down). A typical syllable lands at about 0.6,
///   a stressed one reaches the top.
/// - the **floor**: the quietest recent level (room tone). It maps to nothing
///   and rises only slowly, so a pause stays at rest instead of drifting up.
///
/// The result is relative to the speaker and the microphone, not to the fixed
/// scale: quiet and loud syllables differ visibly, the top is reached by the
/// loudest syllables only, and a steady tone does not stick to it.
///
/// Deterministic: time comes in as a delta, never from a clock. The scale is
/// worked in the dB-linear domain (the mapper's curve undone), so the same
/// number of decibels is the same distance at every level.
library;

import 'dart:math' as math;

import 'speech_level_mapper.dart';

class WaveLevelShaper {
  WaveLevelShaper();

  /// Speech reference of a fresh recording (dB-linear, ≈ −22 dBFS peak): a
  /// plausible first guess until the first words adapt it.
  static const double initialReference = 0.7;

  /// Bounds of the speech reference. The lower bound limits how far a very
  /// quiet microphone is raised; the upper one is full scale.
  static const double minReference = 0.45;
  static const double maxReference = 1.0;

  /// Frames this far above the floor count as speech and move the reference.
  static const double speechGate = 0.12;

  /// Reference follow times in seconds: up to louder, down to quieter speech.
  static const double referenceRiseSeconds = 1.0;
  static const double referenceFallSeconds = 2.5;

  /// How fast the floor rises per second, and its ceiling. A level below the
  /// floor lowers it at once.
  static const double floorRisePerSecond = 0.01;
  static const double maxFloor = 0.3;

  /// Smallest distance between floor and reference, so a microphone with
  /// almost no dynamics is not stretched into noise.
  static const double minSpan = 0.25;

  /// Level relative to the reference at which the wave is full. Above 1 keeps
  /// the top for syllables clearly louder than the average one.
  static const double fullAt = 1.25;

  /// Expansion of the relative level; spreads quiet against loud syllables.
  static const double expansion = 1.7;

  double _reference = initialReference;
  double _floor = 0.0;

  /// Current speech reference (dB-linear), for tests.
  double get reference => _reference;

  /// Shapes [level] (0–1, from [SpeechLevelMapper]) after [deltaSeconds] since
  /// the previous call and returns the display level in `[0, 1]`.
  double shape(double level, double deltaSeconds) {
    final dt = deltaSeconds.isNaN ? 0.0 : deltaSeconds.clamp(0.0, 0.5);
    final x = level.isNaN ? 0.0 : level.clamp(0.0, 1.0);
    // Undo the mapper's x^1.5, which leaves a scale linear in dB.
    final y = math.pow(x, 1 / speechLevelExponent).toDouble();

    _floor = math.min(_floor + floorRisePerSecond * dt, maxFloor);
    if (y < _floor) _floor = y;

    if (y > _floor + speechGate && dt > 0) {
      final tau = y > _reference ? referenceRiseSeconds : referenceFallSeconds;
      _reference += (y - _reference) * (1 - math.exp(-dt / tau));
      _reference = _reference.clamp(minReference, maxReference);
    }

    final span = math.max(_reference - _floor, minSpan);
    final relative = math.max(0.0, (y - _floor) / span);
    return math.pow((relative / fullAt).clamp(0.0, 1.0), expansion).toDouble();
  }

  /// Back to the first guess, for a new recording.
  void reset() {
    _reference = initialReference;
    _floor = 0.0;
  }
}

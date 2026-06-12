/// Pure-Dart scrolling-history pipeline for the floating-overlay waveform.
///
/// This is the **logic/data** layer of the waveform — no painter, no widget,
/// no native code. The renderer (issue 05) consumes the snapshot it produces.
///
/// Canonical model (PRD §D4, ADR 0002):
/// - **Scrolling history**: every bar is one time-moment. New samples enter at
///   the right edge and the whole row scrolls right→left, one bar per [tick].
/// - **Volume-faithful amplitude**: a louder sample drives a taller bar via a
///   short attack time constant.
/// - **Silence → nearly flat**: with no input the level decays to the min-height
///   floor through a longer release time constant; there is no synthetic
///   modulation, so a held pause settles flat instead of jittering.
/// - **Compact = scaled, not reduced**: the bar COUNT is identical for both
///   sizes; only the per-bar pixel height scales by the size's max height
///   ([barHeights]). No 8-vs-30 split.
///
/// All parameters come from the single source of truth
/// ([OverlayDesignSpec.waveform] / [OverlayDesignSpec.normalSize]); the pipeline
/// defines no waveform constants of its own.
///
/// Deterministic by design:
/// - No `DateTime.now()`; time is supplied via [tick].
/// - No `Random`; identical inputs produce identical snapshots.
library;

import 'dart:math' as math;

import '../../core/theme/overlay_design_spec.dart';

/// Scrolling bar-history pipeline. Reads its shape (bar count, min height,
/// attack/release smoothing) entirely from [OverlayDesignSpec].
class WaveformPipeline {
  /// Creates a pipeline.
  ///
  /// [spec] defaults to the canonical [OverlayDesignSpec.waveform]; it is only
  /// overridable to keep the type testable. The normalised min-height floor is
  /// derived from the SSOT pair `minBarHeightPx / normalSize.waveformMaxHeight`.
  WaveformPipeline({WaveformSpec? spec})
    : _spec = spec ?? OverlayDesignSpec.waveform {
    _minBarLevel =
        _spec.minBarHeightPx / OverlayDesignSpec.normalSize.waveformMaxHeight;
    _history = List<double>.filled(_spec.barCount, 0.0);
  }

  final WaveformSpec _spec;

  /// Normalised floor every bar clamps up to. Derived from the SSOT.
  late final double _minBarLevel;

  /// Scrolling history: index 0 is the oldest retained moment (left edge),
  /// the last index is the newest moment (right edge). Holds raw (un-clamped)
  /// smoothed levels so the floor is applied only at [snapshot] time.
  late final List<double> _history;

  double _targetLevel = 0.0;
  double _displayLevel = 0.0;
  DateTime? _lastTickTime;

  /// Number of bars in every snapshot — taken from the spec, shared across
  /// both overlay sizes.
  int get barCount => _spec.barCount;

  /// Normalised hard floor for every bar (`minBarHeightPx / max`).
  double get minBarLevel => _minBarLevel;

  /// Records a new normalised input level (volume). The next [tick] smooths the
  /// display level toward it and scrolls it into the history.
  void pushSample(double level, DateTime now) {
    _targetLevel = level;
  }

  /// Advances one time-moment: smooths the display level toward the last pushed
  /// sample using asymmetric attack/release time constants, then scrolls the
  /// history left and writes the new level into the right edge.
  ///
  /// The first call after construction or [reset] only establishes the time
  /// baseline for the smoother, but it still scrolls a (rest-level) moment in
  /// so the history advances at a steady one-bar-per-tick cadence.
  void tick(DateTime now) {
    final last = _lastTickTime;
    _lastTickTime = now;
    if (last != null) {
      final deltaMs = now.difference(last).inMicroseconds / 1000.0;
      if (deltaMs > 0) {
        final rising = _targetLevel > _displayLevel;
        final tau = rising
            ? _spec.attackTimeConstantMs
            : _spec.releaseTimeConstantMs;
        if (tau <= 0) {
          _displayLevel = _targetLevel;
        } else {
          final alpha = 1.0 - math.exp(-deltaMs / tau);
          _displayLevel += (_targetLevel - _displayLevel) * alpha;
        }
      }
    }
    // Scroll right→left: drop the oldest moment, append the newest at the edge.
    for (var i = 0; i < _spec.barCount - 1; i++) {
      _history[i] = _history[i + 1];
    }
    _history[_spec.barCount - 1] = _displayLevel;
  }

  /// Returns the rendered bar levels, oldest→newest (left→right). Length is
  /// always [barCount]; every value lies in `[minBarLevel, 1.0]`.
  List<double> snapshot() {
    return List<double>.generate(
      _spec.barCount,
      (i) => _clamp(_history[i]),
      growable: false,
    );
  }

  /// Returns the same [snapshot] data scaled to pixel heights for the given
  /// size. The bar COUNT is identical for both sizes — compact is a true
  /// scaling (`level × maxHeight`), never a reduced second bar set.
  List<double> barHeights({required bool compact}) {
    final maxHeight = OverlayDesignSpec.size(
      compact: compact,
    ).waveformMaxHeight;
    final levels = snapshot();
    return List<double>.generate(
      levels.length,
      (i) => levels[i] * maxHeight,
      growable: false,
    );
  }

  /// Clears the history, the smoothing state, and the tick baseline.
  void reset() {
    for (var i = 0; i < _spec.barCount; i++) {
      _history[i] = 0.0;
    }
    _targetLevel = 0.0;
    _displayLevel = 0.0;
    _lastTickTime = null;
  }

  double _clamp(double value) {
    if (value < _minBarLevel) return _minBarLevel;
    if (value > 1.0) return 1.0;
    return value;
  }
}

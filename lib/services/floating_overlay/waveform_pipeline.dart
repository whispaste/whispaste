/// Pure-Dart smoothing + history pipeline for the floating-overlay waveform.
///
/// Single source of truth for:
/// - Asymmetric attack/release smoothing of the live speech level.
/// - Ring-buffer history of past samples.
/// - Composition of the final bar-snapshot (central live zone + symmetric
///   scrolling history flanks).
///
/// Deterministic by design:
/// - No `DateTime.now()`; time is supplied via [pushSample] and [tick].
/// - Micromodulation uses a fixed sine pattern per bar index, no `Random`.
library;

import 'dart:math' as math;

/// Bar-snapshot pipeline. Configured entirely via the constructor — there are
/// no module-level defaults.
class WaveformPipeline {
  /// Creates a pipeline.
  ///
  /// - [barCount]: number of bars in the rendered snapshot.
  /// - [liveZoneRatio]: fraction of bars that form the central live zone.
  /// - [attackTimeConstantMs]: time constant for rising display level.
  /// - [releaseTimeConstantMs]: time constant for falling display level.
  /// - [tickHz]: nominal tick rate; controls ring-buffer length.
  /// - [historyDurationMs]: nominal history window; ring-buffer length is
  ///   `round(historyDurationMs × tickHz / 1000)`.
  /// - [minBarLevel]: hard floor for every bar value in the snapshot.
  /// - [microModulationAmplitude]: maximum relative amplitude of the
  ///   deterministic micromodulation added to live-zone bars.
  WaveformPipeline({
    required this.barCount,
    required double liveZoneRatio,
    required this.attackTimeConstantMs,
    required this.releaseTimeConstantMs,
    required double tickHz,
    required double historyDurationMs,
    required this.minBarLevel,
    required this.microModulationAmplitude,
  }) : _liveZoneBarCount = math.max(
         0,
         math.min(barCount, (liveZoneRatio * barCount).round()),
       ),
       _ringBufferLength = math.max(
         1,
         (historyDurationMs * tickHz / 1000.0).round(),
       ) {
    _history = List<double>.filled(_ringBufferLength, 0.0);
  }

  final int barCount;
  final double attackTimeConstantMs;
  final double releaseTimeConstantMs;
  final double minBarLevel;
  final double microModulationAmplitude;

  final int _liveZoneBarCount;
  final int _ringBufferLength;

  /// Ring buffer: index 0 holds the most recently pushed sample, index
  /// `_ringBufferLength - 1` holds the oldest sample currently retained.
  late List<double> _history;

  double _targetLevel = 0.0;
  double _displayLevel = 0.0;
  DateTime? _lastTickTime;

  /// Records a new normalised input level. Shifts the ring buffer so the new
  /// sample sits at slot 0 and older samples move toward the tail.
  void pushSample(double level, DateTime now) {
    _targetLevel = level;
    // Shift history one slot toward the tail, drop the oldest entry.
    for (var i = _ringBufferLength - 1; i > 0; i--) {
      _history[i] = _history[i - 1];
    }
    _history[0] = level;
  }

  /// Advances the smoothing state toward [_targetLevel] using asymmetric
  /// time constants. The first call after construction or reset establishes
  /// the time baseline without changing the display level.
  void tick(DateTime now) {
    final last = _lastTickTime;
    if (last == null) {
      _lastTickTime = now;
      return;
    }
    final deltaMs = now.difference(last).inMicroseconds / 1000.0;
    _lastTickTime = now;
    if (deltaMs <= 0) {
      return;
    }
    final rising = _targetLevel > _displayLevel;
    final tau = rising ? attackTimeConstantMs : releaseTimeConstantMs;
    if (tau <= 0) {
      _displayLevel = _targetLevel;
      return;
    }
    final alpha = 1.0 - math.exp(-deltaMs / tau);
    _displayLevel += (_targetLevel - _displayLevel) * alpha;
  }

  /// Returns the rendered bar heights. Length is always [barCount]; every
  /// value lies in `[minBarLevel, 1.0]`.
  List<double> snapshot() {
    final out = List<double>.filled(barCount, minBarLevel);
    if (barCount == 0) {
      return out;
    }

    // Live zone occupies the central [liveStart, liveEnd) window.
    final liveStart = ((barCount - _liveZoneBarCount) / 2).floor();
    final liveEnd = liveStart + _liveZoneBarCount;

    // Fill live zone with smoothed live level + deterministic micromodulation.
    for (var i = liveStart; i < liveEnd; i++) {
      final mod = _microModulation(i);
      final value = _displayLevel + mod * _displayLevel;
      out[i] = _clamp(value);
    }

    // Fill flanks symmetrically from the ring buffer.
    //
    // Left flank: bar at `liveStart - 1` shows the youngest sample (slot 0),
    // bar at index 0 shows the oldest sample reachable within
    // `liveStart` slots.
    for (var k = 0; k < liveStart; k++) {
      final leftIndex = liveStart - 1 - k;
      final rightIndex = liveEnd + k;
      final historySlot = math.min(k, _ringBufferLength - 1);
      final value = _history[historySlot];
      final clamped = _clamp(value);
      if (leftIndex >= 0 && leftIndex < barCount) {
        out[leftIndex] = clamped;
      }
      if (rightIndex >= 0 && rightIndex < barCount) {
        out[rightIndex] = clamped;
      }
    }

    return out;
  }

  /// Clears the ring buffer, the smoothing state, and the tick baseline.
  void reset() {
    for (var i = 0; i < _ringBufferLength; i++) {
      _history[i] = 0.0;
    }
    _targetLevel = 0.0;
    _displayLevel = 0.0;
    _lastTickTime = null;
  }

  double _clamp(double value) {
    if (value < minBarLevel) return minBarLevel;
    if (value > 1.0) return 1.0;
    return value;
  }

  /// Deterministic, seed-free micromodulation factor for bar [barIndex].
  ///
  /// Returns a value in `[-microModulationAmplitude, microModulationAmplitude]`
  /// derived from a fixed sine pattern keyed on the bar index. Multiplying by
  /// the current live level keeps modulation proportional and silent at rest.
  double _microModulation(int barIndex) {
    // Mix two coprime sine phases per bar index for visual variation while
    // staying fully deterministic and dependency-free.
    final phase = barIndex * 1.7;
    final wave = (math.sin(phase) + math.sin(phase * 1.31 + 0.5)) / 2.0;
    return wave * microModulationAmplitude;
  }
}

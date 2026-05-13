/// SafetyGuard — amplitude-stream → safety-event transformer.
///
/// Encapsulates all "guard" state that was previously scattered across
/// [RecordingOrchestrator]: dead-mic detection, auto-stop on silence,
/// 90 % duration-warning, and hard duration limit.
///
/// Usage:
/// ```dart
/// final sub = audioNotifier.amplitudeStream
///     ?.transform(SafetyGuard(config: SafetyGuardConfig(...)))
///     .listen((event) => _routeEvent(event));
/// ```
library;

import 'dart:async';

// ---------------------------------------------------------------------------
// SafetyEvent sealed class
// ---------------------------------------------------------------------------

/// Events emitted by [SafetyGuard] when a guard condition is triggered.
///
/// Each variant maps to exactly one action in the orchestrator:
/// - [SafetyEvent.deadMicTimeoutReached]  → stop + error
/// - [SafetyEvent.silenceAutoStop]        → stop + transcribe
/// - [SafetyEvent.durationWarningAt90]    → play warning sound (non-terminal)
/// - [SafetyEvent.durationLimitReached]   → stop + transcribe
sealed class SafetyEvent {
  const SafetyEvent();
}

/// No audio detected within [SafetyGuardConfig.deadMicTimeout] seconds.
final class DeadMicTimeoutReached extends SafetyEvent {
  const DeadMicTimeoutReached();
}

/// Speech was detected, then silence for [SafetyGuardConfig.autoStopSilence]
/// seconds — recording should be stopped and transcribed.
final class SilenceAutoStop extends SafetyEvent {
  const SilenceAutoStop();
}

/// Recording has reached 90 % of [SafetyGuardConfig.maxDurationSeconds] —
/// play a warning sound; recording is still active.
final class DurationWarningAt90 extends SafetyEvent {
  const DurationWarningAt90();
}

/// Recording has reached 100 % of [SafetyGuardConfig.maxDurationSeconds] —
/// stop and transcribe.
final class DurationLimitReached extends SafetyEvent {
  const DurationLimitReached();
}

// Convenience constants so call-sites can use the sealed-class hierarchy or
// reference the familiar enum-style names.
const SafetyEvent deadMicTimeoutReached = DeadMicTimeoutReached();
const SafetyEvent silenceAutoStop = SilenceAutoStop();
const SafetyEvent durationWarningAt90 = DurationWarningAt90();
const SafetyEvent durationLimitReached = DurationLimitReached();

// ---------------------------------------------------------------------------
// SafetyGuardConfig
// ---------------------------------------------------------------------------

/// Immutable configuration snapshot for a single [SafetyGuard] session.
///
/// All time values are in seconds; `0` means the corresponding guard is
/// disabled.
class SafetyGuardConfig {
  const SafetyGuardConfig({
    this.deadMicTimeout = 3.0,
    this.autoStopSilence = 0.0,
    this.maxDurationSeconds = 120,
    this.samplesPerSecond = 10,
  });

  /// Seconds of continuous silence (no speech at all) before dead-mic fires.
  /// `0` disables dead-mic detection.
  final double deadMicTimeout;

  /// Seconds of silence *after* speech is detected before auto-stop fires.
  /// `0` disables silence-auto-stop.
  final double autoStopSilence;

  /// Hard maximum recording duration in seconds.
  /// `0` disables the duration limit and warning.
  final int maxDurationSeconds;

  /// How many amplitude samples arrive per second (default 10 ≈ 100 ms each).
  final int samplesPerSecond;
}

// ---------------------------------------------------------------------------
// SafetyGuard
// ---------------------------------------------------------------------------

/// Stream transformer that converts a stream of amplitude samples
/// (`Stream<double>`) into a stream of [SafetyEvent] values.
///
/// **State machine** (entirely encapsulated — callers never touch it):
/// - `_speechDetected`       — true once a sample ≥ [_silenceThreshold] arrives
/// - `_silentSamples`        — consecutive below-threshold samples since last speech
/// - `_guardFired`           — true after the first terminal event (prevents double-fire)
/// - `_durationWarningFired` — true after [DurationWarningAt90] has been emitted
/// - `_elapsedSamples`       — total samples received (used for duration tracking)
///
/// The transformer closes its output stream after emitting a terminal event
/// ([DeadMicTimeoutReached], [SilenceAutoStop], [DurationLimitReached]).
/// [DurationWarningAt90] is non-terminal; the stream remains open.
///
/// **Thread safety**: Dart is single-threaded; no synchronisation needed.
class SafetyGuard extends StreamTransformerBase<double, SafetyEvent> {
  SafetyGuard({required this.config});

  /// Amplitude threshold below which a sample is considered "silent".
  /// Matches the original orchestrator constant: peak < 0.02 ≈ silent.
  static const double silenceThreshold = 0.02;

  final SafetyGuardConfig config;

  @override
  Stream<SafetyEvent> bind(Stream<double> stream) {
    late StreamController<SafetyEvent> controller;
    StreamSubscription<double>? upstream;

    // Mutable guard state — isolated inside the closure.
    var speechDetected = false;
    var silentSamples = 0;
    var guardFired = false;
    var durationWarningFired = false;
    var elapsedSamples = 0;

    void emitTerminal(SafetyEvent event) {
      if (guardFired) return;
      guardFired = true;
      controller.add(event);
      upstream?.cancel();
      controller.close();
    }

    void onData(double level) {
      if (guardFired) return;
      elapsedSamples++;

      // ── Max recording duration ──────────────────────────────────────────
      final maxDur = config.maxDurationSeconds;
      if (maxDur > 0) {
        final elapsedSec = elapsedSamples / config.samplesPerSecond;

        if (elapsedSec >= maxDur) {
          emitTerminal(durationLimitReached);
          return;
        }

        // 90 % warning (non-terminal)
        if (!durationWarningFired &&
            elapsedSec >= (maxDur * 0.9).floorToDouble()) {
          durationWarningFired = true;
          controller.add(durationWarningAt90);
          // Do NOT return — continue evaluating other guards this sample.
        }
      }

      final isSilent = level < silenceThreshold;

      if (!isSilent) {
        speechDetected = true;
        silentSamples = 0;
        return;
      }

      // Silent sample.
      silentSamples++;

      // ── Dead-mic detection (no speech yet) ──────────────────────────────
      if (!speechDetected && config.deadMicTimeout > 0) {
        final threshold = (config.deadMicTimeout * config.samplesPerSecond)
            .round();
        if (silentSamples >= threshold) {
          emitTerminal(deadMicTimeoutReached);
          return;
        }
      }

      // ── Auto-stop on silence (after speech detected) ─────────────────────
      if (speechDetected && config.autoStopSilence > 0) {
        final threshold = (config.autoStopSilence * config.samplesPerSecond)
            .round();
        if (silentSamples >= threshold) {
          emitTerminal(silenceAutoStop);
          return;
        }
      }
    }

    controller = StreamController<SafetyEvent>(
      onListen: () {
        upstream = stream.listen(
          onData,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => upstream?.pause(),
      onResume: () => upstream?.resume(),
      onCancel: () => upstream?.cancel(),
    );

    return controller.stream;
  }
}

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
import 'dart:math' as math;

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

/// No sample has reached the silence threshold yet, [SafetyGuard
/// .noSignalWarningSeconds] after the start — the microphone may be muted or
/// the wrong input. Emitted once per recording; non-terminal, so the
/// recording keeps running and the dead-mic timeout still applies.
final class NoSignalWarning extends SafetyEvent {
  const NoSignalWarning();
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
const SafetyEvent noSignalWarning = NoSignalWarning();
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
  /// [samplesPerSecond] has no sensible default — it must match the producer's
  /// emit rate (see `amplitudeSamplesPerSecond` in `audio_service.dart`).
  /// Forgetting it lets *all* guard timers drift, so it's a required argument.
  const SafetyGuardConfig({
    required this.samplesPerSecond,
    this.deadMicTimeout = 3.0,
    this.autoStopSilence = 0.0,
    this.maxDurationSeconds = 120,
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
/// - `_speechDetected`       — true once the level stays ≥ [silenceThreshold]
///   for [speechMinDuration]
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

  /// How long the level must stay at or above [silenceThreshold] before the
  /// recording counts as containing speech.
  static const Duration speechMinDuration = Duration(milliseconds: 300);

  /// Longest silent dip that does not restart the [speechMinDuration] count.
  /// Speech dips briefly between syllables; noise spikes are further apart.
  static const Duration speechMaxGap = Duration(milliseconds: 80);

  /// Seconds without any signal after the start before [NoSignalWarning].
  static const double noSignalWarningSeconds = 1.0;

  final SafetyGuardConfig config;

  /// At least one sample, rounded up, for [duration] at the configured rate.
  int _samplesFor(Duration duration) => math.max(
    1,
    (config.samplesPerSecond * duration.inMilliseconds / 1000).ceil(),
  );

  @override
  Stream<SafetyEvent> bind(Stream<double> stream) {
    late StreamController<SafetyEvent> controller;
    StreamSubscription<double>? upstream;

    // Mutable guard state — isolated inside the closure.
    var speechDetected = false;
    var silentSamples = 0;
    var guardFired = false;
    var durationWarningFired = false;
    var noSignalWarningFired = false;
    var elapsedSamples = 0;
    final speechRun = _SpeechRun(
      minSamples: _samplesFor(speechMinDuration),
      maxGapSamples: _samplesFor(speechMaxGap),
    );

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
        if (speechDetected) {
          silentSamples = 0;
          return;
        }
        // A click or a noise spike is loud for a sample or two; only a
        // sustained level counts as speech. Until then the dead-mic count
        // keeps running, so one spike cannot disarm it for the session.
        if (speechRun.addLoud()) {
          speechDetected = true;
          silentSamples = 0;
        }
        return;
      }

      // Silent sample.
      speechRun.addSilent();
      silentSamples++;

      // ── No-signal hint (no speech yet, non-terminal, once) ──────────────
      // Only while dead-mic detection is enabled and fires later than the
      // hint: the hint is a warning ahead of the terminal stop, never a
      // second event on the same sample.
      if (!speechDetected &&
          !noSignalWarningFired &&
          config.deadMicTimeout > noSignalWarningSeconds &&
          silentSamples >=
              (noSignalWarningSeconds * config.samplesPerSecond).round()) {
        noSignalWarningFired = true;
        controller.add(noSignalWarning);
      }

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

/// Counts a run of loud samples towards [SafetyGuard.speechMinDuration],
/// tolerating silent dips of up to [maxGapSamples].
class _SpeechRun {
  _SpeechRun({required this.minSamples, required this.maxGapSamples});

  final int minSamples;
  final int maxGapSamples;
  int _loud = 0;
  int _gap = 0;

  /// Returns true once the run is long enough to count as speech.
  bool addLoud() {
    _gap = 0;
    return ++_loud >= minSamples;
  }

  void addSilent() {
    if (++_gap > maxGapSamples) _loud = 0;
  }
}

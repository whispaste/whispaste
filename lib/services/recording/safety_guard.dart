/// SafetyGuard — guard-sample stream → safety-event transformer.
///
/// Encapsulates all "guard" state that was previously scattered across
/// [RecordingOrchestrator]: dead-mic detection, auto-stop on silence,
/// 90 % duration-warning, and hard duration limit.
///
/// Usage:
/// ```dart
/// final sub = audioNotifier.guardSampleStream
///     ?.transform(SafetyGuard(config: SafetyGuardConfig(...)))
///     .listen((event) => _routeEvent(event));
/// ```
library;

import 'dart:async';
import 'dart:math' as math;

import '../audio/speech_level_mapper.dart';
import '../audio/speech_presence.dart' as presence;

// ---------------------------------------------------------------------------
// GuardSample
// ---------------------------------------------------------------------------

/// One amplitude tick as the guard sees it (#984).
///
/// [dbFs] is the raw peak of the window: `-inf` for digital zero or for no
/// data at all, NaN for a broken buffer. [level] is the meter level mapped
/// from it, which clamps everything below about -60 dBFS to 0. The guard
/// needs both: speech and silence after speech read the level, but "no
/// signal" reads the raw value, so a quiet but working microphone (a finite
/// -70 dBFS) never counts as dead.
class GuardSample {
  const GuardSample({required this.dbFs, required this.level});

  /// The sample of one tick of the audio service, mapped like the meter.
  factory GuardSample.fromDbFs(double dbFs) =>
      GuardSample(dbFs: dbFs, level: const SpeechLevelMapper().map(dbFs));

  final double dbFs;
  final double level;

  /// The input delivered something: neither digital zero, nor no data, nor
  /// a non-finite value.
  bool get hasSignal => dbFs.isFinite;
}

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

/// The microphone delivered no signal at all ([GuardSample.hasSignal] false)
/// for [SafetyGuardConfig.deadMicTimeout] seconds before any speech.
final class DeadMicTimeoutReached extends SafetyEvent {
  const DeadMicTimeoutReached();
}

/// The microphone has delivered no signal at all ([GuardSample.hasSignal]
/// false) for [SafetyGuard.noSignalWarningSeconds] before any speech — it
/// may be muted at the hardware or the wrong input. A quiet microphone does
/// not count (#984). Emitted once per recording; non-terminal, so the
/// recording keeps running and the dead-mic timeout still applies.
final class NoSignalWarning extends SafetyEvent {
  const NoSignalWarning();
}

/// The first signal after a [NoSignalWarning]: the hint can go. Non-terminal,
/// at most once per recording.
final class SignalArrived extends SafetyEvent {
  const SignalArrived();
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
const SafetyEvent signalArrived = SignalArrived();
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

  /// Seconds without any signal (digital zero, no data, non-finite) before
  /// speech, after which dead-mic fires. A quiet level never counts.
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

/// Stream transformer that converts a stream of [GuardSample]s into a stream
/// of [SafetyEvent] values.
///
/// **State machine** (entirely encapsulated — callers never touch it):
/// - `_speechDetected`       — true once the level stays ≥ [silenceThreshold]
///   for [speechMinDuration]
/// - `_deadSamples`          — consecutive samples without signal before speech
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
class SafetyGuard extends StreamTransformerBase<GuardSample, SafetyEvent> {
  SafetyGuard({required this.config});

  /// Level below which a sample is silent; the shared definition of speech
  /// (`speech_presence.dart`), also used by the live preview.
  static const double silenceThreshold = presence.speechLevelThreshold;

  /// Shortest loud run that counts as speech (`speech_presence.dart`).
  static const Duration speechMinDuration = presence.speechMinDuration;

  /// Longest dip inside such a run (`speech_presence.dart`).
  static const Duration speechMaxGap = presence.speechMaxGap;

  /// Seconds without any signal after the start before [NoSignalWarning].
  static const double noSignalWarningSeconds = 1.0;

  final SafetyGuardConfig config;

  /// Seconds added to [SafetyGuardConfig.maxDurationSeconds] by
  /// [extendDuration] while the stream runs.
  int _extraSeconds = 0;

  /// The limit the 90 % warning last fired for; a new limit after
  /// [extendDuration] warns again.
  int _warnedLimit = 0;

  /// The running limit in seconds including extensions; 0 without a limit.
  int get _maxDuration => config.maxDurationSeconds > 0
      ? config.maxDurationSeconds + _extraSeconds
      : 0;

  /// Extends the duration limit of the running recording by [seconds] (the
  /// notice card's "Record {n} more min", overlay F2). Without a limit
  /// (`maxDurationSeconds == 0`) nothing changes.
  void extendDuration(int seconds) {
    if (config.maxDurationSeconds <= 0 || seconds <= 0) return;
    _extraSeconds += seconds;
  }

  /// Seconds the recording runs on past the limit, giving the notice card's
  /// "Record {n} more min" a click that arrives right at the limit (#858).
  /// The card counts wall-clock ticks, this guard counts samples; the two
  /// clocks drift, so a click shown before the limit could land after it.
  /// 0 (default) stops exactly at the limit.
  int limitGraceSeconds = 0;

  /// At least one sample, rounded up, for [duration] at the configured rate.
  int _samplesFor(Duration duration) => math.max(
    1,
    (config.samplesPerSecond * duration.inMilliseconds / 1000).ceil(),
  );

  @override
  Stream<SafetyEvent> bind(Stream<GuardSample> stream) {
    late StreamController<SafetyEvent> controller;
    StreamSubscription<GuardSample>? upstream;

    // Mutable guard state — isolated inside the closure.
    var speechDetected = false;
    var silentSamples = 0;
    var deadSamples = 0;
    var guardFired = false;
    var noSignalWarningFired = false;
    var signalArrivedFired = false;
    var elapsedSamples = 0;
    final speechRun = presence.SpeechRun(
      minWindows: _samplesFor(speechMinDuration),
      maxGapWindows: _samplesFor(speechMaxGap),
    );

    void emitTerminal(SafetyEvent event) {
      if (guardFired) return;
      guardFired = true;
      controller.add(event);
      upstream?.cancel();
      controller.close();
    }

    void onData(GuardSample sample) {
      if (guardFired) return;
      elapsedSamples++;

      // ── Max recording duration ──────────────────────────────────────────
      final maxDur = _maxDuration;
      if (maxDur > 0) {
        final elapsedSec = elapsedSamples / config.samplesPerSecond;

        if (elapsedSec >= maxDur + limitGraceSeconds) {
          emitTerminal(durationLimitReached);
          return;
        }

        // 90 % warning (non-terminal)
        if (_warnedLimit != maxDur &&
            elapsedSec >= (maxDur * 0.9).floorToDouble()) {
          _warnedLimit = maxDur;
          controller.add(durationWarningAt90);
          // Do NOT return — continue evaluating other guards this sample.
        }
      }

      // ── No signal before speech (hint, then dead-mic) ─────────────────────
      // Counts only ticks without any signal; a finite level, however quiet,
      // is a working microphone and resets the count (#984).
      if (!speechDetected) {
        deadSamples = sample.hasSignal ? 0 : deadSamples + 1;
        if (sample.hasSignal && noSignalWarningFired && !signalArrivedFired) {
          signalArrivedFired = true;
          controller.add(signalArrived);
        }

        // The hint is a warning ahead of the terminal stop: only while
        // dead-mic detection is enabled and fires later than the hint, so
        // never a second event on the same sample.
        if (!noSignalWarningFired &&
            config.deadMicTimeout > noSignalWarningSeconds &&
            deadSamples >=
                (noSignalWarningSeconds * config.samplesPerSecond).round()) {
          noSignalWarningFired = true;
          controller.add(noSignalWarning);
        }

        if (config.deadMicTimeout > 0 &&
            deadSamples >=
                (config.deadMicTimeout * config.samplesPerSecond).round()) {
          emitTerminal(deadMicTimeoutReached);
          return;
        }
      }

      final isSilent = sample.level < silenceThreshold;

      if (!isSilent) {
        if (speechDetected) {
          silentSamples = 0;
          return;
        }
        // A click or a noise spike is loud for a sample or two; only a
        // sustained level counts as speech.
        if (speechRun.addLoud()) {
          speechDetected = true;
          silentSamples = 0;
        }
        return;
      }

      // Silent sample.
      speechRun.addSilent();
      silentSamples++;

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

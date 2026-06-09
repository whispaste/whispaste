/// Onboarding-only microphone probe.
///
/// Captures a short PCM stream from the system default input (or a caller-
/// supplied [InputDevice] on platforms that respect it), runs it through
/// [AmplitudeFromPcm], and exposes both a normalised level for waveform
/// visualisation and a single [MicProbeOutcome] future that resolves once the
/// probe detects sustained speech, times out into silence, hits a permission
/// denial, or fails outright.
///
/// Lives outside [AudioServiceNotifier] on purpose: onboarding must run before
/// any real recording session and the probe owns its own short-lived recorder
/// so it never collides with the main capture pipeline. The recorder is hidden
/// behind [MicProbeRecorder] so tests can drive the probe deterministically
/// without touching the platform plugin.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../services/audio/amplitude_from_pcm.dart';

/// Result of a single [OnboardingMicProbe.start] run.
enum MicProbeOutcome {
  /// At least [OnboardingMicProbe.sustainedAbove] of continuous audio crossed
  /// the speech threshold — the mic is producing real signal.
  speechDetected,

  /// The probe ran for [OnboardingMicProbe.timeout] without ever crossing the
  /// threshold. Likely a muted device, wrong default input, or a hardware
  /// problem. The UI surfaces a retry / device-picker affordance.
  silence,

  /// The OS denied microphone access — handled separately from [error]
  /// because the UI shows TCC-specific instructions for it.
  permissionDenied,

  /// Anything else (recorder threw, stream errored, plugin crashed). The UI
  /// folds this into the same retry path as [silence] but with a generic
  /// message.
  error,
}

/// Minimal recorder surface the probe consumes from `package:record`. Exists
/// so tests can supply a deterministic fake without spinning up a real
/// platform plugin.
abstract class MicProbeRecorder {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream(RecordConfig config);
  Future<bool> isRecording();
  Future<String?> stop();
  Future<void> dispose();
  Future<List<InputDevice>> listInputDevices();
}

/// Default [MicProbeRecorder] implementation backed by a real [AudioRecorder].
class _RealMicProbeRecorder implements MicProbeRecorder {
  _RealMicProbeRecorder() : _inner = AudioRecorder();

  final AudioRecorder _inner;

  @override
  Future<bool> hasPermission() => _inner.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _inner.startStream(config);

  @override
  Future<bool> isRecording() => _inner.isRecording();

  @override
  Future<String?> stop() => _inner.stop();

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Future<List<InputDevice>> listInputDevices() => _inner.listInputDevices();
}

/// Drives one onboarding microphone verification cycle.
///
/// Lifecycle:
/// 1. Construct (optionally inject a [MicProbeRecorder] for tests).
/// 2. `await start(device: …)` — returns the outcome once decided. While the
///    future is pending, [level] streams 0.0–1.0 amplitude values for the UI.
/// 3. Call [stop] to abort early or between retries; call [dispose] when the
///    widget is removed.
///
/// `start` can be called again after `stop` — used by the retry / device-
/// switch flow.
class OnboardingMicProbe {
  OnboardingMicProbe({
    MicProbeRecorder? recorder,
    this.timeout = const Duration(seconds: 5),
    this.speechThresholdDbFs = -42.0,
    this.sustainedAbove = const Duration(milliseconds: 120),
    this._pollInterval = const Duration(milliseconds: 40),
  }) : _recorder = recorder ?? _RealMicProbeRecorder();

  /// Wall-clock budget for detecting speech before the probe gives up.
  final Duration timeout;

  /// Peak dBFS that has to be crossed to count as real signal. Set just above
  /// the noise floor of a typical built-in mic in a quiet room (~ −45 dBFS),
  /// with headroom so room tone alone does not trigger.
  final double speechThresholdDbFs;

  /// Continuous duration above [speechThresholdDbFs] required before the
  /// outcome flips to [MicProbeOutcome.speechDetected]. Filters out single
  /// transient peaks (chair creak, door slam) that would otherwise pass.
  final Duration sustainedAbove;

  final MicProbeRecorder _recorder;
  final Duration _pollInterval;

  final ValueNotifier<double> _level = ValueNotifier<double>(0.0);

  /// Normalised amplitude in `[0.0, 1.0]`. Driven by the live PCM stream while
  /// the probe is running; stays at `0.0` before [start] and after [stop].
  ValueListenable<double> get level => _level;

  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<double>? _ampSub;
  AmplitudeFromPcm? _amplitudeFromPcm;
  Timer? _timeoutTimer;
  Completer<MicProbeOutcome>? _outcome;
  Duration _sustainedAccum = Duration.zero;
  bool _disposed = false;

  /// Enumerates available input devices. Empty list on failure — callers
  /// should treat that as "fall back to system default", not as an error.
  Future<List<InputDevice>> listInputDevices() async {
    try {
      return await _recorder.listInputDevices();
    } catch (_) {
      return const <InputDevice>[];
    }
  }

  /// Runs one probe cycle and resolves with the outcome.
  ///
  /// [device] is forwarded into [RecordConfig.device]. On macOS the
  /// underlying `record_macos` plugin ignores this field (see
  /// [AudioRoutingService]); callers that need a non-default device on macOS
  /// must flip the system default before calling and restore it on tear-down.
  ///
  /// Idempotent against concurrent calls — if a probe is already running the
  /// in-flight future is returned. After [stop] the probe can be started
  /// again (retry / device-switch flow).
  Future<MicProbeOutcome> start({InputDevice? device}) {
    if (_disposed) return Future.value(MicProbeOutcome.error);
    final existing = _outcome;
    if (existing != null && !existing.isCompleted) return existing.future;

    final outcome = _outcome = Completer<MicProbeOutcome>();
    _sustainedAccum = Duration.zero;
    _level.value = 0.0;

    unawaited(_runStream(outcome, device));
    return outcome.future;
  }

  Future<void> _runStream(
    Completer<MicProbeOutcome> outcome,
    InputDevice? device,
  ) async {
    try {
      final granted = await _recorder.hasPermission();
      if (outcome.isCompleted) return;
      if (!granted) {
        outcome.complete(MicProbeOutcome.permissionDenied);
        return;
      }

      _amplitudeFromPcm = AmplitudeFromPcm(pollInterval: _pollInterval);
      _ampSub = _amplitudeFromPcm!.stream.listen(_onDbFs);

      final pcmStream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: false,
          noiseSuppress: true,
          device: device,
        ),
      );
      if (outcome.isCompleted) {
        await _teardownCapture();
        return;
      }
      _pcmSub = pcmStream.listen(
        (bytes) => _amplitudeFromPcm?.addChunk(bytes),
        onError: (Object _, StackTrace _) =>
            _completeIfPending(MicProbeOutcome.error),
        cancelOnError: true,
      );

      _timeoutTimer = Timer(timeout, () {
        _completeIfPending(MicProbeOutcome.silence);
      });
    } catch (_) {
      _completeIfPending(MicProbeOutcome.error);
    }
  }

  void _onDbFs(double dbFs) {
    // dBFS → 0..1 mapping for waveform visualisation. -60..0 covers everything
    // from a quiet room to clipping, which is enough headroom for an
    // onboarding-grade meter.
    final clamped = dbFs.isFinite ? dbFs.clamp(-60.0, 0.0) : -60.0;
    _level.value = (clamped + 60.0) / 60.0;

    if (dbFs > speechThresholdDbFs) {
      _sustainedAccum += _pollInterval;
      if (_sustainedAccum >= sustainedAbove) {
        _completeIfPending(MicProbeOutcome.speechDetected);
      }
    } else {
      // Natural speech has short pauses inside a word (plosives, stops).
      // Decay gently instead of hard-resetting so a brief dip doesn't make
      // the user "start over" perceptually.
      final decayed = _sustainedAccum - (_pollInterval ~/ 2);
      _sustainedAccum = decayed < Duration.zero ? Duration.zero : decayed;
    }
  }

  void _completeIfPending(MicProbeOutcome value) {
    final completer = _outcome;
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
    }
  }

  /// Stops the active stream but keeps the recorder alive for a retry.
  Future<void> stop() async {
    _completeIfPending(MicProbeOutcome.error);
    await _teardownCapture();
    _level.value = 0.0;
  }

  Future<void> _teardownCapture() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _amplitudeFromPcm?.dispose();
    _amplitudeFromPcm = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // best-effort — the recorder may already be torn down on some hosts
    }
  }

  /// Releases the underlying recorder. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardownCapture();
    try {
      await _recorder.dispose();
    } catch (_) {
      // best-effort
    }
  }
}

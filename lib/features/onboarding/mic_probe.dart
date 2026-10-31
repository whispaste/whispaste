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

import '../../core/logging/app_logger.dart';
import '../../services/audio/amplitude_from_pcm.dart';
import '../../services/audio/level_smoother.dart';
import '../../services/audio/speech_level_mapper.dart';

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

  /// The recorder could not start and the system lists no input device at
  /// all: nothing is plugged in or enabled.
  noDevice,

  /// The stream ran and then broke off: the device was unplugged or switched
  /// off mid-test.
  disconnected,

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
PcmLevelMeter _defaultMeter({required Duration pollInterval}) =>
    AmplitudeFromPcm(pollInterval: pollInterval);

class OnboardingMicProbe {
  static final _log = AppLogger('MicProbe');

  OnboardingMicProbe({
    MicProbeRecorder? recorder,
    this.timeout = const Duration(seconds: 5),
    this.speechThresholdDbFs = -42.0,
    this.sustainedAbove = const Duration(milliseconds: 120),
    this._pollInterval = const Duration(milliseconds: 40),
    PcmLevelMeter Function({required Duration pollInterval})? meterFactory,
  }) : _recorder = recorder ?? _RealMicProbeRecorder(),
       _meterFactory = meterFactory ?? _defaultMeter;

  /// Wall-clock budget for detecting speech before the probe gives up with
  /// [MicProbeOutcome.silence]. `null` listens without a budget: the caller
  /// then owns the silence decision and the outcome future resolves only on
  /// speech, permission denial or an error.
  final Duration? timeout;

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

  /// Same curve and smoothing as the recording overlay, so the first
  /// waveform a user sees moves like the one they will dictate with.
  static const _mapper = SpeechLevelMapper();
  final LevelSmoother _smoother = LevelSmoother();
  final ValueNotifier<bool> _capturing = ValueNotifier<bool>(false);

  /// True while a stream is open and delivering audio. Lets the UI clear an
  /// error as soon as an automatic retry gets the device back, without
  /// waiting for speech.
  ValueListenable<bool> get capturing => _capturing;

  /// Normalised amplitude in `[0.0, 1.0]`. Driven by the live PCM stream while
  /// the probe is running; stays at `0.0` before [start] and after [stop].
  ValueListenable<double> get level => _level;

  /// Builds the level meter of each run. Tests inject a meter without timers.
  final PcmLevelMeter Function({required Duration pollInterval}) _meterFactory;

  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<double>? _ampSub;
  PcmLevelMeter? _meter;
  Timer? _timeoutTimer;

  /// Bumped by every start, stop and dispose. A run whose generation is no
  /// longer current must not touch the shared fields after an await.
  int _generation = 0;
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
  /// Idempotent against concurrent calls — if a probe is already running the
  /// in-flight future is returned. After [stop] the probe can be started
  /// again (retry / device-switch flow).
  Future<MicProbeOutcome> start({InputDevice? device}) {
    if (_disposed) return Future.value(MicProbeOutcome.error);
    final existing = _outcome;
    if (existing != null && !existing.isCompleted) return existing.future;

    final generation = ++_generation;
    final outcome = _outcome = Completer<MicProbeOutcome>();
    _sustainedAccum = Duration.zero;
    _smoother.reset();
    _level.value = 0.0;

    unawaited(_runStream(generation, outcome, device));
    return outcome.future;
  }

  Future<void> _runStream(
    int generation,
    Completer<MicProbeOutcome> outcome,
    InputDevice? device,
  ) async {
    // What this run created. A superseded run releases exactly these objects
    // and never the ones of a newer run.
    PcmLevelMeter? meter;
    StreamSubscription<double>? ampSub;
    StreamSubscription<Uint8List>? pcmSub;
    bool current() => generation == _generation && !outcome.isCompleted;

    try {
      final granted = await _recorder.hasPermission();
      if (!current()) return;
      if (!granted) {
        outcome.complete(MicProbeOutcome.permissionDenied);
        return;
      }

      final created = _meterFactory(pollInterval: _pollInterval);
      meter = created;
      ampSub = created.stream.listen((dbFs) {
        if (generation == _generation) _onDbFs(dbFs);
      });
      _meter = created;
      _ampSub = ampSub;

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
      if (!current()) {
        // Superseded while starting. Stop the stream this run just opened,
        // unless a newer run already owns the recorder.
        await ampSub.cancel();
        await _releaseRun(meter: meter, ampSub: ampSub, pcmSub: null);
        final owned = _outcome != null && !_outcome!.isCompleted;
        if (!owned) await _stopRecorderQuietly();
        return;
      }
      pcmSub = pcmStream.listen(
        created.addChunk,
        onError: (Object _, StackTrace _) {
          _capturing.value = false;
          if (!outcome.isCompleted) {
            outcome.complete(MicProbeOutcome.disconnected);
          }
        },
        // A stream that ends on its own while this run still listens lost
        // its device.
        onDone: () {
          if (!current()) return;
          _capturing.value = false;
          outcome.complete(MicProbeOutcome.disconnected);
        },
        cancelOnError: true,
      );
      _pcmSub = pcmSub;
      _capturing.value = true;

      final budget = timeout;
      if (budget != null) {
        _timeoutTimer = Timer(budget, () {
          if (generation == _generation) {
            _completeIfPending(MicProbeOutcome.silence);
          }
        });
      }
    } catch (_) {
      if (!outcome.isCompleted) {
        // Without any listed input the cause is clear; otherwise the device
        // is busy, exclusive or failed in a way the plugin does not tell.
        final none = (await listInputDevices()).isEmpty;
        if (!outcome.isCompleted) {
          outcome.complete(
            none ? MicProbeOutcome.noDevice : MicProbeOutcome.error,
          );
        }
      }
      await ampSub?.cancel();
      await pcmSub?.cancel();
      await _releaseRun(meter: meter, ampSub: ampSub, pcmSub: pcmSub);
    }
  }

  void _onDbFs(double dbFs) {
    _level.value = _smoother.step(
      _mapper.map(dbFs),
      _pollInterval.inMicroseconds / 1000.0,
    );

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
    _generation++;
    _completeIfPending(MicProbeOutcome.error);
    await _teardownCapture();
    _smoother.reset();
    _level.value = 0.0;
  }

  /// Releases the objects of the latest run. Their fields are detached
  /// before the first await, so a start that begins meanwhile is not touched.
  Future<void> _teardownCapture() async {
    _capturing.value = false;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final pcmCancel = _pcmSub?.cancel();
    _pcmSub = null;
    final ampCancel = _ampSub?.cancel();
    _ampSub = null;
    final meter = _meter;
    _meter = null;
    await pcmCancel;
    await ampCancel;
    await meter?.dispose();
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (e) {
      _log.debug(
        'MicProbe recorder stop failed during teardown (non-fatal): $e',
      );
    }
  }

  Future<void> _stopRecorderQuietly() async {
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (e) {
      _log.debug('MicProbe recorder stop failed (non-fatal): $e');
    }
  }

  /// Releases the meter of one run and clears the fields only while they still
  /// hold that run's objects. The subscriptions are cancelled by the caller.
  Future<void> _releaseRun({
    required PcmLevelMeter? meter,
    required StreamSubscription<double>? ampSub,
    required StreamSubscription<Uint8List>? pcmSub,
  }) async {
    if (pcmSub != null && identical(_pcmSub, pcmSub)) _pcmSub = null;
    if (ampSub != null && identical(_ampSub, ampSub)) _ampSub = null;
    if (meter != null && identical(_meter, meter)) _meter = null;
    await meter?.dispose();
  }

  /// Releases the underlying recorder. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _completeIfPending(MicProbeOutcome.error);
    await _teardownCapture();
    try {
      await _recorder.dispose();
    } catch (e) {
      _log.debug('MicProbe recorder dispose failed (non-fatal): $e');
    }
    _level.dispose();
    _capturing.dispose();
  }
}

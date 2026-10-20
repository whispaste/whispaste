/// Audio capture service — wraps the `record` package for whisper-compatible
/// WAV recording (16 kHz, 16-bit, mono).
///
/// Provides start/stop recording, amplitude streaming for level metering,
/// and temp-file lifecycle management.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/mic_start_trace.dart';
import 'audio/amplitude_from_pcm.dart';
import 'audio/capture/capture_dir.dart';
import 'audio/user_audio_dirs.dart';
import 'audio/input_device_lookup.dart';
import 'audio/mic_start_cache.dart';
import 'audio/pcm_gain_processor.dart';
import 'audio/recording_start_stop_arbiter.dart';
import 'audio/recovery/recording_journal.dart';
import 'audio/recovery/recording_journal_provider.dart';
import 'audio/signal_loss_detector.dart';
import 'audio/speech_level_mapper.dart';
import 'audio/wav_file_writer.dart';
import 'audio_routing_service.dart';
import 'microphone_priority.dart';
import 'path_service.dart';

final _log = AppLogger('AudioService');

// ---------------------------------------------------------------------------
// Audio service state
// ---------------------------------------------------------------------------

/// Lifecycle of the audio capture.
enum AudioCaptureState { idle, recording, error }

/// Why `AudioRecorder.startStream` failed, as far as the user is concerned.
enum RecordingStartFailure {
  /// The machine has no input device at all — an expected user condition
  /// (Sentry 123116227), surfaced as "no microphone" and not escalated.
  noMicrophone('no_microphone'),

  /// Any other start failure — a genuine defect worth reporting.
  startFailed('recording_start_failed');

  const RecordingStartFailure(this.errorCode);

  /// Error key consumed by `localizeRecordingError`.
  final String errorCode;
}

/// Classifies a [startStream] failure. The recorder's error text is
/// localized by the OS, so the decision rests on the device enumeration
/// ([inputDeviceCount], `null` when it could not be obtained) and the error
/// type, never on the message.
RecordingStartFailure classifyRecordingStartFailure(
  Object error, {
  required int? inputDeviceCount,
}) {
  if (error is PlatformException && inputDeviceCount == 0) {
    return RecordingStartFailure.noMicrophone;
  }
  return RecordingStartFailure.startFailed;
}

/// Polling interval at which the `record` plugin emits amplitude samples.
///
/// The integer reciprocal is also exposed as [amplitudeSamplesPerSecond] so
/// downstream consumers (e.g. `SafetyGuard`) can convert sample counts into
/// wall-clock seconds without re-deriving the rate. Keep both in sync.
const Duration amplitudePollInterval = Duration(milliseconds: 40);

/// Sample rate of the amplitude stream in Hz — derived from
/// [amplitudePollInterval]. Used by `SafetyGuard` to translate elapsed
/// samples into seconds.
const int amplitudeSamplesPerSecond = 25;

/// Immutable snapshot of the audio service.
class AudioStatus {
  const AudioStatus({
    this.captureState = AudioCaptureState.idle,
    this.filePath,
    this.errorMessage,
    this.hasLiveSamples = false,
  });

  final AudioCaptureState captureState;

  /// Path to the WAV file being recorded (or just recorded).
  final String? filePath;

  final String? errorMessage;

  /// True once the current capture delivered its first non-silent sample. The
  /// capture can be open for a moment before that (device warm-up), and the
  /// overlay keeps its "starting" state until then.
  final bool hasLiveSamples;

  bool get isRecording => captureState == AudioCaptureState.recording;

  AudioStatus withLiveSamples() => AudioStatus(
    captureState: captureState,
    filePath: filePath,
    errorMessage: errorMessage,
    hasLiveSamples: true,
  );

  @override
  String toString() => 'AudioStatus($captureState, file=$filePath)';
}

// ---------------------------------------------------------------------------
// Recorder config — whisper-compatible WAV
// ---------------------------------------------------------------------------

/// Builds a whisper-compatible [RecordConfig], optionally targeting a
/// specific [InputDevice]. Pass `null` to use the system default.
///
/// Uses [AudioEncoder.pcm16bits] because the WAV container is written
/// in-process by [WavFileWriter] off the raw PCM stream. Sample format
/// stays 16 kHz mono 16-bit signed LE for whisper compatibility.
///
/// [autoGain] is conditional on the user's configured input gain: when the
/// user keeps the gain at the default `1.0`, the library-side `autoGain`
/// stays on (today's behaviour). When the user dials the slider away from
/// the default, the in-process [PcmGainProcessor] takes over and the
/// library's autoGain is disabled to avoid two gain stages fighting.
RecordConfig _whisperConfig({InputDevice? device, required bool autoGain}) =>
    RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: autoGain,
      echoCancel: false,
      noiseSuppress: true,
      device: device,
    );

// ---------------------------------------------------------------------------
// Audio service notifier
// ---------------------------------------------------------------------------

/// Manages microphone capture via the `record` package.
///
/// The recording orchestrator calls [startRecording] / [stopRecording] and
/// subscribes to [amplitudeStream] for level metering. On stop, the service
/// returns the path to the captured WAV file.
class AudioServiceNotifier extends Notifier<AudioStatus> {
  AudioRecorder? _recorder;

  /// Permission and device listing reused across recording starts. See
  /// [MicStartCache] for what is kept and when it is dropped.
  final MicStartCache _micCache = MicStartCache();

  /// Drops the cached permission and device listing. The power service calls
  /// this after a wake: devices may have come or gone during sleep.
  void forgetMicStartCache() => _micCache.invalidate();

  /// macOS-only: switches the system default input device for the recording
  /// duration, because `record_macos` cannot route via its own `device` field
  /// (silently ignored on macOS 15/26).
  final AudioRoutingService _audioRouting = AudioRoutingService();

  /// UID of the system default input device captured *before* we override it
  /// in [startRecording]. Restored on stop/error so the user's normal audio
  /// routing returns to what it was. `null` when no override is active.
  String? _originalDefaultInputUid;

  /// Arbitrates the start/stop race documented on [RecordingStartStopArbiter]:
  /// a stop that arrives while [startRecording]'s async setup is still in
  /// flight must abort the capture once setup finishes, not leave it running
  /// unsupervised until the next unrelated start/stop cycle.
  final _startStopArbiter = RecordingStartStopArbiter();

  /// Subscription to the raw PCM stream emitted by [AudioRecorder.startStream].
  StreamSubscription<Uint8List>? _pcmSub;

  /// Subscription to [AmplitudeFromPcm.stream] — feeds the perceptual mapper.
  StreamSubscription<double>? _ampSub;

  /// Active dBFS calculator for the current recording. `null` when idle.
  AmplitudeFromPcm? _amplitudeFromPcm;

  /// Active WAV-container writer for the current recording. `null` when idle.
  WavFileWriter? _wavWriter;

  /// Id of the recovery journal entry for the live recording, if one was written.
  RecordingJournalWriter? _journalWriter;
  static bool _retainedDirReady = false;

  /// Active user-gain processor for the current recording. `null` when idle
  /// or when the user is on the default 1.0 gain (identity passthrough).
  PcmGainProcessor? _gainProcessor;

  /// Number of int16 samples that saturated to the int16 limits during the
  /// most recently finished recording. Reset to 0 at the start of every new
  /// recording. Exposed so callers (e.g. a future `ClippingState` provider in
  /// slice #04) can surface a "your gain was too high" warning.
  int get lastRecordingClippedSamples => _lastRecordingClippedSamples;
  int _lastRecordingClippedSamples = 0;

  /// Amplitude values normalized to 0.0–1.0, emitted ~25 times/second.
  ///
  /// Backed by a single-subscription [StreamController] that the orchestrator
  /// listens to. A new controller is created per recording session.
  StreamController<double>? _amplitudeController;

  /// Public amplitude stream. Listen after calling [startRecording].
  Stream<double>? get amplitudeStream => _amplitudeController?.stream;

  /// Broadcast controller for raw PCM chunks (16-bit mono LE, no WAV
  /// header) — only created when [startRecording] is called with
  /// `streamRawPcm: true` (live-transcript-streaming ticket). `null`
  /// otherwise, so a caller that never opts in never pays for forwarding
  /// every captured chunk to a second listener.
  StreamController<Uint8List>? _pcmChunkController;

  /// Public raw-PCM stream, or `null` when [startRecording] was not called
  /// with `streamRawPcm: true` for the current/last recording. Feeds the
  /// live-transcript-during-recording preview
  /// (`SttServerStateNotifier.feedLivePreviewPcm`) — distinct from
  /// [amplitudeStream], which only carries the derived 0.0-1.0 level, not
  /// the samples themselves.
  Stream<Uint8List>? get pcmChunkStream => _pcmChunkController?.stream;

  /// Completes when the current recording delivers its first non-silent PCM
  /// chunk — the moment the microphone is really live, as opposed to
  /// [startRecording] returning. Feeds the mic-start trace (debug log only).
  /// `null` before the first [startRecording]; never completes for a
  /// recording that stays digitally silent.
  Future<void>? get firstSampleArrived => _firstSample?.future;

  /// Completes the first-sample future of the capture that owns [firstSample]
  /// and flags the status, unless that capture has already been stopped.
  void _markLiveSamples(Completer<void> firstSample) {
    firstSample.complete();
    if (identical(_firstSample, firstSample) &&
        state.captureState == AudioCaptureState.recording) {
      state = state.withLiveSamples();
    }
  }

  Completer<void>? _firstSample;

  @override
  AudioStatus build() {
    ref.onDispose(_cleanup);
    return const AudioStatus();
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Starts recording to a temporary WAV file.
  ///
  /// Reads the selected microphone from [settingsProvider] and resolves it
  /// to an [InputDevice]. Falls back to the system default if the configured
  /// device cannot be found.
  ///
  /// Returns immediately — audio data streams to disk.
  /// Subscribe to [amplitudeStream] for level metering.
  ///
  ///
  /// [streamRawPcm] additionally opens [pcmChunkStream] for this recording
  /// (live-transcript-streaming ticket) — `false` by default so a caller
  /// that never opts in (the setting is off) pays nothing for it: no
  /// controller is created and no chunk is ever forwarded beyond the
  /// existing amplitude/WAV-writer fan-out.
  Future<void> startRecording({bool streamRawPcm = false}) async {
    if (state.isRecording) {
      _log.warning('startRecording ignored — already recording');
      return;
    }

    _startStopArbiter.beginStart();
    // The setup below has no bounded duration — it can be suspended for
    // arbitrarily long by main-isolate contention elsewhere (observed: an
    // STT engine warmup starving this continuation for 6+ seconds). A stop
    // can legitimately land anywhere in that window, including inside an
    // `await` that then throws. `finally` is the only exit that is
    // guaranteed to run on every one of those paths — pairing `beginStart()`
    // with scattered `endStart()` calls at each early return left the ones
    // reachable by an *unhandled* throw (e.g. `hasPermission()` itself
    // throwing) able to leak `_startInProgress = true` forever, wedging every
    // later `stopRecording()` onto the arbiter's race-detection branch.
    var startedOk = false;
    var needsAbort = false;
    String? wavPath;
    try {
      // Lazily create a recorder instance.
      _recorder ??= AudioRecorder();
      final recorder = _recorder!;

      // Check / request microphone permission.
      final hasPermission = await _micCache.hasPermission(
        recorder.hasPermission,
      );
      if (!hasPermission) {
        state = const AudioStatus(
          captureState: AudioCaptureState.error,
          errorMessage: 'mic_permission_denied',
        );
        return;
      }

      // ── Resolve selected microphone from settings ────────────────────
      final settings = ref.read(settingsProvider).value;
      final micLabel = settings?.microphone ?? 'Default';
      final retainAudio = settings?.privacy.retainRecentAudio ?? false;
      // Snapshot the gain at start — mid-recording slider changes do not
      // affect the in-flight recording. Threshold against `1.0` is exact:
      // the slider produces discrete 5 %-step values so tolerant float
      // comparison is unnecessary.
      final inputGain = settings?.audioInput.inputGain ?? 1.0;
      final useUserGain = inputGain != 1.0;

      final micPriority =
          settings?.audioInput.microphonePriority ?? const <String>[];
      final selectedDevice = await _resolveInputDevice(
        recorder,
        micLabel,
        micPriority,
      );

      final libraryAutoGain = !useUserGain;

      // The WAV goes into a private per-user folder, never the shared system
      // temp folder (predictable name, other local users can see it). The
      // folder is resolved via pure dart:io/env, not path_provider: its macOS
      // backend goes through package:objective_c FFI, which can lose a
      // symbol-resolution race when called this early in startup (see
      // cleanupStaleFiles below, the actual first-observed crash site).
      // With audio retention on, the WAV goes into the app-data folder so a
      // crash leaves it where recovery finds it.
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String captureDir;
      try {
        captureDir = retainAudio
            ? retainedAudioDir()
            : await currentCaptureDir();
      } on CaptureDirUnavailableException catch (e) {
        // Fail closed: no private folder means no recording, never /tmp.
        _log.error('Recording not started: $e', e);
        state = const AudioStatus(
          captureState: AudioCaptureState.error,
          errorMessage: 'recording_start_failed',
        );
        return;
      }
      wavPath = p.join(
        captureDir,
        captureWavFileName(timestamp, Random.secure()),
      );
      if (retainAudio) _ensureRetainedDir();

      // macOS workaround: AVAudioEngine ignores `setDeviceID()` for
      // non-default devices, so the `device:` field in RecordConfig is
      // silently dropped. Flip the system default to the chosen device for
      // the recording's lifetime; restore in stop/error paths.
      // `_originalDefaultInputUid` is also our "active override" flag.
      await _applyInputRoutingOverride(selectedDevice);

      _logRecordingStart(
        wavPath,
        selectedDevice,
        micLabel,
        inputGain,
        libraryAutoGain,
      );

      // Reset clipping bookkeeping for this recording and instantiate the
      // user-gain processor only when the slider is off the default.
      _lastRecordingClippedSamples = 0;
      _gainProcessor = useUserGain ? PcmGainProcessor(gain: inputGain) : null;

      // Live-transcript-streaming ticket: only created when opted in — see
      // [pcmChunkStream]'s doc comment for the performance guarantee.
      unawaited(_pcmChunkController?.close());
      _pcmChunkController = streamRawPcm
          ? StreamController<Uint8List>.broadcast()
          : null;

      // Prepare amplitude stream and PCM-side helpers.
      final amplitudeFromPcm = _initAmplitudeStream();

      // Open the WAV writer up-front so the file exists from t=0.
      FilePcmSink? pcmSink;
      WavFileWriter? wavWriter;
      Stream<Uint8List> pcmStream;
      try {
        pcmSink = await FilePcmSink.open(wavPath);
        wavWriter = WavFileWriter(
          sink: pcmSink,
          sampleRate: 16000,
          channels: 1,
          bitsPerSample: 16,
        );
        _wavWriter = wavWriter;
        _beginJournal(timestamp, wavPath, retainAudio);
        pcmStream = await recorder.startStream(
          _whisperConfig(device: selectedDevice, autoGain: libraryAutoGain),
        );
      } on Exception catch (e) {
        final failure = classifyRecordingStartFailure(
          e,
          inputDeviceCount: await _countInputDevices(recorder),
        );
        if (failure == RecordingStartFailure.noMicrophone) {
          _log.warning('startStream failed — no input device present: $e');
        } else {
          _log.error('startStream failed: $e', e);
        }
        // The permission or the device listing may be what failed.
        _micCache.invalidate();
        await _ampSub?.cancel();
        _ampSub = null;
        await _amplitudeFromPcm?.dispose();
        _amplitudeFromPcm = null;
        try {
          await wavWriter?.close();
        } on Exception catch (closeErr) {
          _log.error(
            'Closing partial WAV after start error failed: $closeErr',
            closeErr,
          );
        }
        _wavWriter = null;
        _gainProcessor = null;
        await _endJournal();
        await cleanupFile(wavPath);
        _amplitudeController?.close();
        _amplitudeController = null;
        await _pcmChunkController?.close();
        _pcmChunkController = null;
        state = AudioStatus(
          captureState: AudioCaptureState.error,
          errorMessage: failure.errorCode,
        );
        return;
      }

      // Fork the PCM stream into the dBFS calculator + the WAV writer. Any
      // mid-recording stream error transitions to captureState=error and
      // cleans up the partial WAV file. When the user has dialled an
      // explicit gain, the chunk passes through [PcmGainProcessor] first so
      // both downstream branches see the scaled samples.
      final gainProcessor = _gainProcessor;
      final firstSample = _firstSample = Completer<void>();
      final firstSampleDetector = FirstSampleDetector();
      _pcmSub = pcmStream.listen(
        (chunk) {
          if (firstSampleDetector.observe(chunk)) _markLiveSamples(firstSample);
          final scaled = gainProcessor == null
              ? chunk
              : gainProcessor.process(chunk);
          amplitudeFromPcm.addChunk(scaled);
          _pcmChunkController?.add(scaled);
          // Errors from the WAV writer are recoverable from the stream's
          // POV (we just stop writing more samples) but should not crash
          // the recording — they are surfaced in logs.
          wavWriter!.writeChunk(scaled).catchError((Object e) {
            _log.error('WAV writer chunk failure: $e', e);
          });
        },
        onError: (Object e) async {
          _log.error('PCM stream error: $e', e);
          await _failActiveRecording(
            errorMessage: 'pcm_stream_failed',
            deleteWav: true,
          );
        },
        onDone: () {
          _log.info('PCM stream closed');
        },
        cancelOnError: true,
      );

      startedOk = true;
    } finally {
      // Runs on every exit — normal completion, an early `return` above, or
      // an unhandled throw (e.g. `hasPermission()` itself failing) — so
      // `_startInProgress` can never leak `true` past this call. A scattered
      // per-return-site `endStart()` would miss that throw path and wedge
      // every later `stopRecording()` onto the arbiter's race branch.
      needsAbort = _startStopArbiter.endStart() && startedOk;
    }

    if (needsAbort) {
      // A stop arrived while we were still starting up — it was a no-op at
      // the time (nothing was recording yet per `state.isRecording`). Tear
      // this capture down now instead of ever reporting it as active, which
      // would otherwise leave the mic running unsupervised until some
      // later, unrelated start/stop cycle happened to absorb it.
      _log.warning(
        'stop arrived during startup — aborting just-opened capture',
      );
      await _abortJustStartedRecording(wavPath);
      return;
    }

    if (startedOk) {
      state = AudioStatus(
        captureState: AudioCaptureState.recording,
        filePath: wavPath,
      );
    }
  }

  /// Tears down a capture that just finished opening but was already
  /// unwanted — a [stopRecording] call arrived while [startRecording] was
  /// still setting up (see [RecordingStartStopArbiter]). Mirrors
  /// [_failActiveRecording]'s teardown, but always deletes the WAV (nobody
  /// asked for this recording) and resets to idle rather than error (this
  /// is not a failure — it's a stop that arrived a moment too early).
  Future<void> _abortJustStartedRecording(String wavPath) async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _amplitudeFromPcm?.dispose();
    _amplitudeFromPcm = null;
    try {
      await _wavWriter?.close();
    } on Exception catch (e) {
      _log.error('Closing WAV after start/stop race failed: $e', e);
    }
    _wavWriter = null;
    await _endJournal();
    _lastRecordingClippedSamples = 0;
    _gainProcessor = null;
    await _amplitudeController?.close();
    _amplitudeController = null;
    await _pcmChunkController?.close();
    _pcmChunkController = null;

    final recorder = _recorder;
    if (recorder != null) {
      try {
        await recorder.stop();
      } on Exception catch (e) {
        _log.error('Stopping recorder after start/stop race failed: $e', e);
      }
    }

    await cleanupFile(wavPath);
    await _restoreDefaultInputRouting();

    state = const AudioStatus();
  }

  /// Number of input devices the recorder can see, or `null` when the
  /// enumeration itself fails.
  Future<int?> _countInputDevices(AudioRecorder recorder) async {
    final devices = await lookupInputDevices(recorder.listInputDevices);
    return devices?.length;
  }

  /// Resolves the configured microphone label to an [InputDevice] by
  /// enumerating available inputs. Returns `null` when the label is
  /// `'Default'` or when the named device is not found (falls back to
  /// the system default).
  /// Picks the input device for this recording. Without a priority list, the
  /// system default ("Default") costs no enumeration, as before. With a
  /// priority list, one enumeration decides between the explicit device, the
  /// first present priority entry (virtual inputs excluded) and the system
  /// default. See [resolveMicrophoneChoice].
  void _logRecordingStart(
    String wavPath,
    InputDevice? selectedDevice,
    String micLabel,
    double inputGain,
    bool libraryAutoGain,
  ) {
    final device = selectedDevice == null
        ? 'System Default'
        : '${selectedDevice.label}, id: ${selectedDevice.id}';
    _log.info(
      'Start recording → $wavPath | Mic: $device (setting: "$micLabel")'
      ' | inputGain: $inputGain (autoGain=$libraryAutoGain)',
    );
  }

  Future<InputDevice?> _resolveInputDevice(
    AudioRecorder recorder,
    String micLabel,
    List<String> priority,
  ) async {
    if (micLabel == 'Default' && priority.isEmpty) return null;

    final devices = await _micCache.inputDevices(
      () => lookupInputDevices(recorder.listInputDevices),
    );
    if (devices == null) return null;
    _log.info(
      'Enumerated ${devices.length} input devices: '
      '[${devices.map((d) => '"${d.label}"#${d.id}').join(", ")}]',
    );
    final choice = resolveMicrophoneChoice(
      selected: micLabel,
      priority: priority,
      available: [for (final d in devices) d.label],
    );
    final label = choice.label;
    if (label == null) {
      if (micLabel != 'Default') {
        _log.warning(
          'Configured mic "$micLabel" NOT found — falling back to system default',
        );
      }
      return null;
    }
    if (choice.source == MicrophoneChoiceSource.priority) {
      _log.info('Priority pick "$label" (selected: "$micLabel")');
    }
    for (final d in devices) {
      if (d.label == label) return d;
    }
    _log.warning(
      'Configured mic "$micLabel" NOT found — falling back to system default',
    );
    return null;
  }

  /// Applies the macOS system-default-input routing override for [device] when
  /// the audio-routing service is supported and the device differs from the
  /// current default.
  ///
  /// Sets [_originalDefaultInputUid] so [_restoreDefaultInputRouting] can undo
  /// the override on stop/error. No-op when [device] is `null`, the routing
  /// service is unsupported, or the device is already the system default.
  Future<void> _applyInputRoutingOverride(InputDevice? device) async {
    _originalDefaultInputUid = null;
    if (device == null || !_audioRouting.isSupported) return;

    final originalUid = await _audioRouting.getDefaultInputDevice();
    if (originalUid == null || originalUid == device.id) return;

    final ok = await _audioRouting.setDefaultInputDevice(device.id);
    if (ok) {
      _originalDefaultInputUid = originalUid;
      _log.info('Routing override: default input $originalUid → ${device.id}');
      // Settle window: CoreAudio's `kAudioHardwarePropertyDefaultInputDevice`
      // switch returns immediately but the HAL needs a moment to bring the
      // newly-default device into a live state (esp. the built-in mic,
      // which macOS power-saves when idle). AVAudioEngine queries the
      // default at `start()` time — without this wait the engine binds to
      // a device that's still spinning up and the first 100–500 ms of
      // PCM frames come through silent (or the stream returns no frames
      // at all, which whisper.cpp rejects as "failed to read audio data").
      // Poll the default-UID until it matches what we just set, with a
      // hard cap so we never block startup forever on a flaky HAL.
      await _waitForDefaultInputSwitch(device.id);
    } else {
      _log.warning(
        'Routing override failed — recording will use system default',
      );
    }
  }

  /// Tears down any existing amplitude stream and creates a fresh
  /// [AmplitudeFromPcm] + [StreamController] pair for the new recording
  /// session. Returns the [AmplitudeFromPcm] instance so callers can feed
  /// PCM chunks to it.
  AmplitudeFromPcm _initAmplitudeStream() {
    _amplitudeController?.close();
    _amplitudeController = StreamController<double>.broadcast();

    final amplitudeFromPcm = AmplitudeFromPcm(
      pollInterval: amplitudePollInterval,
    );
    _amplitudeFromPcm = amplitudeFromPcm;

    const levelMapper = SpeechLevelMapper();
    final lossDetector = SignalLossDetector(
      samplesPerSecond: amplitudeSamplesPerSecond,
    );
    _setMicSignalLost(false);
    _ampSub?.cancel();
    _ampSub = amplitudeFromPcm.stream.listen(
      (dbFs) {
        _amplitudeController?.add(levelMapper.map(dbFs));
        final lost = lossDetector.observe(dbFs);
        if (lost != null) _setMicSignalLost(lost);
      },
      onError: (Object e) {
        _log.error('Amplitude error: $e', e);
      },
    );
    return amplitudeFromPcm;
  }

  void _setMicSignalLost(bool lost) {
    try {
      ref.read(micSignalLostProvider.notifier).set(lost);
    } on Object catch (e) {
      // Only a disposed container lands here; the recording itself is fine.
      _log.debug('Mic signal state update skipped: $e');
    }
  }

  /// Tears down active recording resources after a fatal mid-recording
  /// error and (optionally) deletes the partial WAV file. Idempotent.
  Future<void> _failActiveRecording({
    required String errorMessage,
    required bool deleteWav,
  }) async {
    final wavPath = state.filePath;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _amplitudeFromPcm?.dispose();
    _amplitudeFromPcm = null;
    try {
      await _wavWriter?.close();
    } on Exception catch (e) {
      _log.error('Closing WAV after error failed: $e', e);
    }
    _wavWriter = null;
    await _endJournal();
    _lastRecordingClippedSamples = _gainProcessor?.clippedSamples ?? 0;
    _gainProcessor = null;
    await _amplitudeController?.close();
    _amplitudeController = null;
    await _pcmChunkController?.close();
    _pcmChunkController = null;

    final recorder = _recorder;
    if (recorder != null) {
      try {
        await recorder.stop();
      } on Exception catch (e) {
        _log.error('Stopping recorder after error failed: $e', e);
      }
    }

    if (deleteWav) {
      await cleanupFile(wavPath);
    }

    await _restoreDefaultInputRouting();

    state = AudioStatus(
      captureState: AudioCaptureState.error,
      errorMessage: errorMessage,
      filePath: deleteWav ? null : wavPath,
    );
  }

  /// Stops the current recording.
  ///
  /// Returns the path to the captured WAV file, or `null` if nothing
  /// was recording.
  Future<String?> stopRecording() async {
    if (!state.isRecording) {
      if (_startStopArbiter.requestStopWhileNotRecording()) {
        _log.warning(
          'stopRecording arrived mid-startup — capture will be aborted '
          'once setup finishes',
        );
      } else {
        _log.warning('stopRecording ignored — not recording');
      }
      return null;
    }

    final wavPath = state.filePath;

    // Stop the recorder first; this closes the platform PCM stream and
    // triggers `onDone` on our subscription.
    //
    // Bounded by a timeout: the `record` package can hang in `stop()` on
    // Windows for very short recordings (the platform PCM stream's `onDone`
    // never fires). That previously stalled the orchestrator's whole 10s
    // capture budget and dropped the session into a lingering error
    // (Sentry FLUTTER_WHISPASTE-80) — making rapid push-to-talk unreliable. Our
    // own WAV is finalized below by the wav writer regardless of the platform
    // stop, so timing out here and proceeding loses nothing.
    final recorder = _recorder;
    if (recorder != null) {
      try {
        await recorder.stop().timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _log.warning(
          'recorder.stop() timed out after 3s — proceeding with captured WAV',
        );
      } on Exception catch (e) {
        _log.error('Error stopping recorder: $e', e);
      }
    }

    // Tear down the PCM subscription before closing the WAV writer so no
    // late chunks try to append after the header has been patched.
    await _pcmSub?.cancel();
    _pcmSub = null;

    try {
      await _wavWriter?.close();
    } on Exception catch (e) {
      _log.error('Error closing WAV writer: $e', e);
    }
    _wavWriter = null;
    await _endJournal();

    // Capture the user-gain clipping counter before tearing the processor
    // down. Slice #04 will read this via [lastRecordingClippedSamples].
    _lastRecordingClippedSamples = _gainProcessor?.clippedSamples ?? 0;
    _gainProcessor = null;

    await _ampSub?.cancel();
    _ampSub = null;
    final gap = _amplitudeFromPcm?.longestChunkGap;
    if (gap != null) {
      _log.info('Longest gap between PCM chunks: ${gap.inMilliseconds} ms');
    }
    await _amplitudeFromPcm?.dispose();
    _amplitudeFromPcm = null;
    await _amplitudeController?.close();
    _amplitudeController = null;
    await _pcmChunkController?.close();
    _pcmChunkController = null;

    await _restoreDefaultInputRouting();

    _log.info(
      'Recording stopped → $wavPath '
      '(clippedSamples=$_lastRecordingClippedSamples)',
    );

    state = AudioStatus(filePath: wavPath);
    return wavPath;
  }

  /// Polls `getDefaultInputDevice` until the system reports the expected UID
  /// or the [timeout] elapses. Adds a small extra settle pause so the HAL
  /// reaches a steady state before AVAudioEngine queries it.
  Future<void> _waitForDefaultInputSwitch(
    String expectedUid, {
    Duration timeout = const Duration(milliseconds: 600),
    Duration poll = const Duration(milliseconds: 40),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = await _audioRouting.getDefaultInputDevice();
      if (current == expectedUid) {
        // One extra settle tick so the HAL's input stream is fully spun up
        // before AVAudioEngine asks for the inputFormat. Empirical 150 ms is
        // enough on a MacBook Air to take the built-in mic out of power-save.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return;
      }
      await Future<void>.delayed(poll);
    }
    _log.warning(
      'Default-input switch to $expectedUid did not settle within '
      '${timeout.inMilliseconds}ms — proceeding anyway',
    );
  }

  /// Reverts the macOS system default input device to what it was before
  /// [startRecording] flipped it. No-op when no override is active (Linux,
  /// Windows, or recording without an explicit device selection).
  Future<void> _restoreDefaultInputRouting() async {
    final original = _originalDefaultInputUid;
    if (original == null) return;
    _originalDefaultInputUid = null;
    final ok = await _audioRouting.setDefaultInputDevice(original);
    _log.info('Routing restore: default input → $original (ok=$ok)');
  }

  RecordingJournal get _journal => ref.read(recordingJournalProvider);

  /// Journals the live recording so a crash leaves a trace for recovery. The
  /// write runs in the background: the microphone must not wait for the disk.
  /// Best-effort: a failed journal write must never stop the recording.
  void _beginJournal(int timestamp, String? wavPath, bool retainAudio) {
    final writer = RecordingJournalWriter(
      journal: _journal,
      onError: (Object e) => _log.warning('Recovery journal not written: $e'),
    );
    _journalWriter = writer;
    writer.beginInBackground(
      id: 'rec-$timestamp',
      startedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      wavPath: retainAudio ? wavPath : null,
    );
  }

  /// Removes the journal entry after the recording ended in any way. Waits for
  /// a still-pending begin, so the entry is never removed before it exists.
  Future<void> _endJournal() async {
    final writer = _journalWriter;
    _journalWriter = null;
    await writer?.endAndWait();
  }

  /// Creates the retained-audio folder once per process. A synchronous call on
  /// purpose: it is a single `mkdir` that runs once, and the start path must not
  /// await file IO before the microphone starts. The 0700 check runs in the
  /// background; an existing folder was already tightened at startup.
  void _ensureRetainedDir() {
    if (_retainedDirReady) return;
    final dir = retainedAudioDir();
    Directory(dir).createSync(recursive: true);
    unawaited(userAudioDirs.ensure(dir));
    _retainedDirReady = true;
  }

  /// Deletes the temporary WAV file if it exists.
  Future<void> cleanupFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        _log.debug('Cleaned up: $path');
      }
    } on FileSystemException catch (e) {
      _log.error('Cleanup failed: $e', e);
    }
  }

  /// Runs [cleanupStaleFiles] now and once more shortly after [maxAge].
  ///
  /// The first sweep skips a crash leftover younger than [maxAge] (it might
  /// belong to a concurrent instance), which then used to survive until the
  /// next launch — with "do not keep audio" that is raw audio on disk for
  /// days. The second sweep catches it. Both only delete files last modified
  /// before [launchedAt], so a WAV of this session (being recorded, or still
  /// being transcribed after [maxAge]) is never touched. The 2 s margin covers
  /// file systems with coarse modification times.
  static Timer scheduleStaleFileCleanup({
    required DateTime launchedAt,
    Duration maxAge = const Duration(minutes: 5),
    Future<void> Function({DateTime? modifiedBefore})? sweep,
    Future<void> Function({required DateTime modifiedBefore})? legacySweep,
  }) {
    final run = sweep ?? cleanupStaleFiles;
    final modifiedBefore = launchedAt.subtract(const Duration(seconds: 2));
    unawaited(run(modifiedBefore: modifiedBefore));
    // One-time cleanup of WAVs earlier versions left in the shared temp folder.
    unawaited(
      (legacySweep ?? runLegacyTempWavSweepOnce)(
        modifiedBefore: modifiedBefore,
      ),
    );
    return Timer(
      maxAge + const Duration(seconds: 30),
      () => unawaited(run(modifiedBefore: modifiedBefore)),
    );
  }

  /// Removes stale capture WAVs (`whispaste_*.wav`) from the private capture
  /// folder.
  ///
  /// Cleans up leftovers from crashes or interrupted recordings (see
  /// [scheduleStaleFileCleanup]). Only deletes files older than [maxAge]
  /// (default: 5 minutes) to avoid removing a WAV that's currently being
  /// recorded, and with [modifiedBefore] only files last modified before it.
  /// [directory] and [now] are for tests.
  static Future<void> cleanupStaleFiles({
    Duration maxAge = const Duration(minutes: 5),
    DateTime? modifiedBefore,
    Directory? directory,
    DateTime Function() now = DateTime.now,
  }) async {
    try {
      final tempDir = directory ?? Directory(await currentCaptureDir());
      final at = now();
      var cleaned = 0;
      var freedBytes = 0;

      await for (final entity in tempDir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!isCaptureWavName(name)) continue;

        try {
          final stat = await entity.stat();
          if (modifiedBefore != null &&
              !stat.modified.isBefore(modifiedBefore)) {
            continue;
          }
          if (at.difference(stat.modified) > maxAge) {
            final size = stat.size;
            await entity.delete();
            cleaned++;
            freedBytes += size;
          }
        } on FileSystemException catch (e) {
          // File may be locked by a concurrent instance — skip it.
          _log.warning('Skipping locked WAV: ${entity.path}: $e', e);
        }
      }

      if (cleaned > 0) {
        _log.info(
          'Stale WAV cleanup: removed $cleaned file(s) '
          '(${(freedBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
        );
      }
    } on Exception catch (e) {
      _log.error('Stale WAV cleanup failed: $e', e);
    }
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  void _cleanup() {
    _pcmSub?.cancel();
    _ampSub?.cancel();
    _amplitudeFromPcm?.dispose();
    _amplitudeController?.close();
    _pcmChunkController?.close();
    // Best-effort: close the writer; ignore errors during dispose.
    _wavWriter?.close().catchError((Object _) {});
    _gainProcessor = null;
    _recorder?.dispose();
    _recorder = null;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global audio capture provider.
final audioServiceProvider =
    NotifierProvider<AudioServiceNotifier, AudioStatus>(
      AudioServiceNotifier.new,
    );

/// Available audio input devices. Returns device labels for the microphone
/// dropdown in settings. The first entry is always "Default".
final audioInputDevicesProvider = FutureProvider<List<String>>((ref) async {
  try {
    final recorder = AudioRecorder();
    try {
      final devices = await lookupInputDevices(recorder.listInputDevices);
      return inputDeviceLabelsFrom(devices);
    } finally {
      recorder.dispose();
    }
  } catch (e) {
    _log.warning('Input device recorder unavailable: $e');
    return inputDeviceLabelsFrom(null);
  }
});

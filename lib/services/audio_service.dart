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
import 'audio/amplitude_from_pcm.dart';
import 'audio/capture/capture_dir.dart';
import 'audio/user_audio_dirs.dart';
import 'audio/input_device_lookup.dart';
import 'audio/linux_default_source.dart';
import 'audio/mic_start_cache.dart';
import 'audio/mic_warmup_probe.dart';
import 'audio/pcm_gain_processor.dart';
import 'audio/quiet_microphone_watch.dart';
import 'audio/recording_start_stop_arbiter.dart';
import 'audio/recovery/recording_journal.dart';
import 'audio/recovery/recording_journal_provider.dart';
import 'audio/signal_loss_detector.dart';
import 'audio/speech_level_mapper.dart';
import 'audio/wav_file_writer.dart';
import 'audio/wav_leveler.dart';
import 'audio_routing_service.dart';
import 'media_pause/media_pause_providers.dart';
import 'mic_busy_app.dart';
import 'microphone_priority.dart';
import 'path_service.dart';
import 'recording/safety_guard.dart' show GuardSample;
import 'telemetry_service.dart' show telemetrySessionAggregatorProvider;

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

  /// Linux: the capture tool (`parecord` from pulseaudio-utils, started by
  /// the `record` package) is not installed. An expected setup gap, not a
  /// defect: the user is told which package is missing (#85).
  audioToolMissing('audio_tool_missing'),

  /// Any other start failure — a genuine defect worth reporting.
  startFailed('recording_start_failed');

  const RecordingStartFailure(this.errorCode);

  /// Error key consumed by `localizeRecordingError`.
  final String errorCode;

  /// An expected user condition: logged as a warning, never escalated as a
  /// defect.
  bool get expected => this != startFailed;
}

/// Classifies a [startStream] failure. The recorder's error text is
/// localized by the OS, so the decision rests on the device enumeration
/// ([inputDeviceCount], `null` when it could not be obtained) and the error
/// type, never on the message.
RecordingStartFailure classifyRecordingStartFailure(
  Object error, {
  required int? inputDeviceCount,
}) {
  if (error is ProcessException) return RecordingStartFailure.audioToolMissing;
  if (error is PlatformException && inputDeviceCount == 0) {
    return RecordingStartFailure.noMicrophone;
  }
  return RecordingStartFailure.startFailed;
}

/// How long capture keeps running after the user releases the hotkey, so
/// audio already spoken but still in the platform pipeline reaches the WAV.
///
/// Why 250 ms: platform capture delivers PCM with a pipeline latency (macOS
/// `AVAudioEngine` tap buffers, WASAPI and PipeWire periods are in the
/// 10-200 ms range), and a stop drops what is still in flight. A user also
/// releases the hotkey a beat before the last syllable has decayed. 250 ms
/// covers both while adding a latency the user does not perceive between
/// release and text. One value for macOS, Windows and Linux: [stopRecording]
/// has no platform branch.
const Duration recordingStopTail = Duration(milliseconds: 250);

/// Waits out the stop tail. A provider so tests advance it by hand instead of
/// sleeping; the default is a real delay.
final recordingStopTailWaitProvider = Provider<Future<void> Function(Duration)>(
  (ref) =>
      (d) => Future<void>.delayed(d),
);

/// How often a running capture checks whether its PCM stream still delivers
/// (#1784). [micStallReopenAfter] without a chunk reopens it once.
const Duration micStallCheckInterval = Duration(milliseconds: 500);

/// Starts the periodic stall check of a capture. A provider so tests fire the
/// checks by hand instead of waiting; the default is [Timer.periodic].
final micStallTimerProvider =
    Provider<Timer Function(Duration, void Function(Timer))>(
      (ref) => Timer.periodic,
    );

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
/// `autoGain` stays off on every system (#1611): the `record` plugin's level
/// control never acted here (macOS only with voice processing, which
/// `echoCancel: false` keeps off; Windows ignores the option; Linux only sets
/// a stream property). The level is WhisPaste's own and the same on all
/// three systems: the automatic level of the finished WAV
/// (`wav_leveler.dart`) or the manual input volume ([PcmGainProcessor]).
RecordConfig _whisperConfig({InputDevice? device}) => RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  autoGain: false,
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

  /// Label the last start asked for (the resolved device, else the setting).
  String _lastStartLabel = 'Default';

  /// The label of the input that was silent. With the system default this is
  /// known on macOS, Windows (communications endpoint, #929), and Linux
  /// (the sound server's default source, #930); elsewhere it stays `'Default'`, and
  /// no device is suggested, because the suggestion could name the silent
  /// device itself. [devices] is the current listing, when the caller has it.
  Future<String> _silentLabel([List<InputDevice>? devices]) async {
    if (_lastStartLabel != 'Default') return _lastStartLabel;
    return await _systemDefaultInputLabel(devices) ?? _lastStartLabel;
  }

  /// Name of the current system default input, else `null`.
  Future<String?> _systemDefaultInputLabel([List<InputDevice>? devices]) async {
    if (Platform.isLinux) {
      final list =
          devices ??
          (_recorder == null
              ? null
              : await lookupInputDevices(_recorder!.listInputDevices));
      if (list == null) return null;
      return linuxDefaultInputLabel(list);
    }
    if (!_audioRouting.canReadDefaultInput) return null;
    final inputs = Platform.isWindows
        ? devices ??
              (_recorder == null
                  ? null
                  : await lookupInputDevices(_recorder!.listInputDevices))
        : await _audioRouting.listInputDevices();
    return _audioRouting.defaultInputLabel(inputs ?? const <InputDevice>[]);
  }

  /// Built-in microphone that delivered only silence (dead-mic guard, #846).
  /// The next starts avoid it and use another usable input instead.
  String? _deadBuiltInLabel;

  /// Whether the lid was closed when [_deadBuiltInLabel] went silent. Opening
  /// the lid again lifts the avoidance (the microphone works then).
  bool _deadBuiltInWasLidClosed = false;

  /// The fallback notice is shown once per dead-mic hit, not at every start.
  bool _deadFallbackAnnounced = false;

  /// Records the dead-mic guard hit of the last recording (#846). Only the
  /// built-in microphone is remembered: the next start moves to another
  /// usable input and reports it. Logs the silent device, the candidates and
  /// the lid state so a dead-mic case can be read from the log alone.
  Future<void> noteDeadMicrophone() async {
    try {
      final silent = await _silentLabel();
      final lidClosed = await _audioRouting.isLidClosed();
      final recorder = _recorder;
      final devices = recorder == null
          ? null
          : await lookupInputDevices(recorder.listInputDevices);
      final labels = [
        for (final d in devices ?? const <InputDevice>[]) d.label,
      ];
      final candidates = rankMicrophones(labels, lidClosed: lidClosed);
      _log.warning(
        'Dead mic: "$silent" delivered no signal | lid closed: $lidClosed'
        ' | candidates: [${candidates.join(", ")}]',
      );
      // Windows and Linux only name the silent device for the suggestion
      // (#929, #930); the automatic avoidance stays a macOS behaviour
      // (#846). Windows only got a device name here with #929, which made
      // the old `!Platform.isLinux` reach it by accident (#1784).
      if (Platform.isMacOS &&
          classifyMicrophone(silent) == MicrophoneKind.builtIn) {
        _deadBuiltInLabel = silent;
        _deadBuiltInWasLidClosed = lidClosed;
        _deadFallbackAnnounced = false;
      }
    } on Exception catch (e) {
      _log.warning('noteDeadMicrophone failed: $e');
    }
  }

  /// The device to offer when the last recording delivered only silence (#595):
  /// the best ranked other input ([rankMicrophones]), or `null` when there is
  /// none or the listing is unavailable. Only a suggestion; nothing is
  /// switched here, and a device the user chose is never replaced unasked.
  /// A closed lid removes the built-in microphone from the candidates (#846).
  Future<String?> suggestSilentMicrophoneSwitch() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    final devices = await lookupInputDevices(recorder.listInputDevices);
    if (devices == null) return null;
    final lidClosed = await _audioRouting.isLidClosed();
    final suggestion = suggestAlternativeMicrophone(
      silent: await _silentLabel(devices),
      available: [for (final d in devices) d.label],
      lidClosed: lidClosed,
    );
    _log.info(
      'Mic switch suggestion: ${suggestion == null ? "none" : '"$suggestion"'}'
      ' (lid closed: $lidClosed)',
    );
    return suggestion;
  }

  /// Drops the cached permission and device listing. The power service calls
  /// this after a wake: devices may have come or gone during sleep.
  void forgetMicStartCache() {
    _micCache.invalidate();
    _deadBuiltInLabel = null;
  }

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
  /// Set while [stopRecording] waits out its tail; see [abortStopTail].
  Completer<void>? _stopTailAbort;

  StreamSubscription<Uint8List>? _pcmSub;

  /// The running capture's stream bookkeeping for the one silent reopen
  /// (#1784). `null` when idle and from the moment a stop or failure begins.
  _LiveCapture? _live;

  /// Recorder state events (`record`, `pause`, `stop`), subscribed once per
  /// recorder. A `stop` nobody asked for reopens the capture (#1784).
  StreamSubscription<RecordState>? _stateSub;

  /// Subscription to [AmplitudeFromPcm.stream] — feeds the perceptual mapper.
  StreamSubscription<double>? _ampSub;

  /// Active dBFS calculator for the current recording. `null` when idle.
  AmplitudeFromPcm? _amplitudeFromPcm;

  /// Active WAV-container writer for the current recording. `null` when idle.
  WavFileWriter? _wavWriter;

  /// Id of the recovery journal entry for the live recording, if one was written.
  RecordingJournalWriter? _journalWriter;
  static bool _retainedDirReady = false;

  /// Active manual-volume processor for the current recording. `null` when
  /// idle, with the automatic level on, or at the manual identity 1.0.
  PcmGainProcessor? _gainProcessor;

  /// The current recording's WAV still awaits the automatic level (#1611).
  /// Set at start when the setting is on, cleared by the one run of
  /// [_levelFinishedWav], so the file is leveled exactly once.
  bool _levelPending = false;

  /// Samples of the most recently finished recording that were too loud: at
  /// the int16 limits in the microphone signal (automatic level) or pushed
  /// past them by the manual volume. Reset at every start; read together
  /// with [lastRecordingSampleCount] by `ClippingState`.
  int get lastRecordingClippedSamples => _lastRecordingClippedSamples;
  int _lastRecordingClippedSamples = 0;

  /// Samples the clipping count of the last recording refers to.
  int get lastRecordingSampleCount => _lastRecordingSampleCount;
  int _lastRecordingSampleCount = 0;

  /// Amplitude values normalized to 0.0–1.0, emitted ~25 times/second.
  ///
  /// Backed by a single-subscription [StreamController] that the orchestrator
  /// listens to. A new controller is created per recording session.
  StreamController<double>? _amplitudeController;

  /// Public amplitude stream. Listen after calling [startRecording].
  Stream<double>? get amplitudeStream => _amplitudeController?.stream;

  /// Per-tick raw dBFS plus meter level for the safety guard (#984), same
  /// lifecycle as [_amplitudeController]. The guard needs the raw value: the
  /// meter level clamps a quiet but working microphone to 0, which must not
  /// read as "no signal".
  StreamController<GuardSample>? _guardSampleController;

  /// Guard samples of the running recording. Listen after [startRecording].
  Stream<GuardSample>? get guardSampleStream => _guardSampleController?.stream;

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

  /// Start-up diagnostics of the current or last capture (#1777).
  MicWarmupProbe? _warmup;

  /// How the current or last capture started: reason, chunk counts, timings
  /// and the first sound's level. Logged with a dead-mic stop so the next
  /// case shows whether the device sent nothing, only zeros, or went quiet.
  /// `null` before the first capture.
  MicWarmupProbe? get micWarmup => _warmup;

  @override
  AudioStatus build() {
    ref.onDispose(_cleanup);
    // Media pause runs beside the recording, never inside the start path (#563).
    listenSelf((prev, next) {
      final media = ref.read(mediaPauseControllerProvider);
      if (next.isRecording && !(prev?.isRecording ?? false)) {
        media.recordingStarted();
      } else if (!next.isRecording && (prev?.isRecording ?? false)) {
        media.recordingEnded();
      }
    });
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
      _watchRecorderState(recorder);

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
      // Snapshot the level mode at start — mid-recording changes do not
      // affect the in-flight recording.
      final autoLevel = settings?.audioInput.autoLevel ?? true;
      final inputGain = autoLevel ? 1.0 : settings?.audioInput.inputGain ?? 1.0;

      final micPriority =
          settings?.audioInput.microphonePriority ?? const <String>[];
      final selectedDevice = await _resolveInputDevice(
        recorder,
        micLabel,
        micPriority,
      );

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
        autoLevel,
      );

      // Reset clipping bookkeeping for this recording. The manual volume
      // runs per chunk; the automatic level runs once on the finished WAV.
      _lastRecordingClippedSamples = 0;
      _lastRecordingSampleCount = 0;
      _levelPending = autoLevel;
      _gainProcessor = inputGain != 1.0
          ? PcmGainProcessor(gain: inputGain)
          : null;

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
      final config = _whisperConfig(device: selectedDevice);
      try {
        pcmSink = await FilePcmSink.open(wavPath);
        wavWriter = WavFileWriter(
          sink: pcmSink,
          sampleRate: 16000,
          channels: 1,
          bitsPerSample: 16,
        );
        _wavWriter = wavWriter;
        _beginJournal(timestamp, wavPath);
        _warmup = MicWarmupProbe();
        pcmStream = await recorder.startStream(config);
      } on Exception catch (e) {
        final failure = classifyRecordingStartFailure(
          e,
          inputDeviceCount: await _countInputDevices(recorder),
        );
        if (failure.expected) {
          _log.warning('startStream failed (${failure.errorCode}): $e');
        } else {
          _log.error('startStream failed: $e', e);
        }
        // The permission or the device listing may be what failed.
        _micCache.invalidate();
        await _stopLevelWatch();
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
        _levelPending = false;
        await _endJournal();
        await cleanupFile(wavPath);
        _amplitudeController?.close();
        _amplitudeController = null;
        _guardSampleController?.close();
        _guardSampleController = null;
        await _pcmChunkController?.close();
        _pcmChunkController = null;
        // Name the app that holds the microphone, where the platform says
        // (#139); set before the error state so the card has it at once.
        micBusyApp = failure == RecordingStartFailure.startFailed
            ? await probeMicBusyApp()
            : null;
        state = AudioStatus(
          captureState: AudioCaptureState.error,
          errorMessage: failure.errorCode,
        );
        return;
      }

      // Fork the PCM stream into the dBFS calculator + the WAV writer. Any
      // mid-recording stream error transitions to captureState=error and
      // keeps the partial WAV. The level meter and with it the silence,
      // signal-loss and quiet-microphone checks read the raw microphone
      // signal (#1611), so neither volume mode hides a dead or quiet input.
      // With a manual volume, the WAV and the live preview get the scaled
      // chunk from [PcmGainProcessor].
      final gainProcessor = _gainProcessor;
      final firstSample = _firstSample = Completer<void>();
      final warmup = _warmup ?? MicWarmupProbe();
      final live = _live = _LiveCapture(
        config: config,
        warmup: warmup,
        onChunk: (chunk) {
          if (warmup.observe(chunk)) {
            // A slow start is the one worth reading later (#1777).
            if (warmup.slowStart) _log.info(warmup.warmupLine());
            _markLiveSamples(firstSample);
          }
          final scaled = gainProcessor == null
              ? chunk
              : gainProcessor.process(chunk);
          amplitudeFromPcm.addChunk(chunk);
          _pcmChunkController?.add(scaled);
          // Errors from the WAV writer are recoverable from the stream's
          // POV (we just stop writing more samples) but should not crash
          // the recording — they are surfaced in logs.
          wavWriter!.writeChunk(scaled).catchError((Object e) {
            _log.error('WAV writer chunk failure: $e', e);
          });
        },
      );
      _listenPcm(live, pcmStream);
      live.stallTimer = ref.read(micStallTimerProvider)(
        micStallCheckInterval,
        (_) => _checkForStall(live),
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

  // -------------------------------------------------------------------------
  // Stalled stream: one silent reopen (#1784)
  // -------------------------------------------------------------------------

  /// Feeds [stream] into [live]'s chunk handler. Used for the first stream
  /// and for the reopened one, so both write into the same WAV.
  void _listenPcm(_LiveCapture live, Stream<Uint8List> stream) {
    _pcmSub = stream.listen(
      (chunk) {
        live.quietChecks = 0;
        live.onChunk(chunk);
      },
      onError: (Object e) async {
        _log.error('PCM stream error: $e', e);
        // The audio captured so far is kept: the WAV is finalised and
        // handed to the normal stop path, which transcribes it (or parks it
        // when that fails). Deleting it here lost the whole recording.
        await _failActiveRecording(
          errorMessage: 'pcm_stream_failed',
          deleteWav: false,
        );
      },
      onDone: () {
        _log.info('PCM stream closed');
      },
      cancelOnError: true,
    );
  }

  /// Subscribes once per recorder to its state events. The `record` package
  /// does not pass on the end of the platform stream, so a recorder that
  /// stops by itself (Windows after a read error, `record_readercallback.cpp`)
  /// otherwise leaves a PCM stream that never delivers again.
  void _watchRecorderState(AudioRecorder recorder) {
    _stateSub ??= recorder.onStateChanged().listen(
      _onRecorderState,
      onError: (Object e) => _log.warning('Recorder state error: $e'),
    );
  }

  void _onRecorderState(RecordState recordState) {
    final live = _live;
    if (recordState == RecordState.stop && live != null && live.expectsAudio) {
      _log.warning('Recorder stopped unexpectedly during the recording');
      unawaited(_reopenCapture(live, MicReopenTrigger.platformStop));
      return;
    }
    _log.debug('Recorder state: ${recordState.name}');
  }

  /// One periodic stall check: [micStallReopenAfter] without any chunk
  /// reopens the capture.
  void _checkForStall(_LiveCapture live) {
    if (!live.expectsAudio || live.reopenUsed) return;
    live.quietChecks++;
    // More than the timeout's worth of checks: at least the full timeout
    // passed since the last chunk, wherever it fell between two checks.
    final needed =
        micStallReopenAfter.inMilliseconds ~/
        micStallCheckInterval.inMilliseconds;
    if (live.quietChecks > needed) {
      _log.warning(
        'Mic stalled: no PCM chunk for ${micStallReopenAfter.inSeconds} s',
      );
      unawaited(_reopenCapture(live, MicReopenTrigger.stalled));
    }
  }

  /// Whether [live] still is the running capture, with no stop begun.
  bool _owns(_LiveCapture live) =>
      identical(_live, live) && !live.ended && state.isRecording;

  /// Stops the recorder and opens the stream again with the same
  /// configuration, once per recording (#1784). The WAV writer, level meter
  /// and session stay; what is already in the WAV is kept. A stop by the
  /// user wins at every step: [_endLiveCapture] marks [live] as ended, and
  /// the user's `recorder.stop()` queues behind a stream already being
  /// opened, so no microphone stays open. If the second stream delivers
  /// nothing either, the dead-mic guard ends the recording as before.
  Future<void> _reopenCapture(
    _LiveCapture live,
    MicReopenTrigger trigger,
  ) async {
    final recorder = _recorder;
    if (recorder == null || !_owns(live) || live.reopenUsed) return;
    if (trigger == MicReopenTrigger.platformStop) {
      // A `stop` event can arrive late from an earlier stop of ours; only a
      // recorder that really is not recording counts.
      final stillRecording = await recorder.isRecording().catchError(
        (Object _) => false,
      );
      if (stillRecording) {
        _log.info('Recorder stop event ignored: the recorder is recording');
        return;
      }
      if (!_owns(live) || live.reopenUsed) return;
    }
    live
      ..reopenUsed = true
      ..reopening = true;
    live.stallTimer?.cancel();
    live.warmup.noteReopen(trigger);
    _log.warning('Mic reopen: ${trigger.reason}, opening the capture again');
    // Null while the reopen was given up for a stop by the user: that is no
    // outcome worth counting.
    bool? running;
    try {
      try {
        await recorder.stop().timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _log.warning('Mic reopen: recorder.stop() timed out after 3 s');
      } on Exception catch (e) {
        _log.warning('Mic reopen: stopping the recorder failed: $e');
      }
      if (!_owns(live)) return;
      final oldSub = _pcmSub;
      _pcmSub = null;
      await oldSub?.cancel();
      if (!_owns(live)) return;
      final Stream<Uint8List> stream;
      try {
        stream = await recorder.startStream(live.config);
      } on Exception catch (e) {
        _log.warning('Mic reopen failed: $e');
        running = false;
        return;
      }
      // A stop that began meanwhile stops this stream itself.
      if (!_owns(live)) return;
      _listenPcm(live, stream);
      live.quietChecks = 0;
      running = await recorder.isRecording().catchError((Object _) => false);
      _log.warning('Mic reopened: recorder running: $running');
    } finally {
      live.reopening = false;
      final outcome = running;
      if (outcome != null) {
        live.warmup.noteReopenResult(running: outcome);
        _countTelemetry(
          action: 'mic_reopen',
          name: '${trigger.id}_${outcome ? 'running' : 'failed'}',
        );
      }
    }
  }

  /// Marks the running capture as ending: no reopen starts from here on, and
  /// a `stop` event of the recorder is expected. The PCM subscription stays
  /// with the caller, so a stop tail still reaches the WAV.
  void _endLiveCapture() {
    final live = _live;
    _live = null;
    if (live == null) return;
    live.ended = true;
    live.stallTimer?.cancel();
  }

  /// One aggregated counter in the `recording` category, like the
  /// orchestrator's (#1777): fixed ids only, no device names or content.
  void _countTelemetry({required String action, required String name}) {
    try {
      ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'recording', action: action, name: name);
    } on Object catch (e) {
      _log.debug('Telemetry count skipped: $e');
    }
  }

  /// Tears down a capture that just finished opening but was already
  /// unwanted — a [stopRecording] call arrived while [startRecording] was
  /// still setting up (see [RecordingStartStopArbiter]). Mirrors
  /// [_failActiveRecording]'s teardown, but always deletes the WAV (nobody
  /// asked for this recording) and resets to idle rather than error (this
  /// is not a failure — it's a stop that arrived a moment too early).
  Future<void> _abortJustStartedRecording(String wavPath) async {
    _endLiveCapture();
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _stopLevelWatch();
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
    _lastRecordingSampleCount = 0;
    _gainProcessor = null;
    _levelPending = false;
    await _amplitudeController?.close();
    _amplitudeController = null;
    await _guardSampleController?.close();
    _guardSampleController = null;
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
    bool autoLevel,
  ) {
    final device = selectedDevice == null
        ? 'System Default'
        : '${selectedDevice.label}, id: ${selectedDevice.id}';
    _log.info(
      'Start recording → $wavPath | Mic: $device (setting: "$micLabel")'
      ' | autoLevel: $autoLevel | inputGain: $inputGain',
    );
  }

  Future<InputDevice?> _resolveInputDevice(
    AudioRecorder recorder,
    String micLabel,
    List<String> priority,
  ) async {
    _lastStartLabel = micLabel;
    final lidClosed = await _audioRouting.isLidClosed();
    if (_deadBuiltInLabel != null && _deadBuiltInWasLidClosed && !lidClosed) {
      _log.info('Lid open again — built-in microphone is used again');
      _deadBuiltInLabel = null;
    }
    if (micLabel == 'Default' &&
        priority.isEmpty &&
        _deadBuiltInLabel == null) {
      return null;
    }

    final devices = await _micCache.inputDevices(
      () => lookupInputDevices(recorder.listInputDevices),
    );
    if (devices == null) return null;
    final labels = [for (final d in devices) d.label];
    _log.info(
      'Enumerated ${devices.length} input devices: '
      '[${devices.map((d) => '"${d.label}"#${d.id}').join(", ")}]'
      ' | lid closed: $lidClosed',
    );
    final choice = resolveMicrophoneChoice(
      selected: micLabel,
      priority: priority,
      available: labels,
      lidClosed: lidClosed,
    );
    if (choice.source == MicrophoneChoiceSource.lidClosedFallback) {
      _log.warning(
        'Lid closed — built-in mic "$micLabel" is not forced, '
        'using the system default',
      );
      return null;
    }
    var label = choice.label;
    // The built-in microphone went silent last time: move to another input
    // and say so (#846). Nothing better available means the old behaviour.
    final dead = _deadBuiltInLabel;
    if (dead != null) {
      final current = label ?? await _systemDefaultInputLabel() ?? micLabel;
      if (current == dead) {
        final alternative = suggestAlternativeMicrophone(
          silent: dead,
          available: labels,
          lidClosed: lidClosed,
        );
        if (alternative != null) {
          _log.warning(
            'Dead-mic fallback: "$dead" was silent, using "$alternative"',
          );
          if (!_deadFallbackAnnounced) {
            _deadFallbackAnnounced = true;
            ref.read(micFallbackNoticeProvider.notifier).set(alternative);
          }
          label = alternative;
        }
      }
    }
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
      if (d.label == label) {
        _lastStartLabel = label;
        return d;
      }
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
    _guardSampleController?.close();
    _guardSampleController = StreamController<GuardSample>.broadcast();

    final amplitudeFromPcm = AmplitudeFromPcm(
      pollInterval: amplitudePollInterval,
    );
    _amplitudeFromPcm = amplitudeFromPcm;

    const levelMapper = SpeechLevelMapper();
    final lossDetector = SignalLossDetector(
      samplesPerSecond: amplitudeSamplesPerSecond,
    );
    final quietWatch = QuietMicrophoneWatch();
    _setMicSignalLost(false);
    _setMicQuiet(false);
    _ampSub?.cancel();
    _ampSub = amplitudeFromPcm.stream.listen(
      (dbFs) {
        final level = levelMapper.map(dbFs);
        _amplitudeController?.add(level);
        _guardSampleController?.add(GuardSample(dbFs: dbFs, level: level));
        final lost = lossDetector.observe(dbFs);
        if (lost != null) _setMicSignalLost(lost);
        if (quietWatch.observe(amplitudeFromPcm.lastRmsDbFs, DateTime.now())) {
          _setMicQuiet(quietWatch.hinting);
        }
      },
      onError: (Object e) {
        _log.error('Amplitude error: $e', e);
      },
    );
    return amplitudeFromPcm;
  }

  /// Ends a recording's level watch: the amplitude subscription and the
  /// signal-lost and too-quiet flags it drives, so neither flag outlives its
  /// recording and the overlay never shows it after the end (PAR-026).
  Future<void> _stopLevelWatch() async {
    await _ampSub?.cancel();
    _ampSub = null;
    _setMicSignalLost(false);
    _setMicQuiet(false);
  }

  void _setMicSignalLost(bool lost) {
    try {
      ref.read(micSignalLostProvider.notifier).set(lost);
    } on Object catch (e) {
      // Only a disposed container lands here; the recording itself is fine.
      _log.debug('Mic signal state update skipped: $e');
    }
  }

  /// Too-quiet hint for the overlay. Recording keeps running either way.
  void _setMicQuiet(bool quiet) {
    try {
      ref.read(micQuietProvider.notifier).set(quiet);
    } on Object catch (e) {
      _log.debug('Mic quiet state update skipped: $e');
    }
  }

  /// Tears down active recording resources after a fatal mid-recording
  /// error and (optionally) deletes the partial WAV file. Idempotent.
  Future<void> _failActiveRecording({
    required String errorMessage,
    required bool deleteWav,
  }) async {
    final wavPath = state.filePath;
    _endLiveCapture();
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _stopLevelWatch();
    await _amplitudeFromPcm?.dispose();
    _amplitudeFromPcm = null;
    try {
      await _wavWriter?.close();
    } on Exception catch (e) {
      _log.error('Closing WAV after error failed: $e', e);
    }
    _wavWriter = null;
    _takeManualGainCounts();
    // The kept WAV goes to recognition like a normal stop: level it first,
    // while the recovery journal still covers it.
    if (deleteWav) {
      _levelPending = false;
    } else {
      await _levelFinishedWav(wavPath);
    }
    await _endJournal();
    // Publish the error state before the level stream closes below: the
    // orchestrator reacts to that close by stopping the recording.
    state = AudioStatus(
      captureState: AudioCaptureState.error,
      errorMessage: errorMessage,
      filePath: deleteWav ? null : wavPath,
    );
    await _amplitudeController?.close();
    _amplitudeController = null;
    await _guardSampleController?.close();
    _guardSampleController = null;
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
  }

  /// Completes the stop tail of a running [stopRecording] early. Returns
  /// `false` when no tail is running. The recorder still stops normally; the
  /// caller decides what happens to the captured audio.
  bool abortStopTail() {
    final abort = _stopTailAbort;
    if (abort == null || abort.isCompleted) return false;
    abort.complete();
    return true;
  }

  /// Stops the current recording.
  ///
  /// With [keepTail] (the default) capture keeps running for
  /// [recordingStopTail] before the recorder is stopped, so audio spoken
  /// before the release that is still in the platform pipeline reaches the
  /// WAV. Cancelling passes `keepTail: false`: the captured audio is thrown
  /// away anyway, so it stops at once.
  ///
  /// Returns the path to the captured WAV file, or `null` if nothing
  /// was recording.
  Future<String?> stopRecording({bool keepTail = true}) async {
    final keptAfterStreamError = state.captureState == AudioCaptureState.error
        ? state.filePath
        : null;
    if (keptAfterStreamError != null) {
      // A mid-recording stream failure already finalised the WAV and kept it
      // (see `_failActiveRecording`). Hand it over as a normal stop would.
      state = AudioStatus(filePath: keptAfterStreamError);
      return keptAfterStreamError;
    }
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
    // From here no reopen starts and the recorder's `stop` is expected; the
    // PCM subscription keeps feeding the WAV through the tail.
    _endLiveCapture();

    if (keepTail) {
      final abort = _stopTailAbort = Completer<void>();
      try {
        await Future.any<void>([
          ref.read(recordingStopTailWaitProvider)(recordingStopTail),
          abort.future,
        ]);
      } finally {
        _stopTailAbort = null;
      }
    }

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
    _takeManualGainCounts();
    // Level the finished WAV before anyone reads it: recognition, the saved
    // file and "Anhören" all get the same audio (#1611). Runs while the
    // recovery journal still covers the file.
    if (keepTail) {
      await _levelFinishedWav(wavPath);
    } else {
      // Cancelled: the audio is thrown away, leveling it costs only time.
      _levelPending = false;
    }
    await _endJournal();

    await _stopLevelWatch();
    final gap = _amplitudeFromPcm?.longestChunkGap;
    if (gap != null) {
      _log.info('Longest gap between PCM chunks: ${gap.inMilliseconds} ms');
    }
    await _amplitudeFromPcm?.dispose();
    _amplitudeFromPcm = null;
    await _amplitudeController?.close();
    _amplitudeController = null;
    await _guardSampleController?.close();
    _guardSampleController = null;
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

  /// Moves the manual-volume counters of the ending recording into the
  /// last-recording fields and drops the processor.
  void _takeManualGainCounts() {
    final processor = _gainProcessor;
    _gainProcessor = null;
    if (processor == null) return;
    _lastRecordingClippedSamples = processor.clippedSamples;
    _lastRecordingSampleCount = processor.sampleCount;
  }

  /// Runs the automatic level on the closed WAV at [wavPath] when this
  /// recording asked for it, at most once. A failure keeps the file as it was
  /// (`levelWavFile` never deletes audio) and is only logged.
  Future<void> _levelFinishedWav(String? wavPath) async {
    if (!_levelPending || wavPath == null) return;
    _levelPending = false;
    final result = await ref.read(wavLevelerProvider)(wavPath);
    _lastRecordingClippedSamples = result.fullScaleSamples;
    _lastRecordingSampleCount = result.sampleCount;
    if (result.error != null) {
      _log.warning('Automatic level skipped, WAV kept as is: ${result.error}');
    } else if (result.changed) {
      _log.info(
        'Automatic level: +${result.boostDb.toStringAsFixed(1)} dB '
        '(speech ${_formatDbFs(result.speechDbFs)})',
      );
    } else {
      _log.debug(
        'Automatic level: unchanged '
        '(speech ${_formatDbFs(result.speechDbFs)})',
      );
    }
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
  void _beginJournal(int timestamp, String wavPath) {
    final writer = RecordingJournalWriter(
      journal: _journal,
      onError: (Object e) => _log.warning('Recovery journal not written: $e'),
    );
    _journalWriter = writer;
    writer.beginInBackground(
      id: 'rec-$timestamp',
      startedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      wavPath: wavPath,
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
    RecordingJournal? journal,
    Future<void> Function({DateTime? modifiedBefore})? sweep,
    Future<void> Function({required DateTime modifiedBefore})? legacySweep,
  }) {
    final run =
        sweep ??
        ({DateTime? modifiedBefore}) =>
            cleanupStaleFiles(modifiedBefore: modifiedBefore, journal: journal);
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
    RecordingJournal? journal,
  }) async {
    try {
      final tempDir = directory ?? Directory(await currentCaptureDir());
      final at = now();
      var cleaned = 0;
      var freedBytes = 0;
      // WAVs named by a journal entry await their startup recovery.
      final journaled = journal == null
          ? const <String>{}
          : {
              for (final r in (await journal.scan()).recordings)
                if (r.wavPath != null) p.normalize(r.wavPath!),
            };

      await for (final entity in tempDir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!isCaptureWavName(name)) continue;
        if (journaled.contains(p.normalize(entity.path))) continue;

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
    _endLiveCapture();
    _stateSub?.cancel();
    _stateSub = null;
    _pcmSub?.cancel();
    _ampSub?.cancel();
    _amplitudeFromPcm?.dispose();
    _amplitudeController?.close();
    _guardSampleController?.close();
    _pcmChunkController?.close();
    // Best-effort: close the writer; ignore errors during dispose.
    _wavWriter?.close().catchError((Object _) {});
    _gainProcessor = null;
    _levelPending = false;
    _recorder?.dispose();
    _recorder = null;
  }
}

/// Stream bookkeeping of one running capture for the silent reopen (#1784).
/// Pure state, owned by [AudioServiceNotifier].
class _LiveCapture {
  _LiveCapture({
    required this.config,
    required this.warmup,
    required this.onChunk,
  });

  /// The configuration the capture was opened with; a reopen uses it again.
  final RecordConfig config;

  /// Start-up diagnostics, which also note the reopen.
  final MicWarmupProbe warmup;

  /// Writes one chunk into the capture's WAV, level meter and live preview.
  final void Function(Uint8List chunk) onChunk;

  /// Stall checks since the last chunk.
  int quietChecks = 0;

  /// The one reopen of this capture has been used.
  bool reopenUsed = false;

  /// A reopen is stopping and opening the stream right now.
  bool reopening = false;

  /// A stop or failure began; nothing may reopen the stream any more.
  bool ended = false;

  Timer? stallTimer;

  /// Whether the platform should be delivering audio right now, so a
  /// recorder `stop` or a pause in chunks is a fault.
  bool get expectsAudio => !ended && !reopening;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Levels a finished capture WAV in place (#1611). A provider so tests can
/// observe or replace the step; production uses [levelWavFile].
final wavLevelerProvider = Provider<Future<WavLevelResult> Function(String)>(
  (ref) => levelWavFile,
);

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

/// Linux: the last device listing found no `pactl` (pulseaudio-utils), so the
/// microphone row names the missing package (#85).
final inputDeviceToolMissingProvider = Provider<bool>(
  (ref) =>
      ref.watch(audioInputDevicesProvider).hasValue && inputDeviceToolMissing,
);

/// Speech level for the log line, `none` when no speech was found.
String _formatDbFs(double? dbFs) =>
    dbFs == null ? 'none' : '${dbFs.toStringAsFixed(1)} dBFS';

/// Audio capture service — wraps the `record` package for whisper-compatible
/// WAV recording (16 kHz, 16-bit, mono).
///
/// Provides start/stop recording, amplitude streaming for level metering,
/// and temp-file lifecycle management.
library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/config/settings_provider.dart';
import 'audio/amplitude_from_pcm.dart';
import 'audio/pcm_gain_processor.dart';
import 'audio/speech_level_mapper.dart';
import 'audio/wav_file_writer.dart';

// ---------------------------------------------------------------------------
// Audio service state
// ---------------------------------------------------------------------------

/// Lifecycle of the audio capture.
enum AudioCaptureState { idle, recording, error }

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
  });

  final AudioCaptureState captureState;

  /// Path to the WAV file being recorded (or just recorded).
  final String? filePath;

  final String? errorMessage;

  bool get isRecording => captureState == AudioCaptureState.recording;

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

  /// Subscription to the raw PCM stream emitted by [AudioRecorder.startStream].
  StreamSubscription<Uint8List>? _pcmSub;

  /// Subscription to [AmplitudeFromPcm.stream] — feeds the perceptual mapper.
  StreamSubscription<double>? _ampSub;

  /// Active dBFS calculator for the current recording. `null` when idle.
  AmplitudeFromPcm? _amplitudeFromPcm;

  /// Active WAV-container writer for the current recording. `null` when idle.
  WavFileWriter? _wavWriter;

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
  Future<void> startRecording() async {
    if (state.isRecording) {
      dev.log(
        'startRecording ignored — already recording',
        name: 'AudioService',
      );
      return;
    }

    // Lazily create a recorder instance.
    _recorder ??= AudioRecorder();
    final recorder = _recorder!;

    // Check / request microphone permission.
    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'mic_permission_denied',
      );
      return;
    }

    // ── Resolve selected microphone from settings ──────────────────────
    final settings = ref.read(settingsProvider).value;
    final micLabel = settings?.microphone ?? 'Default';
    // Snapshot the gain at start — mid-recording slider changes do not
    // affect the in-flight recording. Threshold against `1.0` is exact:
    // the slider produces discrete 5 %-step values so tolerant float
    // comparison is unnecessary.
    final inputGain = settings?.audioInput.inputGain ?? 1.0;
    final useUserGain = inputGain != 1.0;
    final libraryAutoGain = !useUserGain;
    InputDevice? selectedDevice;

    if (micLabel != 'Default') {
      try {
        final devices = await recorder.listInputDevices();
        for (final d in devices) {
          if (d.label == micLabel) {
            selectedDevice = d;
            break;
          }
        }
        if (selectedDevice == null) {
          dev.log(
            'Configured mic "$micLabel" not found in '
            '[${devices.map((d) => d.label).join(", ")}]. '
            'Falling back to system default.',
            name: 'AudioService',
          );
        }
      } catch (e) {
        dev.log('Failed to enumerate input devices: $e', name: 'AudioService');
      }
    }

    // Generate a temp file path for the WAV.
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final wavPath = p.join(tempDir.path, 'whispaste_$timestamp.wav');

    dev.log(
      'Start recording → $wavPath | '
      'Mic: ${selectedDevice?.label ?? "System Default"} '
      '(setting: "$micLabel"'
      '${selectedDevice != null ? ', id: ${selectedDevice.id}' : ''})'
      ' | inputGain: $inputGain (autoGain=$libraryAutoGain)',
      name: 'AudioService',
    );

    // Reset clipping bookkeeping for this recording and instantiate the
    // user-gain processor only when the slider is off the default.
    _lastRecordingClippedSamples = 0;
    _gainProcessor = useUserGain ? PcmGainProcessor(gain: inputGain) : null;

    // Prepare amplitude stream and PCM-side helpers.
    _amplitudeController?.close();
    _amplitudeController = StreamController<double>.broadcast();

    final amplitudeFromPcm = AmplitudeFromPcm(
      pollInterval: amplitudePollInterval,
    );
    _amplitudeFromPcm = amplitudeFromPcm;

    const levelMapper = SpeechLevelMapper();
    _ampSub?.cancel();
    _ampSub = amplitudeFromPcm.stream.listen(
      (dbFs) {
        _amplitudeController?.add(levelMapper.map(dbFs));
      },
      onError: (Object e) {
        dev.log('Amplitude error: $e', name: 'AudioService');
      },
    );

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
      pcmStream = await recorder.startStream(
        _whisperConfig(device: selectedDevice, autoGain: libraryAutoGain),
      );
    } on Exception catch (e) {
      dev.log('startStream failed: $e', name: 'AudioService');
      await _ampSub?.cancel();
      _ampSub = null;
      await _amplitudeFromPcm?.dispose();
      _amplitudeFromPcm = null;
      try {
        await wavWriter?.close();
      } on Exception catch (closeErr) {
        dev.log(
          'Closing partial WAV after start error failed: $closeErr',
          name: 'AudioService',
        );
      }
      _wavWriter = null;
      _gainProcessor = null;
      await cleanupFile(wavPath);
      _amplitudeController?.close();
      _amplitudeController = null;
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'recording_start_failed',
      );
      return;
    }

    // Fork the PCM stream into the dBFS calculator + the WAV writer. Any
    // mid-recording stream error transitions to captureState=error and
    // cleans up the partial WAV file. When the user has dialled an
    // explicit gain, the chunk passes through [PcmGainProcessor] first so
    // both downstream branches see the scaled samples.
    final gainProcessor = _gainProcessor;
    _pcmSub = pcmStream.listen(
      (chunk) {
        final scaled = gainProcessor == null
            ? chunk
            : gainProcessor.process(chunk);
        amplitudeFromPcm.addChunk(scaled);
        // Errors from the WAV writer are recoverable from the stream's POV
        // (we just stop writing more samples) but should not crash the
        // recording — they are surfaced in logs.
        wavWriter!.writeChunk(scaled).catchError((Object e) {
          dev.log('WAV writer chunk failure: $e', name: 'AudioService');
        });
      },
      onError: (Object e) async {
        dev.log('PCM stream error: $e', name: 'AudioService');
        await _failActiveRecording(
          errorMessage: 'pcm_stream_failed',
          deleteWav: true,
        );
      },
      onDone: () {
        dev.log('PCM stream closed', name: 'AudioService');
      },
      cancelOnError: true,
    );

    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPath,
    );
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
      dev.log('Closing WAV after error failed: $e', name: 'AudioService');
    }
    _wavWriter = null;
    _lastRecordingClippedSamples = _gainProcessor?.clippedSamples ?? 0;
    _gainProcessor = null;
    await _amplitudeController?.close();
    _amplitudeController = null;

    final recorder = _recorder;
    if (recorder != null) {
      try {
        await recorder.stop();
      } on Exception catch (e) {
        dev.log(
          'Stopping recorder after error failed: $e',
          name: 'AudioService',
        );
      }
    }

    if (deleteWav) {
      await cleanupFile(wavPath);
    }

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
      dev.log('stopRecording ignored — not recording', name: 'AudioService');
      return null;
    }

    final wavPath = state.filePath;

    // Stop the recorder first; this closes the platform PCM stream and
    // triggers `onDone` on our subscription.
    final recorder = _recorder;
    if (recorder != null) {
      try {
        await recorder.stop();
      } on Exception catch (e) {
        dev.log('Error stopping recorder: $e', name: 'AudioService');
      }
    }

    // Tear down the PCM subscription before closing the WAV writer so no
    // late chunks try to append after the header has been patched.
    await _pcmSub?.cancel();
    _pcmSub = null;

    try {
      await _wavWriter?.close();
    } on Exception catch (e) {
      dev.log('Error closing WAV writer: $e', name: 'AudioService');
    }
    _wavWriter = null;

    // Capture the user-gain clipping counter before tearing the processor
    // down. Slice #04 will read this via [lastRecordingClippedSamples].
    _lastRecordingClippedSamples = _gainProcessor?.clippedSamples ?? 0;
    _gainProcessor = null;

    await _ampSub?.cancel();
    _ampSub = null;
    await _amplitudeFromPcm?.dispose();
    _amplitudeFromPcm = null;
    await _amplitudeController?.close();
    _amplitudeController = null;

    dev.log(
      'Recording stopped → $wavPath '
      '(clippedSamples=$_lastRecordingClippedSamples)',
      name: 'AudioService',
    );

    state = AudioStatus(filePath: wavPath);
    return wavPath;
  }

  /// Deletes the temporary WAV file if it exists.
  Future<void> cleanupFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        dev.log('Cleaned up: $path', name: 'AudioService');
      }
    } on FileSystemException catch (e) {
      dev.log('Cleanup failed: $e', name: 'AudioService');
    }
  }

  /// Removes stale `whispaste_*.wav` files from the system temp directory.
  ///
  /// Called once at startup to clean up leftovers from crashes or interrupted
  /// recordings. Only deletes files older than [maxAge] (default: 5 minutes)
  /// to avoid removing a WAV that's currently being recorded.
  static Future<void> cleanupStaleFiles({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      var cleaned = 0;
      var freedBytes = 0;

      await for (final entity in tempDir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('whispaste_') || !name.endsWith('.wav')) continue;

        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > maxAge) {
            final size = stat.size;
            await entity.delete();
            cleaned++;
            freedBytes += size;
          }
        } on FileSystemException catch (e) {
          // File may be locked by a concurrent instance — skip it.
          dev.log(
            'Skipping locked WAV: ${entity.path}: $e',
            name: 'AudioService',
          );
        }
      }

      if (cleaned > 0) {
        dev.log(
          'Startup cleanup: removed $cleaned stale WAV file(s) '
          '(${(freedBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
          name: 'AudioService',
        );
      }
    } on Exception catch (e) {
      dev.log('Stale WAV cleanup failed: $e', name: 'AudioService');
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
      final devices = await recorder.listInputDevices();
      return [
        'Default',
        ...devices.where((d) => d.label.isNotEmpty).map((d) => d.label),
      ];
    } finally {
      recorder.dispose();
    }
  } catch (e) {
    dev.log('Failed to enumerate input devices: $e', name: 'AudioService');
    return ['Default'];
  }
});

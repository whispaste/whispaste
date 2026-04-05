/// Audio capture service — wraps the `record` package for whisper-compatible
/// WAV recording (16 kHz, 16-bit, mono).
///
/// Provides start/stop recording, amplitude streaming for level metering,
/// and temp-file lifecycle management.
library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// ---------------------------------------------------------------------------
// Audio service state
// ---------------------------------------------------------------------------

/// Lifecycle of the audio capture.
enum AudioCaptureState { idle, recording, error }

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
  String toString() =>
      'AudioStatus($captureState, file=$filePath)';
}

// ---------------------------------------------------------------------------
// Recorder config — whisper-compatible WAV
// ---------------------------------------------------------------------------

/// RecordConfig tuned for whisper-server: 16 kHz, mono, WAV.
const _whisperRecordConfig = RecordConfig(
  encoder: AudioEncoder.wav,
  sampleRate: 16000,
  numChannels: 1,
  autoGain: true,
  echoCancel: false,
  noiseSuppress: true,
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
  StreamSubscription<Amplitude>? _amplitudeSub;

  /// Amplitude values normalized to 0.0–1.0, emitted ~10 times/second.
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
  /// Returns immediately — audio data streams to disk.
  /// Subscribe to [amplitudeStream] for level metering.
  ///
  /// Throws [StateError] if already recording.
  Future<void> startRecording() async {
    if (state.isRecording) {
      throw StateError('Already recording');
    }

    // Lazily create a recorder instance.
    _recorder ??= AudioRecorder();
    final recorder = _recorder!;

    // Check / request microphone permission.
    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'Microphone permission denied',
      );
      return;
    }

    // Generate a temp file path for the WAV.
    final tempDir = await getTemporaryDirectory();
    final timestamp =
        DateTime.now().millisecondsSinceEpoch;
    final wavPath =
        p.join(tempDir.path, 'whispaste_$timestamp.wav');

    dev.log('Start recording → $wavPath', name: 'AudioService');

    // Prepare amplitude stream.
    _amplitudeController?.close();
    _amplitudeController = StreamController<double>.broadcast();

    // Subscribe to amplitude before starting (the stream auto-starts).
    _amplitudeSub?.cancel();
    _amplitudeSub = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen(
      (amp) {
        // Convert dBFS (negative, -∞ to 0) to linear 0.0–1.0.
        // Clamp to a useful range (-60 dB = silence floor).
        final db = amp.current;
        final linear = db <= -60.0
            ? 0.0
            : math.pow(10.0, db / 20.0).toDouble().clamp(0.0, 1.0);
        _amplitudeController?.add(linear);
      },
      onError: (Object e) {
        dev.log('Amplitude error: $e', name: 'AudioService');
      },
    );

    try {
      await recorder.start(_whisperRecordConfig, path: wavPath);
    } on Exception catch (e) {
      _amplitudeSub?.cancel();
      _amplitudeController?.close();
      state = AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'Failed to start recording: $e',
      );
      return;
    }

    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPath,
    );
  }

  /// Stops the current recording.
  ///
  /// Returns the path to the captured WAV file, or `null` if nothing
  /// was recording.
  Future<String?> stopRecording() async {
    if (!state.isRecording) {
      dev.log(
        'stopRecording ignored — not recording',
        name: 'AudioService',
      );
      return null;
    }

    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeController?.close();
    _amplitudeController = null;

    final recorder = _recorder;
    if (recorder == null) return null;

    String? path;
    try {
      path = await recorder.stop();
    } on Exception catch (e) {
      dev.log('Error stopping recorder: $e', name: 'AudioService');
    }

    final wavPath = path ?? state.filePath;
    dev.log('Recording stopped → $wavPath', name: 'AudioService');

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

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  void _cleanup() {
    _amplitudeSub?.cancel();
    _amplitudeController?.close();
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

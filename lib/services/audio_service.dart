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

import '../core/config/settings_provider.dart';

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

/// Builds a whisper-compatible [RecordConfig], optionally targeting a
/// specific [InputDevice]. Pass `null` to use the system default.
RecordConfig _whisperConfig({InputDevice? device}) => RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
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
  /// Reads the selected microphone from [settingsProvider] and resolves it
  /// to an [InputDevice]. Falls back to the system default if the configured
  /// device cannot be found.
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
        errorMessage: 'mic_permission_denied',
      );
      return;
    }

    // ── Resolve selected microphone from settings ──────────────────────
    final settings = ref.read(settingsProvider).value;
    final micLabel = settings?.microphone ?? 'Default';
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
        dev.log(
          'Failed to enumerate input devices: $e',
          name: 'AudioService',
        );
      }
    }

    // Generate a temp file path for the WAV.
    final tempDir = await getTemporaryDirectory();
    final timestamp =
        DateTime.now().millisecondsSinceEpoch;
    final wavPath =
        p.join(tempDir.path, 'whispaste_$timestamp.wav');

    dev.log(
      'Start recording → $wavPath | '
      'Mic: ${selectedDevice?.label ?? "System Default"} '
      '(setting: "$micLabel"'
      '${selectedDevice != null ? ', id: ${selectedDevice.id}' : ''})',
      name: 'AudioService',
    );

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
        if (db <= -60.0) {
          _amplitudeController?.add(0.0);
          return;
        }
        // Linear dB conversion + sqrt boost for visual presence
        // (matches Windows native SetAudioLevel boost).
        final raw = math.pow(10.0, db / 20.0).toDouble().clamp(0.0, 1.0);
        final boosted = (math.sqrt(raw) * 1.5).clamp(0.0, 1.0);
        _amplitudeController?.add(boosted);
      },
      onError: (Object e) {
        dev.log('Amplitude error: $e', name: 'AudioService');
      },
    );

    try {
      await recorder.start(
        _whisperConfig(device: selectedDevice),
        path: wavPath,
      );
    } on Exception {
      _amplitudeSub?.cancel();
      _amplitudeController?.close();
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'recording_start_failed',
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
          dev.log('Skipping locked WAV: ${entity.path}: $e',
              name: 'AudioService');
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

/// Available audio input devices. Returns device labels for the microphone
/// dropdown in settings. The first entry is always "Default".
final audioInputDevicesProvider = FutureProvider<List<String>>((ref) async {
  try {
    final recorder = AudioRecorder();
    try {
      final devices = await recorder.listInputDevices();
      return [
        'Default',
        ...devices
            .where((d) => d.label.isNotEmpty)
            .map((d) => d.label),
      ];
    } finally {
      recorder.dispose();
    }
  } catch (e) {
    dev.log('Failed to enumerate input devices: $e', name: 'AudioService');
    return ['Default'];
  }
});

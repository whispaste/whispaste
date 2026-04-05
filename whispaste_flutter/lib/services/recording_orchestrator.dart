/// Recording pipeline orchestrator — wires audio capture, STT, history,
/// and the [RecordingNotifier] state machine into a single high-level API.
///
/// External code calls [toggleRecording] — everything else is handled
/// internally, including error recovery and temp-file cleanup.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../features/history/data/database.dart';
import '../features/recording/recording_state.dart';
import 'audio_service.dart';
import 'config_service.dart';
import 'stt_service.dart';

// ---------------------------------------------------------------------------
// Orchestrator
// ---------------------------------------------------------------------------

/// Orchestrates the full dictation pipeline:
///
/// 1. Start audio capture → state = recording
/// 2. Stream amplitude → level metering
/// 3. Stop audio capture → get WAV path
/// 4. Ensure STT server running
/// 5. Transcribe WAV → text
/// 6. Save to history DB
/// 7. State = done
/// 8. Cleanup temp WAV
///
/// All transitions go through the existing [RecordingNotifier] so the UI
/// reacts automatically. Errors are caught and surfaced via the error phase.
class RecordingOrchestrator extends Notifier<void> {
  static final _log = AppLogger('RecordingOrchestrator');

  StreamSubscription<double>? _amplitudeSub;

  @override
  void build() {
    ref.onDispose(_cancelAmplitude);

    // Pre-warm the STT server in the background so the first recording
    // doesn't pay the ~10 s cold-start penalty.
    Future.microtask(() => _prewarmStt());
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Starts or stops recording based on the current phase.
  ///
  /// Idle → starts recording. Recording → stops and transcribes.
  /// Other phases are ignored.
  Future<void> toggleRecording() async {
    final recording = ref.read(recordingProvider);
    if (recording.isIdle) {
      await startRecording();
    } else if (recording.isRecording) {
      await stopRecording();
    }
  }

  /// Starts the recording pipeline.
  Future<void> startRecording() async {
    final notifier = ref.read(recordingProvider.notifier);

    try {
      // ── Preflight checks ──────────────────────────────────────────────
      final preflightError = _runPreflight();
      if (preflightError != null) {
        notifier.fail(preflightError);
        return;
      }

      // Transition state: idle → recording.
      notifier.startRecording();

      // Start audio capture.
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      await audioNotifier.startRecording();

      // Verify recording actually started.
      final audioStatus = ref.read(audioServiceProvider);
      if (audioStatus.captureState == AudioCaptureState.error) {
        notifier.fail(
          audioStatus.errorMessage ?? 'recording_failed',
        );
        return;
      }

      // Subscribe to amplitude for level metering.
      _cancelAmplitude();
      _amplitudeSub = audioNotifier.amplitudeStream?.listen(
        (level) => notifier.updateAudioLevel(level),
        onError: (Object e) {
          _log.warning('Amplitude stream error: $e');
        },
      );

      _log.info('Recording started');
    } on Exception catch (e) {
      ref.read(recordingProvider.notifier).fail('$e');
    }
  }

  /// Stops recording and runs the transcription pipeline.
  Future<void> stopRecording() async {
    final notifier = ref.read(recordingProvider.notifier);
    String? wavPath;

    try {
      // Cancel amplitude subscription.
      _cancelAmplitude();

      // Stop audio capture.
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      wavPath = await audioNotifier.stopRecording();

      if (wavPath == null) {
        notifier.fail('no_audio_recorded');
        return;
      }

      // Transition state: recording → transcribing.
      notifier.stopRecording();

      // On Windows the `record` package can return before the WAV is fully
      // flushed to disk.  Wait up to 2 s for the file to appear.
      final wavFile = File(wavPath);
      if (!wavFile.existsSync()) {
        _log.debug('WAV not yet on disk, waiting for flush…');
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (wavFile.existsSync()) break;
        }
      }
      if (!wavFile.existsSync()) {
        notifier.fail('wav_file_not_created');
        _log.error('WAV file never appeared: $wavPath');
        return;
      }

      // Read bytes now while the file is guaranteed to exist — avoids a
      // second race during the ensureRunning() await.
      final wavBytes = await wavFile.readAsBytes();
      if (wavBytes.isEmpty) {
        notifier.fail('wav_file_empty');
        _log.error('WAV file is empty: $wavPath');
        return;
      }
      _log.debug('WAV ready: ${wavBytes.length} bytes');

      // Read config for language hint.
      final config = ref.read(effectiveConfigProvider);
      final language = config.transcriptionLanguage;

      // Ensure STT server is ready.
      final sttNotifier = ref.read(sttServiceProvider.notifier);
      await sttNotifier.ensureRunning();

      // Verify server is ready before transcribing.
      final sttStatus = ref.read(sttServiceProvider);
      if (!sttStatus.isReady) {
        notifier.fail(
          sttStatus.errorMessage ?? 'stt_server_failed',
        );
        return;
      }

      // Transcribe using pre-loaded bytes (avoids file-system race).
      _log.info('Transcribing $wavPath (${wavBytes.length} bytes)');
      final transcript = await sttNotifier.transcribeBytes(
        wavBytes,
        language: language != 'auto' ? language : null,
      );

      if (transcript.isEmpty) {
        notifier.fail('transcription_empty');
        return;
      }

      // Save to history database.
      await _saveToHistory(transcript, config);

      // Transition state: transcribing → done.
      notifier.completeTranscription(transcript);
      _log.info('Pipeline complete: ${transcript.length} chars');
    } on Exception catch (e) {
      notifier.fail('$e');
      _log.error('Pipeline error: $e');
    } finally {
      // Always clean up the temp WAV file.
      if (wavPath != null) {
        await ref
            .read(audioServiceProvider.notifier)
            .cleanupFile(wavPath);
      }
    }
  }

  /// Resets the recording state to idle.
  void reset() {
    _cancelAmplitude();
    ref.read(recordingProvider.notifier).reset();
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  /// Validates STT prerequisites before starting a recording.
  ///
  /// Returns an error code string if something is missing,
  /// or `null` when everything is ready. Error codes are mapped
  /// to localized messages in the UI layer.
  String? _runPreflight() {
    final config = ref.read(effectiveConfigProvider);

    // Ensure STT directory exists.
    final dir = Directory(sttDir());
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } on FileSystemException catch (e) {
        _log.warning('Failed to create STT dir: $e');
      }
    }

    // Check whisper-server binary.
    final serverPath = whisperServerPath();
    if (!File(serverPath).existsSync()) {
      _log.warning('Preflight FAIL: whisper-server not found at $serverPath');
      return 'stt_server_not_found';
    }

    // Check model file.
    final modelId = config.localModelId;
    final modelPath = sttModelPath(modelId);
    if (modelPath == null) {
      return 'stt_model_unknown';
    }
    if (!File(modelPath).existsSync()) {
      _log.warning('Preflight FAIL: model "$modelId" not found at $modelPath');
      return 'stt_model_not_found';
    }

    _log.info('Preflight OK: server=$serverPath model=$modelPath');
    return null;
  }

  Future<void> _saveToHistory(
    String transcript,
    WhisPasteConfig config,
  ) async {
    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    final recording = ref.read(recordingProvider);

    final id = '${now.millisecondsSinceEpoch}';

    // Auto-generate a short title from the first ~60 chars.
    var title = transcript.trim();
    if (title.length > 60) {
      // Cut at the last word boundary within 60 chars.
      final cut = title.substring(0, 60);
      final lastSpace = cut.lastIndexOf(' ');
      title = lastSpace > 20 ? '${cut.substring(0, lastSpace)}…' : '$cut…';
    }

    await db.upsertEntry(HistoryEntriesCompanion(
      id: Value(id),
      content: Value(transcript),
      title: Value(title),
      timestamp: Value(now),
      durationSec: Value(recording.elapsed.inSeconds.toDouble()),
      language: Value(config.transcriptionLanguage),
      model: Value(config.localModelId),
      isLocal: const Value(true),
      source: const Value('dictation'),
    ));

    _log.info('Saved entry $id to history');
  }

  void _cancelAmplitude() {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  /// Best-effort pre-warm: starts the STT server so the first dictation is
  /// instant. Runs in the background — failures are silently logged.
  Future<void> _prewarmStt() async {
    final config = ref.read(effectiveConfigProvider);
    if (!config.useLocalStt) return;

    // Only pre-warm when runtime + model are already downloaded.
    final serverPath = whisperServerPath();
    final modelPath = sttModelPath(config.localModelId);
    if (!File(serverPath).existsSync()) return;
    if (modelPath == null || !File(modelPath).existsSync()) return;

    await ref.read(sttServiceProvider.notifier).prewarm();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global recording orchestrator provider.
///
/// The orchestrator is a `void` notifier — it has no state of its own.
/// All observable state lives in [recordingProvider], [audioServiceProvider],
/// and [sttServiceProvider].
final recordingOrchestratorProvider =
    NotifierProvider<RecordingOrchestrator, void>(
  RecordingOrchestrator.new,
);

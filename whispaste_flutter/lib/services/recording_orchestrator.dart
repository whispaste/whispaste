/// Recording pipeline orchestrator — wires audio capture, STT, history,
/// and the [RecordingNotifier] state machine into a single high-level API.
///
/// External code calls [toggleRecording] — everything else is handled
/// internally, including error recovery and temp-file cleanup.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../features/history/data/database.dart';
import '../core/recording/recording_state.dart';
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

  // ── Audio Safety Guard state ──────────────────────────────────────────────
  /// Amplitude threshold below which we consider the signal "silent".
  /// Matches the Go implementation: peak < 0.02 ≈ silent.
  static const _silenceThreshold = 0.02;

  /// Whether speech has been detected at least once during this recording.
  bool _speechDetected = false;

  /// Consecutive silent samples since last speech (each ~100 ms).
  int _silentSamples = 0;

  /// Whether the guard already triggered (prevents double-fire).
  bool _guardFired = false;

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

      // Subscribe to amplitude for level metering + safety guard.
      _cancelAmplitude();
      _resetGuardState();
      _amplitudeSub = audioNotifier.amplitudeStream?.listen(
        (level) {
          notifier.updateAudioLevel(level);
          _evaluateGuard(level);
        },
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

      // When language is empty or "auto", fall back to the app's UI locale
      // so local whisper models don't guess wrong (mirrors Go's
      // GetEffectiveLocalTranscriptionLanguage which uses UILanguage).
      final appLocale = ref.read(settingsProvider).value?.locale;
      String? effectiveLang;
      if (language.isNotEmpty && language != 'auto') {
        effectiveLang = language;
      } else if (appLocale != null && appLocale.isNotEmpty) {
        effectiveLang = appLocale; // e.g. "de", "en"
      }

      // Ensure STT server is ready (with timeout to prevent indefinite hang).
      final sttNotifier = ref.read(sttServiceProvider.notifier);
      try {
        await sttNotifier.ensureRunning().timeout(
              const Duration(seconds: 30),
            );
      } on TimeoutException {
        notifier.fail('stt_start_timeout');
        _log.warning('STT server start timed out after 30s');
        return;
      }

      // Verify server is ready before transcribing.
      final sttStatus = ref.read(sttServiceProvider);
      if (!sttStatus.isReady) {
        notifier.fail(
          sttStatus.errorMessage ?? 'stt_server_failed',
        );
        return;
      }

      // Transcribe using pre-loaded bytes (avoids file-system race).
      // Calculate audio duration for RTF logging (16 kHz, mono, 16-bit + 44-byte header).
      final audioDurMs = ((wavBytes.length - 44) / 32000 * 1000).round();
      _log.info(
        'Transcribing $wavPath (${wavBytes.length} bytes, ~${audioDurMs}ms audio, lang=$effectiveLang)',
      );

      final inferSw = Stopwatch()..start();
      final transcript = await sttNotifier.transcribeBytes(
        wavBytes,
        language: effectiveLang,
      );
      inferSw.stop();

      if (audioDurMs > 0) {
        final rtf = inferSw.elapsedMilliseconds / audioDurMs;
        _log.info(
          'STT timing: inference=${inferSw.elapsedMilliseconds}ms '
          'audio=${audioDurMs}ms RTF=${rtf.toStringAsFixed(2)}x',
        );
      }

      if (transcript.isEmpty) {
        notifier.fail('transcription_empty');
        return;
      }

      // Save to history database.
      await _saveToHistory(transcript, config);

      // ── Post-processing (LLM) ──────────────────────────────────────────
      final settings =
          ref.read(settingsProvider).value ?? AppSettings.defaults;
      final finalText = transcript;

      if (settings.postProcessEnabled) {
        notifier.startProcessing();
        _log.info('Post-processing enabled — skipping (not yet implemented)');

        // TODO: Wire actual LLM post-processing via Go FFI or cloud API.
      }

      // Copy to clipboard / auto-paste based on user preference.
      // Timeout prevents a locked clipboard from hanging the pipeline.
      try {
        await _handleAfterTranscription(finalText, config).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _log.warning('After-transcription action timed out (10s)');
          },
        );
      } on Exception catch (e) {
        _log.warning('After-transcription action failed (non-fatal): $e');
      }

      // Transition state: transcribing/processing → done.
      notifier.completeTranscription(finalText);
      _log.info('Pipeline complete: ${finalText.length} chars');
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
    final durationSec = recording.elapsed.inSeconds.toDouble();

    // Auto-generate a short title from the first ~60 chars.
    var title = transcript.trim();
    if (title.length > 60) {
      // Cut at the last word boundary within 60 chars.
      final cut = title.substring(0, 60);
      final lastSpace = cut.lastIndexOf(' ');
      title = lastSpace > 20 ? '${cut.substring(0, lastSpace)}…' : '$cut…';
    }

    final wordCount = transcript.trim().isEmpty
        ? 0
        : transcript.trim().split(RegExp(r'\s+')).length;

    await db.upsertEntry(HistoryEntriesCompanion(
      id: Value(id),
      content: Value(transcript),
      title: Value(title),
      timestamp: Value(now),
      durationSec: Value(durationSec),
      language: Value(config.transcriptionLanguage),
      model: Value(config.localModelId),
      isLocal: const Value(true),
      source: const Value('dictation'),
    ));

    // Persist analytics independently from history — these counters survive
    // history entry deletion.
    await db.recordDailyStat(
      timestamp: now,
      model: config.localModelId,
      isLocal: true,
      durationSec: durationSec,
      processingDurationSec: 0,
      wordCount: wordCount,
      costUsd: 0,
    );

    _log.info('Saved entry $id to history');
  }

  void _cancelAmplitude() {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  // ── Audio Safety Guard ────────────────────────────────────────────────────

  void _resetGuardState() {
    _speechDetected = false;
    _silentSamples = 0;
    _guardFired = false;
  }

  /// Called for every amplitude sample (~100 ms). Implements:
  /// 1. Dead-mic detection: no audio at all for [deadMicTimeout] → error.
  /// 2. Auto-stop on silence: speech detected then silence for
  ///    [autoStopSilence] → auto-transcribe.
  void _evaluateGuard(double level) {
    if (_guardFired) return;
    final recording = ref.read(recordingProvider);
    if (!recording.isRecording) return;

    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;

    final isSilent = level < _silenceThreshold;

    if (!isSilent) {
      _speechDetected = true;
      _silentSamples = 0;
      return;
    }

    // Silent sample — increment counter.
    _silentSamples++;

    // Amplitude stream fires every ~100 ms → 10 samples ≈ 1 second.
    const samplesPerSecond = 10;

    // ── Dead-mic detection ───────────────────────────────────────────────
    if (!_speechDetected && settings.deadMicTimeout > 0) {
      final threshold =
          (settings.deadMicTimeout * samplesPerSecond).round();
      if (_silentSamples >= threshold) {
        _guardFired = true;
        _log.warning(
            'Dead-mic guard triggered after ${settings.deadMicTimeout}s');
        // Auto-stop with error — runs asynchronously.
        _handleDeadMic();
        return;
      }
    }

    // ── Auto-stop on silence (only after speech detected) ────────────────
    if (_speechDetected && settings.autoStopSilence > 0) {
      final threshold =
          (settings.autoStopSilence * samplesPerSecond).round();
      if (_silentSamples >= threshold) {
        _guardFired = true;
        _log.info(
            'Auto-stop triggered after ${settings.autoStopSilence}s silence');
        // Auto-stop and transcribe — runs asynchronously.
        _handleAutoStop();
        return;
      }
    }
  }

  /// Dead-mic triggered: stop recording and surface error.
  Future<void> _handleDeadMic() async {
    try {
      _cancelAmplitude();
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      await audioNotifier.stopRecording();
      ref.read(recordingProvider.notifier).fail('recording_guard_failed');
    } on Exception catch (e) {
      _log.warning('Error during dead-mic cleanup: $e');
      ref.read(recordingProvider.notifier).fail('recording_guard_failed');
    }
  }

  /// Auto-stop triggered: stop recording and run transcription pipeline.
  Future<void> _handleAutoStop() async {
    try {
      await stopRecording();
    } on Exception catch (e) {
      _log.warning('Error during auto-stop: $e');
      ref.read(recordingProvider.notifier).fail('$e');
    }
  }

  /// Best-effort pre-warm: starts the STT server so the first dictation is
  /// instant. Runs in the background — failures are silently logged.
  Future<void> _prewarmStt() async {
    try {
      final config = ref.read(effectiveConfigProvider);
      if (!config.useLocalStt) return;

      // Only pre-warm when runtime + model are already downloaded.
      final serverPath = whisperServerPath();
      final modelPath = sttModelPath(config.localModelId);
      if (!File(serverPath).existsSync()) return;
      if (modelPath == null || !File(modelPath).existsSync()) return;

      await ref.read(sttServiceProvider.notifier).prewarm();
    } on Exception catch (e) {
      _log.warning('STT pre-warm failed (non-fatal): $e');
    }
  }

  /// Copies transcript to clipboard and/or simulates paste depending on the
  /// user's "after transcription" setting.
  Future<void> _handleAfterTranscription(
    String transcript,
    WhisPasteConfig config,
  ) async {
    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    final action = settings.afterTranscriptionAction;

    if (action == AfterTranscriptionAction.nothing) return;

    // clipboard, paste, and clipboardAndPaste all start by copying.
    try {
      await Clipboard.setData(ClipboardData(text: transcript)).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _log.warning('Clipboard.setData timed out after 5s');
        },
      );
      _log.info('Transcript copied to clipboard (${transcript.length} chars)');
    } on Exception catch (e) {
      _log.warning('Clipboard copy failed: $e');
    }

    // TODO: 'paste' mode — simulate Ctrl+V via platform channel / Go FFI.
    // Requires Windows SendInput bridge (paste.go). Will be wired in a
    // follow-up when the Go FFI paste export is added.
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

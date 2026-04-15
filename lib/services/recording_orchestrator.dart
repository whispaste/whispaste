/// Recording pipeline orchestrator — wires audio capture, STT, history,
/// and the [RecordingNotifier] state machine into a single high-level API.
///
/// External code calls [toggleRecording] — everything else is handled
/// internally, including error recovery and temp-file cleanup.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_state.dart';
import '../core/data/analytics_provider.dart';
import 'audio_service.dart';
import 'desktop_paste/desktop_paste_controller.dart';
import 'model_download_service.dart';
import 'path_service.dart';
import 'sound_feedback_service.dart';
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
  static const _maxOomRecoveryAttempts = 3;

  StreamSubscription<double>? _amplitudeSub;

  /// Prevents concurrent `startRecording()` calls from racing through
  /// the async preflight.
  bool _startInFlight = false;

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

  /// Whether the 90% duration warning has been played.
  bool _durationWarningFired = false;

  /// Whether the current recording session has a captured desktop paste target.
  bool _hasCapturedPasteTarget = false;

  int _oomAttemptCount = 0;

  int get oomAttemptCount => _oomAttemptCount;

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
      // Kick off server warm-up before preflight to maximise parallel window.
      unawaited(_prewarmStt());
      await startRecording();
    } else if (recording.isRecording) {
      await stopRecording();
    }
  }

  /// Starts the recording pipeline.
  Future<void> startRecording() async {
    // Concurrency guard: prevent double-start from hotkey spam or rapid taps.
    if (_startInFlight) {
      _log.debug('startRecording ignored — already in flight');
      return;
    }
    _startInFlight = true;

    final notifier = ref.read(recordingProvider.notifier);

    try {
      // ── Preflight checks ──────────────────────────────────────────────
      final preflightError = await _runPreflight();

      // Re-check phase after async gap — another caller may have started.
      if (ref.read(recordingProvider).phase != RecordingPhase.idle) {
        _log.debug('startRecording aborted — phase changed during preflight');
        return;
      }

      if (preflightError != null) {
        // Try soft handling first (auto-download, info toast).
        if (_handleSoftPreflight(preflightError)) return;
        // Hard failure — transition to error state.
        notifier.fail(preflightError);
        return;
      }

      // Transition state: idle → recording (generates sessionId).
      notifier.startRecording();
      final sid = ref.read(recordingProvider).sessionId ?? '?';
      _log.info('[$sid] Recording started');

      // Notify STT service that a recording is active (pauses idle timer).
      final sttNot = ref.read(sttServiceProvider.notifier);
      sttNot.notifyRecordingStarted();

      // Kick off STT server in parallel — files already confirmed by preflight.
      // Fires before the two async calls below to maximise warm-up lead time.
      unawaited(sttNot.ensureRunning());

      _hasCapturedPasteTarget = await _capturePasteTarget();

      // Start audio capture.
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      await audioNotifier.startRecording();

      // Verify recording actually started.
      final audioStatus = ref.read(audioServiceProvider);
      if (audioStatus.captureState == AudioCaptureState.error) {
        sttNot.notifyRecordingStopped();
        notifier.fail(audioStatus.errorMessage ?? 'recording_failed');
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
          _log.warning('[$sid] Amplitude stream error: $e');
        },
      );
    } on Exception catch (e) {
      ref.read(sttServiceProvider.notifier).notifyRecordingStopped();
      ref.read(recordingProvider.notifier).fail('$e');
    } finally {
      _startInFlight = false;
    }
  }

  /// Stops recording and runs the transcription pipeline.
  ///
  /// Each major step has its own timeout so a single hung operation cannot
  /// freeze the app.  A 90 s pipeline watchdog acts as a final safety net.
  ///
  /// Pipeline timing is logged at completion (or failure) for diagnostics.
  Future<void> stopRecording() async {
    final notifier = ref.read(recordingProvider.notifier);
    final sid = ref.read(recordingProvider).sessionId ?? '?';
    String? wavPath;

    // ── Pipeline timing ──────────────────────────────────────────────────
    final pipelineSw = Stopwatch()..start();
    int? wavReadyMs;
    int? sttEnsureMs;
    int? transcribeMs;
    int? replaceMs;
    int? saveMs;
    int? clipboardMs;
    String pipelineOutcome = 'unknown';

    // ── Pipeline watchdog ─────────────────────────────────────────────────
    // Force-fail if the entire stop→done pipeline exceeds 90 s.
    final watchdog = Timer(const Duration(seconds: 90), () {
      _log.error(
        '[$sid] Pipeline watchdog triggered after 90s — force-resetting',
      );
      notifier.fail('pipeline_timeout');
    });

    try {
      // Cancel amplitude subscription.
      _cancelAmplitude();

      // Stop audio capture.
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      wavPath = await audioNotifier.stopRecording();

      if (wavPath == null) {
        pipelineOutcome = 'no_audio';
        notifier.fail('no_audio_recorded');
        return;
      }

      // Transition state: recording → transcribing.
      notifier.stopRecording();

      // On Windows the `record` package can return before the WAV is fully
      // flushed to disk.  Wait up to 2 s for the file to appear.
      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        _log.debug('[$sid] WAV not yet on disk, waiting for flush…');
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (await wavFile.exists()) break;
        }
      }
      if (!await wavFile.exists()) {
        pipelineOutcome = 'wav_not_created';
        notifier.fail('wav_file_not_created');
        _log.error('[$sid] WAV file never appeared: $wavPath');
        return;
      }

      // Read bytes now while the file is guaranteed to exist — avoids a
      // second race during the ensureRunning() await.
      final wavBytes = await wavFile.readAsBytes();
      if (wavBytes.isEmpty) {
        pipelineOutcome = 'wav_empty';
        notifier.fail('wav_file_empty');
        _log.error('[$sid] WAV file is empty: $wavPath');
        return;
      }
      wavReadyMs = pipelineSw.elapsedMilliseconds;
      _log.debug(
        '[$sid] WAV ready: ${wavBytes.length} bytes (${wavReadyMs}ms)',
      );

      // Read settings for language hint and model info.
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      final language = settings.sttLanguageCode;

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

      // Ensure STT server is ready (with generous timeout for cold-starts —
      // large models on integrated GPUs can take 60–90s to load into VRAM).
      final sttNotifier = ref.read(sttServiceProvider.notifier);
      final ensureSw = Stopwatch()..start();
      try {
        await sttNotifier.ensureRunning().timeout(const Duration(seconds: 120));
      } on TimeoutException {
        pipelineOutcome = 'stt_timeout';
        notifier.fail('stt_start_timeout');
        _log.warning('[$sid] STT server start timed out after 120s');
        return;
      }
      ensureSw.stop();
      sttEnsureMs = ensureSw.elapsedMilliseconds;

      // Verify server is ready before transcribing.
      final sttStatus = ref.read(sttServiceProvider);
      if (!sttStatus.isReady) {
        if (sttStatus.errorMessage == 'stt_cuda_oom') {
          pipelineOutcome = 'stt_cuda_oom';
          _handleOomRecovery();
          return;
        }
        pipelineOutcome = 'stt_failed';
        notifier.fail(sttStatus.errorMessage ?? 'stt_server_failed');
        return;
      }

      // Transcribe using pre-loaded bytes (avoids file-system race).
      // Calculate audio duration for RTF logging (16 kHz, mono, 16-bit + 44-byte header).
      final audioDurMs = ((wavBytes.length - 44) / 32000 * 1000).round();
      _log.info(
        '[$sid] Transcribing (${wavBytes.length} bytes, '
        '~${audioDurMs}ms audio, lang=$effectiveLang)',
      );

      final inferSw = Stopwatch()..start();
      // Timeout scales with audio length: 60s base + 0.8× audio duration.
      // A 10s clip gets 68s, a 120s clip gets 156s — enough headroom for
      // large-v3-turbo even on slower hardware.
      final timeoutSec = 60 + (audioDurMs / 1000 * 0.8).round();
      String transcript;
      try {
        transcript = await sttNotifier
            .transcribeBytes(wavBytes, language: effectiveLang)
            .timeout(Duration(seconds: timeoutSec));
      } on TimeoutException {
        pipelineOutcome = 'transcribe_timeout';
        notifier.fail('transcription_timeout');
        _log.error('[$sid] Transcription timed out after ${timeoutSec}s');
        return;
      } on SocketException catch (_) {
        final sttError = ref.read(sttServiceProvider).errorMessage;
        if (sttError == 'stt_cuda_oom') {
          pipelineOutcome = 'stt_cuda_oom';
          _handleOomRecovery();
          return;
        }
        pipelineOutcome = 'stt_connection_lost';
        notifier.fail('stt_server_connection_lost');
        _log.error('[$sid] STT server connection lost during inference');
        return;
      } on http.ClientException catch (_) {
        final sttError = ref.read(sttServiceProvider).errorMessage;
        if (sttError == 'stt_cuda_oom') {
          pipelineOutcome = 'stt_cuda_oom';
          _handleOomRecovery();
          return;
        }
        pipelineOutcome = 'stt_connection_lost';
        notifier.fail('stt_server_connection_lost');
        _log.error(
          '[$sid] STT server connection lost during inference (ClientException)',
        );
        return;
      }
      inferSw.stop();
      transcribeMs = inferSw.elapsedMilliseconds;

      if (audioDurMs > 0) {
        final rtf = transcribeMs / audioDurMs;
        _log.info(
          '[$sid] STT: inference=${transcribeMs}ms '
          'audio=${audioDurMs}ms RTF=${rtf.toStringAsFixed(2)}x',
        );
      }

      if (transcript.isEmpty) {
        pipelineOutcome = 'empty_transcript';
        notifier.fail('transcription_empty');
        return;
      }

      // ── Text replacements (voice shortcuts) ─────────────────────────────
      final replaceSw = Stopwatch()..start();
      var finalText = transcript;
      if (settings.textReplacementsEnabled) {
        try {
          final db = ref.read(historyDatabaseProvider);
          final replacements = await db.readAllReplacements();
          if (replacements.isNotEmpty) {
            for (final r in replacements) {
              // Case-insensitive whole-word replacement.
              final escaped = RegExp.escape(r.trigger);
              final pattern = RegExp(
                r'(?<=\s|^)' + escaped + r'(?=\s|$|[.,;:!?])',
                caseSensitive: false,
              );
              finalText = finalText.replaceAll(pattern, r.replacement);
            }
            if (finalText != transcript) {
              _log.info(
                '[$sid] Text replacements applied: ${replacements.length} rules, '
                '${transcript.length}→${finalText.length} chars',
              );
            }
          }
        } on Exception catch (e) {
          _log.warning('[$sid] Text replacement failed (non-fatal): $e');
        }
      }
      replaceSw.stop();
      replaceMs = replaceSw.elapsedMilliseconds;

      // ── Transcription cleanup (always applied) ──────────────────────────
      // Whisper models often insert extraneous newlines. Collapse them into
      // single spaces for clean copy/paste results.
      final rawLen = finalText.length;
      finalText = finalText
          .replaceAll(RegExp(r'\r\n|\r'), '\n')
          .replaceAll(RegExp(r'\n+'), ' ')
          .replaceAll(RegExp(r' {2,}'), ' ')
          .trim();
      if (finalText.length != rawLen) {
        _log.info(
          '[$sid] Whitespace cleanup: $rawLen→${finalText.length} chars',
        );
      }

      // Save to history database (with replacements applied).
      final saveSw = Stopwatch()..start();
      await _saveToHistory(finalText, settings);
      saveSw.stop();
      saveMs = saveSw.elapsedMilliseconds;

      // Copy to clipboard / auto-paste based on user preference.
      // Timeout prevents a locked clipboard from hanging the pipeline.
      final clipSw = Stopwatch()..start();
      try {
        await _handleAfterTranscription(finalText, settings).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _log.warning('[$sid] After-transcription action timed out (10s)');
          },
        );
      } on Exception catch (e) {
        _log.warning(
          '[$sid] After-transcription action failed (non-fatal): $e',
        );
      }
      clipSw.stop();
      clipboardMs = clipSw.elapsedMilliseconds;

      // Transition state: transcribing/processing → done.
      notifier.completeTranscription(finalText);
      ref.read(sttServiceProvider.notifier).notifyTranscriptionCompleted();
      _oomAttemptCount = 0;
      pipelineOutcome = 'ok';
    } on Exception catch (e) {
      pipelineOutcome = 'exception';
      if ('$e'.contains('stt_cuda_oom')) {
        pipelineOutcome = 'stt_cuda_oom';
        _handleOomRecovery();
        return;
      }
      notifier.fail('$e');
      ref.read(sttServiceProvider.notifier).notifyRecordingStopped();
      _log.error('[$sid] Pipeline error: $e');
    } finally {
      watchdog.cancel();
      pipelineSw.stop();

      // Log structured pipeline summary (success AND failure).
      _log.info(
        '[$sid] Pipeline[$pipelineOutcome]: '
        'total=${pipelineSw.elapsedMilliseconds}ms '
        'wav=${wavReadyMs ?? "-"}ms '
        'stt_ensure=${sttEnsureMs ?? "-"}ms '
        'transcribe=${transcribeMs ?? "-"}ms '
        'replace=${replaceMs ?? "-"}ms '
        'save=${saveMs ?? "-"}ms '
        'clipboard=${clipboardMs ?? "-"}ms',
      );

      // Always clean up the temp WAV file.
      if (wavPath != null) {
        await ref.read(audioServiceProvider.notifier).cleanupFile(wavPath);
      }
    }
  }

  /// Resets the recording state to idle.
  void reset() {
    _cancelAmplitude();
    ref.read(recordingProvider.notifier).reset();
  }

  Future<bool> applyOomModelFallback(String modelId) async {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    if (modelId.isEmpty || settings.effectiveModelId == modelId) {
      return false;
    }

    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(
            sttProvider: SttProviderType.onDevice.value,
            sttModel: modelId,
          ),
        );
    _oomAttemptCount += 1;
    ref.read(oomRecoveryPendingProvider.notifier).clear();
    ref.read(sttServiceProvider.notifier).stop();
    return true;
  }

  Future<SttProviderType?> switchToConfiguredCloudStt() async {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final provider = _preferredCloudProvider(settings);
    if (provider == null) return null;

    await ref.read(settingsProvider.notifier).updateSettings((s) {
      return s.copyWith(
        sttProvider: provider.value,
        cloudSttProvider: _cloudProviderValue(provider),
      );
    });
    _oomAttemptCount = 0;
    ref.read(oomRecoveryPendingProvider.notifier).clear();
    ref.read(sttServiceProvider.notifier).stop();
    return provider;
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  /// Validates STT prerequisites before starting a recording.
  ///
  /// Returns an error code string if something is missing,
  /// or `null` when everything is ready. Error codes are mapped
  /// to localized messages in the UI layer.
  /// Handles recoverable preflight failures gracefully instead of entering
  /// the error phase. Returns `true` if the failure was handled softly
  /// (recording stays idle, info notification sent), `false` if it's a hard
  /// error that should use the normal error flow.
  bool _handleSoftPreflight(String errorCode) {
    switch (errorCode) {
      case 'stt_server_not_found':
        final dl = ref.read(modelDownloadProvider);
        if (dl.downloadedModels.isNotEmpty) {
          // Server missing but models exist → auto-download.
          ref.read(modelDownloadProvider.notifier).ensureServerBinary();
          ref
              .read(recordingInfoProvider.notifier)
              .show('info_engine_auto_download');
        } else {
          // No models at all → user needs to go to settings.
          ref.read(recordingInfoProvider.notifier).show('info_model_missing');
        }
        _log.info('Soft preflight: $errorCode handled gracefully');
        return true;

      case 'stt_model_not_found':
      case 'stt_model_unknown':
        ref.read(recordingInfoProvider.notifier).show('info_model_missing');
        _log.info('Soft preflight: $errorCode handled gracefully');
        return true;

      default:
        return false;
    }
  }

  void _handleOomRecovery() {
    final sid = ref.read(recordingProvider).sessionId ?? '?';
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final currentModelId = settings.effectiveModelId;
    final nextModelId = _nextAvailableFallbackModelId(currentModelId);
    final hasCloudConfigured = _preferredCloudProvider(settings) != null;
    final isPermanentFail =
        nextModelId == null || _oomAttemptCount >= _maxOomRecoveryAttempts;

    ref
        .read(oomRecoveryPendingProvider.notifier)
        .showPending(
          nextModelId: isPermanentFail ? null : nextModelId,
          hasCloudConfigured: hasCloudConfigured,
          isPermanentFail: isPermanentFail,
        );
    ref.read(recordingProvider.notifier).reset();
    ref.read(sttServiceProvider.notifier).notifyRecordingStopped();

    _log.warning(
      '[$sid] CUDA OOM detected for model=$currentModelId '
      'attempts=$_oomAttemptCount/$_maxOomRecoveryAttempts '
      'nextModel=${isPermanentFail ? "none" : nextModelId} '
      'hasCloud=$hasCloudConfigured permanent=$isPermanentFail',
    );
  }

  String? _nextAvailableFallbackModelId(String currentModelId) {
    final currentTier = tierForModel(currentModelId);
    if (currentTier == null) return null;

    final downloadedModels = ref.read(modelDownloadProvider).downloadedModels;
    final tierModels = modelsForTier(currentTier);
    final currentIndex = tierModels.indexWhere(
      (model) => model.id == currentModelId,
    );
    if (currentIndex == -1) return null;

    for (var index = currentIndex + 1; index < tierModels.length; index++) {
      final candidateId = tierModels[index].id;
      if (downloadedModels.contains(candidateId)) {
        return candidateId;
      }
    }

    for (var tierIndex = currentTier.index - 1; tierIndex >= 0; tierIndex--) {
      for (final candidate in modelsForTier(QualityTier.values[tierIndex])) {
        if (downloadedModels.contains(candidate.id)) {
          return candidate.id;
        }
      }
    }

    return null;
  }

  SttProviderType? _preferredCloudProvider(AppSettings settings) {
    final preferredOrder = <SttProviderType>[
      switch (settings.cloudSttProviderType) {
        CloudSttProvider.openAI => SttProviderType.openAI,
        CloudSttProvider.groq => SttProviderType.groq,
        CloudSttProvider.deepgram => SttProviderType.deepgram,
      },
      SttProviderType.openAI,
      SttProviderType.groq,
      SttProviderType.deepgram,
    ];

    for (final provider in preferredOrder) {
      if (_hasApiKeyForProvider(settings, provider)) {
        return provider;
      }
    }

    return null;
  }

  bool _hasApiKeyForProvider(AppSettings settings, SttProviderType provider) {
    return switch (provider) {
      SttProviderType.openAI => settings.openAiApiKey.trim().isNotEmpty,
      SttProviderType.groq => settings.groqApiKey.trim().isNotEmpty,
      SttProviderType.deepgram => settings.deepgramApiKey.trim().isNotEmpty,
      SttProviderType.onDevice => false,
    };
  }

  String _cloudProviderValue(SttProviderType provider) {
    return switch (provider) {
      SttProviderType.openAI => CloudSttProvider.openAI.value,
      SttProviderType.groq => CloudSttProvider.groq.value,
      SttProviderType.deepgram => CloudSttProvider.deepgram.value,
      SttProviderType.onDevice => CloudSttProvider.openAI.value,
    };
  }

  Future<String?> _runPreflight() async {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;

    // Block recording while onboarding is active.
    if (!settings.onboardingCompleted) {
      _log.warning('Preflight FAIL: onboarding not completed');
      return 'onboarding_not_completed';
    }

    // Ensure STT directory exists.
    final dir = Directory(sttDir());
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } on FileSystemException catch (e) {
        _log.warning('Failed to create STT dir: $e');
      }
    }

    // Check whisper-server binary.
    final serverPath = whisperServerPath();
    if (!await File(serverPath).exists()) {
      _log.warning('Preflight FAIL: whisper-server not found at $serverPath');
      return 'stt_server_not_found';
    }

    // Check model file.
    final modelId = settings.effectiveModelId;
    final modelPath = sttModelPath(modelId);
    if (modelPath == null) {
      return 'stt_model_unknown';
    }
    if (!await File(modelPath).exists()) {
      _log.warning('Preflight FAIL: model "$modelId" not found at $modelPath');
      return 'stt_model_not_found';
    }

    _log.info('Preflight OK: server=$serverPath model=$modelPath');
    return null;
  }

  Future<void> _saveToHistory(String transcript, AppSettings settings) async {
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

    await db.upsertEntry(
      HistoryEntriesCompanion(
        id: Value(id),
        content: Value(transcript),
        title: Value(title),
        timestamp: Value(now),
        durationSec: Value(durationSec),
        language: Value(settings.sttLanguageCode),
        model: Value(settings.effectiveModelId),
        isLocal: const Value(true),
        source: const Value('dictation'),
      ),
    );

    // Persist analytics independently from history — these counters survive
    // history entry deletion.
    await db.recordDailyStat(
      timestamp: now,
      model: settings.effectiveModelId,
      isLocal: true,
      durationSec: durationSec,
      processingDurationSec: 0,
      wordCount: wordCount,
      costUsd: 0,
    );

    _log.info('Saved entry $id to history');

    // Auto-cleanup: trim oldest non-favorite entries if limit is set.
    if (settings.historyMaxEntries > 0) {
      final trimmed = await db.trimToMaxEntries(settings.historyMaxEntries);
      if (trimmed > 0) {
        _log.info(
          'Auto-trimmed $trimmed old entries to stay within '
          '${settings.historyMaxEntries} limit',
        );
      }
    }

    // Refresh analytics dashboard so counters update immediately.
    ref.invalidate(analyticsProvider);
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
    _durationWarningFired = false;
  }

  /// Called for every amplitude sample (~100 ms). Implements:
  /// 1. Max recording duration: auto-stop at user-configured limit.
  /// 2. Dead-mic detection: no audio at all for [deadMicTimeout] → error.
  /// 3. Auto-stop on silence: speech detected then silence for
  ///    [autoStopSilence] → auto-transcribe.
  void _evaluateGuard(double level) {
    if (_guardFired) return;
    final recording = ref.read(recordingProvider);
    if (!recording.isRecording) return;

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;

    // ── Max recording duration ──────────────────────────────────────────
    final maxDuration = settings.maxRecordDuration;
    if (maxDuration > 0) {
      final elapsed = recording.elapsed.inSeconds;
      if (elapsed >= maxDuration) {
        _guardFired = true;
        _log.info('Max recording duration reached (${maxDuration}s)');
        _handleAutoStop();
        return;
      }

      // ── Duration warning at 90% ────────────────────────────────────────
      if (!_durationWarningFired && elapsed >= (maxDuration * 0.9).round()) {
        _durationWarningFired = true;
        _playDurationWarning(settings);
      }
    }

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
      final threshold = (settings.deadMicTimeout * samplesPerSecond).round();
      if (_silentSamples >= threshold) {
        _guardFired = true;
        _log.warning(
          'Dead-mic guard triggered after ${settings.deadMicTimeout}s',
        );
        // Auto-stop with error — runs asynchronously.
        _handleDeadMic();
        return;
      }
    }

    // ── Auto-stop on silence (only after speech detected) ────────────────
    if (_speechDetected && settings.autoStopSilence > 0) {
      final threshold = (settings.autoStopSilence * samplesPerSecond).round();
      if (_silentSamples >= threshold) {
        _guardFired = true;
        _log.info(
          'Auto-stop triggered after ${settings.autoStopSilence}s silence',
        );
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
      ref.read(sttServiceProvider.notifier).notifyRecordingStopped();
      ref.read(recordingProvider.notifier).fail('recording_guard_failed');
    } on Exception catch (e) {
      _log.warning('Error during dead-mic cleanup: $e');
      ref.read(sttServiceProvider.notifier).notifyRecordingStopped();
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

  /// Play duration warning sound (90% of max duration reached).
  void _playDurationWarning(AppSettings settings) {
    if (!settings.durationWarningSound) return;
    try {
      ref.read(soundFeedbackProvider.notifier).playDurationWarning();
    } catch (e) {
      _log.warning('Duration warning sound failed: $e');
    }
  }

  /// Best-effort pre-warm: starts the STT server so the first dictation is
  /// instant. Runs in the background — failures are silently logged.
  Future<void> _prewarmStt() async {
    try {
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      if (!settings.sttProviderType.isLocal) return;

      // Only pre-warm when runtime + model are already downloaded.
      final serverPath = whisperServerPath();
      final modelPath = sttModelPath(settings.effectiveModelId);
      if (!await File(serverPath).exists()) return;
      if (modelPath == null || !await File(modelPath).exists()) return;

      await ref.read(sttServiceProvider.notifier).prewarm();
    } on Exception catch (e) {
      _log.warning('STT pre-warm failed (non-fatal): $e');
    }
  }

  Future<bool> _capturePasteTarget() async {
    final controller = ref.read(desktopPasteControllerProvider);
    if (controller == null) return false;

    try {
      return await controller.capturePasteTarget();
    } on MissingPluginException {
      _log.warning(
        'Desktop paste controller missing native implementation for this platform',
      );
      return false;
    } on Exception catch (e) {
      _log.warning('Paste target capture failed: $e');
      return false;
    }
  }

  Future<String?> _captureClipboardText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _log.warning('Clipboard.getData timed out after 2s');
          return null;
        },
      );
      return data?.text;
    } on Exception catch (e) {
      _log.warning('Clipboard snapshot failed: $e');
      return null;
    }
  }

  Future<bool> _copyTranscriptToClipboard(String transcript) async {
    try {
      await Clipboard.setData(ClipboardData(text: transcript)).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _log.warning('Clipboard.setData timed out after 5s');
        },
      );
      _log.info('Transcript copied to clipboard (${transcript.length} chars)');
      return true;
    } on Exception catch (e) {
      _log.warning('Clipboard copy failed: $e');
      return false;
    }
  }

  Future<bool> _pasteClipboard(AppSettings settings) async {
    final controller = ref.read(desktopPasteControllerProvider);
    if (controller == null) {
      _log.warning(
        'Auto-paste requested but no desktop paste controller is available',
      );
      return false;
    }

    final delayMs = settings.autoPasteDelay < 0 ? 0 : settings.autoPasteDelay;

    try {
      if (!_hasCapturedPasteTarget) {
        _hasCapturedPasteTarget = await _capturePasteTarget();
      }
      if (!_hasCapturedPasteTarget) {
        _log.warning(
          'Auto-paste requested but no target window could be captured',
        );
        return false;
      }

      final didPaste = await controller.pasteClipboard(
        delay: Duration(milliseconds: delayMs),
      );
      if (!didPaste) {
        _log.warning(
          'Desktop paste bridge reported an unsuccessful paste attempt',
        );
      }
      return didPaste;
    } on MissingPluginException {
      _log.warning(
        'Desktop paste controller missing native implementation for this platform',
      );
      return false;
    } on Exception catch (e) {
      _log.warning('Desktop paste failed: $e');
      return false;
    }
  }

  Duration _clipboardRestoreDelay(AppSettings settings) {
    final restoreMs = math.max(500, settings.autoPasteDelay + 350);
    return Duration(milliseconds: restoreMs);
  }

  Future<void> _restoreClipboardText(String? previousText) async {
    try {
      await Clipboard.setData(ClipboardData(text: previousText ?? '')).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _log.warning('Clipboard restore timed out after 5s');
        },
      );
    } on Exception catch (e) {
      _log.warning('Clipboard restore failed: $e');
    }
  }

  /// Copies transcript to clipboard and/or simulates paste depending on the
  /// user's "after transcription" setting.
  Future<void> _handleAfterTranscription(
    String transcript,
    AppSettings settings,
  ) async {
    final action = settings.afterTranscriptionAction;

    switch (action) {
      case AfterTranscriptionAction.nothing:
        return;
      case AfterTranscriptionAction.clipboard:
        await _copyTranscriptToClipboard(transcript);
        return;
      case AfterTranscriptionAction.paste:
        final previousClipboardText = await _captureClipboardText();
        final copied = await _copyTranscriptToClipboard(transcript);
        if (!copied) return;

        final didPaste = await _pasteClipboard(settings);
        if (didPaste) {
          await Future<void>.delayed(_clipboardRestoreDelay(settings));
          await _restoreClipboardText(previousClipboardText);
        }
        return;
      case AfterTranscriptionAction.clipboardAndPaste:
        final copied = await _copyTranscriptToClipboard(transcript);
        if (!copied) return;
        await _pasteClipboard(settings);
        return;
    }
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
    NotifierProvider<RecordingOrchestrator, void>(RecordingOrchestrator.new);

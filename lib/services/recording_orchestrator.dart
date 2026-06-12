/// Recording pipeline orchestrator — wires audio capture, STT, history,
/// and the [RecordingNotifier] state machine into a single high-level API.
///
/// External code calls [toggleRecording] — everything else is handled
/// internally, including error recovery and temp-file cleanup.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_state.dart';
import '../core/data/analytics_provider.dart';
import '../features/recording/clipping_state.dart';
import 'audio_service.dart';
import 'model_download_service.dart';
import 'path_service.dart';
import 'recording/oom_recovery_handler.dart';
import 'recording/pipeline_step_runner.dart';
import 'recording/recording_state_machine.dart';
import 'recording/safety_guard.dart';
import 'review_prompt_service.dart';
import 'sound_feedback_service.dart';
import 'paste/paste_failure_notifier.dart';
import 'paste/paste_policy.dart';
import 'paste/paster.dart';
import 'system_attention_service.dart';
import 'tray_service.dart';
import 'recording_store.dart';
import 'stt/stt_bundle.dart';
import 'transcription/transcriber.dart';

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

  /// Subscription to [SafetyGuard] events for the active recording session.
  StreamSubscription<SafetyEvent>? _guardSub;

  /// State machine that enforces the recording phase transition table.
  /// Initialized lazily in [build] after the notifier is available.
  late RecordingStateMachine _stateMachine;

  /// Prevents concurrent `startRecording()` calls from racing through
  /// the async preflight.
  bool _startInFlight = false;

  /// Handles OOM retry policy and model-fallback decisions.
  ///
  /// Initialized lazily in [build] so that [ref] is available for the
  /// callbacks that read settings and downloaded-model state.
  late OomRecoveryHandler _oomHandler;

  /// Exposed for diagnostics/logging only.
  int get oomAttemptCount => _oomHandler.attemptCount;

  @override
  void build() {
    ref.onDispose(_cancelAmplitude);

    // Wire the state machine to the shared RecordingNotifier.
    // phaseReader reads the current phase without accessing protected state.
    _stateMachine = RecordingStateMachine(
      phaseReader: () => ref.read(recordingProvider).phase,
      notifier: ref.read(recordingProvider.notifier),
    );

    // Initialise OOM recovery handler with injectable callbacks so the policy
    // is fully testable without a live Riverpod container.
    _oomHandler = OomRecoveryHandler(
      maxRetries: 3,
      nextModelIdForCurrent: _nextAvailableFallbackModelId,
      hasCloudConfigured: () {
        final settings =
            ref.read(settingsProvider).value ?? AppSettings.defaults;
        return _preferredCloudProvider(settings) != null;
      },
    );

    // Pre-warm the STT server in the background so the first recording
    // doesn't pay the ~10 s cold-start penalty.
    Future.microtask(() => _prewarmStt());
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Acquires the shared `_startInFlight` lock for a voice-note recording
  /// session that runs outside the main dictation pipeline.
  ///
  /// Returns `true` if the lock was acquired (caller may proceed to start
  /// audio capture). Returns `false` if the lock was already held or the
  /// orchestrator phase is not [RecordingPhase.idle] — the caller must treat
  /// this as a no-op and not start any recording.
  ///
  /// The caller **must** call [releaseStartLock] when the voice-note session
  /// ends (success or failure), ideally in a `finally` block.
  bool tryAcquireStartLock() {
    if (_startInFlight) {
      _log.debug('tryAcquireStartLock denied — already in flight');
      return false;
    }
    if (ref.read(recordingProvider).phase != RecordingPhase.idle) {
      _log.debug(
        'tryAcquireStartLock denied — orchestrator not idle '
        '(${ref.read(recordingProvider).phase})',
      );
      return false;
    }
    _startInFlight = true;
    _log.debug('tryAcquireStartLock acquired (voice note)');
    return true;
  }

  /// Releases the `_startInFlight` lock previously acquired via
  /// [tryAcquireStartLock]. Must be called exactly once per successful
  /// acquisition.
  void releaseStartLock() {
    _startInFlight = false;
    _log.debug('releaseStartLock released (voice note)');
  }

  /// Starts or stops recording based on the current phase.
  ///
  /// Recording → stops and transcribes. Idle / done / error → starts a new
  /// recording (a lingering "done"/"error" status is preempted by
  /// [startRecording] — see there). Transcribing is in-flight → ignored.
  Future<void> toggleRecording() async {
    final recording = ref.read(recordingProvider);
    if (recording.isRecording) {
      await stopRecording();
      return;
    }
    if (recording.phase == RecordingPhase.transcribing) return;
    // idle, done, or error → start. Kick off server warm-up before preflight
    // to maximise the parallel window.
    unawaited(_prewarmStt());
    await startRecording();
  }

  /// Starts the recording pipeline.
  Future<void> startRecording() async {
    // Concurrency guard: prevent double-start from hotkey spam or rapid taps.
    if (_startInFlight) {
      _log.debug('startRecording ignored — already in flight');
      return;
    }
    _startInFlight = true;

    // Flow-first: a fresh start while a terminal "done"/"error" status is still
    // lingering preempts it immediately. By the time the phase is `done` the
    // transcript is already pasted (see _finalizeTranscription), and `error` is
    // merely a dismissable status — so there is nothing to lose, and the user
    // can fire the next dictation without waiting out the linger timer (matters
    // most for push-to-hold). This resets to idle so the start can proceed; the
    // now-stale linger timers in recording_behavior.dart no-op on a non-terminal
    // phase.
    final entryPhase = ref.read(recordingProvider).phase;
    if (entryPhase == RecordingPhase.done ||
        entryPhase == RecordingPhase.error) {
      _log.debug('startRecording preempting lingering $entryPhase → idle');
      _stateMachine.transition(RecordingIntent.reset);
    }

    // Re-check phase immediately after acquiring the in-flight lock.
    // A concurrent caller may have already advanced the state machine while
    // this call was entering (e.g. two simultaneous hotkey presses).
    if (ref.read(recordingProvider).phase != RecordingPhase.idle) {
      _log.debug('startRecording aborted — phase not idle after lock acquired');
      _startInFlight = false;
      return;
    }

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
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: preflightError,
        );
        return;
      }

      // Transition state: idle → recording (generates sessionId).
      _stateMachine.transition(RecordingIntent.start);
      final sid = ref.read(recordingProvider).sessionId ?? '?';
      _log.info('[$sid] Recording started');

      // Notify STT service that a recording is active (pauses idle timer).
      final sttNot = ref.read(localSttBundleProvider.notifier);
      sttNot.notifyRecordingStarted();

      // Kick off STT server in parallel — files already confirmed by preflight.
      // Fires before the two async calls below to maximise warm-up lead time.
      // Cloud providers transcribe over HTTP and need no local server.
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      if (settings.sttProviderType.isLocal) {
        unawaited(sttNot.ensureRunning());
      }

      await ref.read(pasterProvider)?.prime();

      // Start audio capture.
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      await audioNotifier.startRecording();

      // Verify recording actually started.
      final audioStatus = ref.read(audioServiceProvider);
      if (audioStatus.captureState == AudioCaptureState.error) {
        sttNot.notifyRecordingStopped();
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: audioStatus.errorMessage ?? 'recording_failed',
        );
        return;
      }

      // Subscribe to amplitude for level metering + safety guard.
      _cancelAmplitude();
      final rawStream = audioNotifier.amplitudeStream;
      if (rawStream != null) {
        // Level-metering subscription (always active).
        // updateAudioLevel is NOT a phase transition, so it calls the
        // notifier directly (it only mutates audioLevel, not RecordingPhase).
        final notifier = ref.read(recordingProvider.notifier);
        _amplitudeSub = rawStream.listen(
          (level) => notifier.updateAudioLevel(level),
          onError: (Object e) {
            _log.warning('[$sid] Amplitude stream error: $e');
          },
        );

        // Safety guard subscription — routes SafetyEvents to handlers.
        final guardConfig = SafetyGuardConfig(
          deadMicTimeout: settings.recordingSafety.deadMicTimeout,
          autoStopSilence: settings.recordingSafety.autoStopSilence,
          maxDurationSeconds: settings.behavior.maxRecordDuration,
          samplesPerSecond: amplitudeSamplesPerSecond,
        );
        _guardSub = rawStream
            .transform(SafetyGuard(config: guardConfig))
            .listen(
              _routeGuardEvent,
              onError: (Object e) {
                _log.warning('[$sid] Safety guard stream error: $e');
              },
            );
      }
    } on Exception catch (e) {
      ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
      _stateMachine.transition(RecordingIntent.fail, errorMessage: '$e');
    } finally {
      _startInFlight = false;
    }
  }

  /// Stops recording and runs the transcription pipeline.
  ///
  /// Each step runs through [PipelineStepRunner.run] with its own budget:
  ///   - Capture/WAV flush: 10 s
  ///   - STT prepare (cold-start): 120 s (large models can need 60–90 s on
  ///     integrated GPUs — a tighter budget would cause spurious timeouts)
  ///   - Transcription: 60 s base + 0.8 × audio duration (scales with clip)
  ///   - Save to history: 5 s
  ///   - After-transcription action (clipboard / paste): 10 s
  ///
  /// A hung step times out independently, preventing it from consuming the
  /// budget meant for later steps.  There is no separate 90-second watchdog;
  /// the per-step timeouts act as the total safety net.
  ///
  /// Pipeline timing is logged at completion (or failure) for diagnostics.
  Future<void> stopRecording() async {
    final sid = ref.read(recordingProvider).sessionId ?? '?';
    String? wavPath;

    // ── Pipeline timing ──────────────────────────────────────────────────
    final pipelineSw = Stopwatch()..start();
    final timing = _PipelineTiming();

    // One runner instance; per-call timeout overrides are used where the
    // step budget differs from the default.  The default is intentionally
    // generous because it is always overridden below — it only serves as a
    // last-resort safety net if a call site omits the explicit timeout.
    const runner = PipelineStepRunner(timeout: Duration(seconds: 120));

    try {
      // Cancel amplitude subscription.
      _cancelAmplitude();

      // ── Step 1: Capture — stop audio and flush WAV (10 s budget) ─────────
      final captureResult = await _runCaptureStep(runner, sid);
      switch (captureResult) {
        case _CaptureAbort(:final outcome):
          timing.outcome = outcome;
          return;
        case _CaptureOk(:final path, :final bytes):
          wavPath = path;
          timing.wavReadyMs = pipelineSw.elapsedMilliseconds;
          _log.debug(
            '[$sid] WAV ready: ${bytes.length} bytes (${timing.wavReadyMs}ms)',
          );
          final shouldContinue = await _runTranscriptionPipeline(
            runner: runner,
            sid: sid,
            wavPath: path,
            wavBytes: bytes,
            timing: timing,
          );
          if (!shouldContinue) return;
      }
    } on Exception catch (e) {
      timing.outcome = 'exception';
      if ('$e'.contains('stt_cuda_oom')) {
        timing.outcome = 'stt_cuda_oom';
        _handleOomRecovery();
        return;
      }
      _stateMachine.transition(RecordingIntent.fail, errorMessage: '$e');
      ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
      _log.error('[$sid] Pipeline error: $e');
    } finally {
      pipelineSw.stop();
      _logPipelineSummary(sid, pipelineSw, timing);

      // Always clean up the temp WAV file.
      if (wavPath != null) {
        await ref.read(audioServiceProvider.notifier).cleanupFile(wavPath);
      }
    }
  }

  /// Runs Step 1: stop audio capture and flush the WAV file to disk.
  ///
  /// Returns a [_CaptureAbort] with the error outcome when the step failed,
  /// or a [_CaptureOk] with the path and bytes when capture succeeded (path
  /// and bytes are guaranteed non-empty).
  Future<_CaptureStepResult> _runCaptureStep(
    PipelineStepRunner runner,
    String sid,
  ) async {
    final captureResult = await runner.run<(String?, List<int>)>(
      'capture',
      () async {
        final audioNotifier = ref.read(audioServiceProvider.notifier);
        final path = await audioNotifier.stopRecording();
        if (path == null) return (null, <int>[]);

        // On Windows the `record` package can return before the WAV is
        // fully flushed to disk.  Wait up to 2 s for the file to appear.
        final wavFile = File(path);
        if (!await wavFile.exists()) {
          _log.debug('[$sid] WAV not yet on disk, waiting for flush…');
          for (var i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            if (await wavFile.exists()) break;
          }
        }
        if (!await wavFile.exists()) return (path, <int>[]);

        final bytes = await wavFile.readAsBytes();
        return (path, bytes);
      },
      timeout: const Duration(seconds: 10),
    );

    switch (captureResult) {
      case StepTimeout():
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: 'pipeline_timeout',
        );
        _log.error('[$sid] Capture step timed out after 10s');
        return const _CaptureAbort('capture_timeout');
      case FailedWith(:final error):
        _stateMachine.transition(RecordingIntent.fail, errorMessage: '$error');
        _log.error('[$sid] Capture step failed: $error');
        return const _CaptureAbort('capture_error');
      case Ok(:final value):
        final path = value.$1;
        final bytes = value.$2;

        if (path == null) {
          _stateMachine.transition(
            RecordingIntent.fail,
            errorMessage: 'no_audio_recorded',
          );
          return const _CaptureAbort('no_audio');
        }

        // Transition state: recording → transcribing.
        _stateMachine.transition(RecordingIntent.stop);

        // Push the final user-gain clipping counter into the settings UI's
        // ClippingState. We only reach this point on a successful capture
        // step — error/abort paths above return early and intentionally
        // leave the previous ClippingState untouched. A fresh `0` from a
        // clean recording overrides any prior non-zero count, which is the
        // desired auto-hide behaviour for the banner.
        ref
            .read(clippingStateProvider.notifier)
            .reportRecordingFinished(
              ref
                  .read(audioServiceProvider.notifier)
                  .lastRecordingClippedSamples,
            );

        if (bytes.isEmpty) {
          // Distinguish between file-never-appeared and empty-file.
          // STT prepare has not run yet, so we do not read localSttBundleProvider
          // here — wav_file_not_created is the correct error in both sub-cases.
          if (!await File(path).exists()) {
            _stateMachine.transition(
              RecordingIntent.fail,
              errorMessage: 'wav_file_not_created',
            );
            _log.error('[$sid] WAV file never appeared: $path');
            return const _CaptureAbort('wav_not_created');
          }
          _stateMachine.transition(
            RecordingIntent.fail,
            errorMessage: 'wav_file_empty',
          );
          _log.error('[$sid] WAV file is empty: $path');
          return const _CaptureAbort('wav_empty');
        }

        return _CaptureOk(path: path, bytes: bytes);
    }
  }

  /// Runs Steps 2–5: STT prepare, transcription, save, and after-transcription
  /// action. Called only after a successful capture step.
  ///
  /// Returns `true` when the pipeline completed (outcome set to `ok`), or
  /// `false` when a step failed and [timing.outcome] has already been set.
  /// All error-phase transitions are performed internally.
  Future<bool> _runTranscriptionPipeline({
    required PipelineStepRunner runner,
    required String sid,
    required String wavPath,
    required List<int> wavBytes,
    required _PipelineTiming timing,
  }) async {
    // Read settings for language hint and model info.
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final effectiveLang = _resolveEffectiveLang(settings);

    // ── Step 2: STT prepare — ensure backend ready (120 s budget) ──────
    // Large models on integrated GPUs can take 60–90 s to load into
    // VRAM; a tighter budget causes spurious timeouts on first use.
    final transcriber = ref.read(transcriberProvider);
    final sttBundle = await _runSttPrepareStep(
      runner,
      sid,
      transcriber,
      timing,
    );
    if (sttBundle == null) return false;

    // ── Step 3: Transcription (60 s base + 0.8× audio duration) ────────
    // Calculate audio duration for RTF logging
    // (16 kHz, mono, 16-bit + 44-byte header).
    final audioDurMs = ((wavBytes.length - 44) / 32000 * 1000).round();
    _log.info(
      '[$sid] Transcribing (${wavBytes.length} bytes, '
      '~${audioDurMs}ms audio, lang=$effectiveLang)',
    );

    // Timeout scales with audio length: 60s base + 0.8× audio duration.
    // A 10s clip gets 68s, a 120s clip gets 156s — enough headroom for
    // large-v3-turbo even on slower hardware.
    final timeoutSec = 60 + (audioDurMs / 1000 * 0.8).round();
    final inferSw = Stopwatch()..start();
    final transcribeResult = await runner.run<String>(
      'transcribe',
      () async => transcriber.transcribe(wavBytes, language: effectiveLang),
      timeout: Duration(seconds: timeoutSec),
    );
    inferSw.stop();
    timing.transcribeMs = inferSw.elapsedMilliseconds;

    return _handleTranscribeResult(
      result: transcribeResult,
      sid: sid,
      sttBundle: sttBundle,
      audioDurMs: audioDurMs,
      timeoutSec: timeoutSec,
      settings: settings,
      runner: runner,
      timing: timing,
    );
  }

  /// Runs Step 2: STT prepare and verifies the local server is ready.
  ///
  /// Returns the [SttStatus] snapshot when prepare succeeded and the server
  /// is ready to accept requests. Returns `null` (with [timing.outcome] set
  /// and error-phase transition performed) when the step should abort.
  Future<SttStatus?> _runSttPrepareStep(
    PipelineStepRunner runner,
    String sid,
    Transcriber transcriber,
    _PipelineTiming timing,
  ) async {
    final ensureSw = Stopwatch()..start();
    final prepareResult = await runner.run<void>(
      'stt_prepare',
      () async => transcriber.prepare(),
      timeout: const Duration(seconds: 120),
    );
    ensureSw.stop();
    timing.sttEnsureMs = ensureSw.elapsedMilliseconds;

    switch (prepareResult) {
      case StepTimeout():
        timing.outcome = 'stt_timeout';
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: 'stt_start_timeout',
        );
        _log.warning('[$sid] STT server start timed out after 120s');
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        return null;
      case FailedWith(:final error) when error is TranscriberException:
        timing.outcome = 'stt_start_error';
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: _transcriberErrorCode(error),
        );
        _log.warning('[$sid] STT prepare failed: ${error.message}');
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        return null;
      case FailedWith(:final error):
        timing.outcome = 'stt_start_error';
        _stateMachine.transition(RecordingIntent.fail, errorMessage: '$error');
        _log.warning('[$sid] STT prepare failed: $error');
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        return null;
      case Ok():
        // prepare succeeded — fall through.
        break;
    }

    // Read localSttBundleProvider exactly once — after prepare() ran so
    // ensureRunning() has had a chance to set the error state (e.g. OOM).
    // All downstream branches (after-prepare check, SocketException path)
    // use this single local variable.
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final sttBundle = ref.read(localSttBundleProvider);

    // Verify local server is ready before transcribing (on-device only).
    if (!sttBundle.isReady && settings.sttProviderType.isLocal) {
      if (sttBundle.errorMessage == 'stt_cuda_oom') {
        timing.outcome = 'stt_cuda_oom';
        _handleOomRecovery();
        return null;
      }
      timing.outcome = 'stt_failed';
      _stateMachine.transition(
        RecordingIntent.fail,
        errorMessage: sttBundle.errorMessage ?? 'stt_server_failed',
      );
      return null;
    }

    return sttBundle;
  }

  /// Dispatches the transcription step result and runs Steps 4–5 on success.
  ///
  /// Returns `true` when the pipeline completed with outcome `ok`, or `false`
  /// when a step failed (with [timing.outcome] and error transitions set).
  Future<bool> _handleTranscribeResult({
    required StepResult<String> result,
    required String sid,
    required SttStatus sttBundle,
    required int audioDurMs,
    required int timeoutSec,
    required AppSettings settings,
    required PipelineStepRunner runner,
    required _PipelineTiming timing,
  }) async {
    switch (result) {
      case StepTimeout():
        timing.outcome = 'transcribe_timeout';
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: 'transcription_timeout',
        );
        _log.error('[$sid] Transcription timed out after ${timeoutSec}s');
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        return false;
      case FailedWith(:final error)
          when error is SocketException || error is http.ClientException:
        // Uses the sttBundle read at the start of the pipeline
        // (single read — covers both SocketException and ClientException).
        if (sttBundle.errorMessage == 'stt_cuda_oom') {
          timing.outcome = 'stt_cuda_oom';
          _handleOomRecovery();
          return false;
        }
        timing.outcome = 'stt_connection_lost';
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: 'stt_server_connection_lost',
        );
        _log.error(
          '[$sid] STT server connection lost during inference'
          '${error is http.ClientException ? " (ClientException)" : ""}',
        );
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        return false;
      case FailedWith(:final error) when error is InferenceClientRejected:
        // Pre-flight reject — validator already emitted a Sentry
        // breadcrumb in category `stt` and explicitly NOT a capture.
        // Surface the user-message-key as the orchestrator's error
        // code so `recording_behavior.dart` can localize the toast.
        timing.outcome = 'transcribe_reject';
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: error.userMessageKey,
        );
        _log.warning(
          '[$sid] Inference rejected pre-flight: ${error.userMessageKey}',
        );
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        return false;
      case FailedWith(:final error) when error is TranscriberException:
        timing.outcome = 'transcribe_error';
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: _transcriberErrorCode(error),
        );
        // Downgraded from `_log.error` to `_log.warning` so the
        // AppLogger auto-escalation does NOT capture a second Sentry
        // event under the catch-all `appLoggerAutoEscalated` finger-
        // print. The explicit capture (with a real fingerprint +
        // extras) already happens inside `SttServerStateNotifier.
        // transcribeBytes` for non-200 responses. See CHANGELOG.md
        // — Unreleased.
        _log.warning('[$sid] Transcription failed: ${error.message}');
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        return false;
      case FailedWith(:final error):
        timing.outcome = 'transcribe_error';
        if ('$error'.contains('stt_cuda_oom')) {
          timing.outcome = 'stt_cuda_oom';
          _handleOomRecovery();
          return false;
        }
        _stateMachine.transition(RecordingIntent.fail, errorMessage: '$error');
        ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
        // Downgraded to `_log.warning` — see the parallel comment a
        // few lines up. The notifier-side `captureError` is the
        // single source of truth for inference Sentry events.
        _log.warning('[$sid] Transcription failed: $error');
        return false;
      case Ok(:final value):
        return _finalizeTranscription(
          sid: sid,
          transcript: value,
          audioDurMs: audioDurMs,
          settings: settings,
          runner: runner,
          timing: timing,
        );
    }
  }

  /// Runs Steps 4–5 after a successful transcription: whitespace cleanup,
  /// save to history, and after-transcription action.
  ///
  /// Returns `true` when the pipeline completed successfully (outcome `ok`),
  /// or `false` when the transcript was empty (outcome `empty_transcript`).
  Future<bool> _finalizeTranscription({
    required String sid,
    required String transcript,
    required int audioDurMs,
    required AppSettings settings,
    required PipelineStepRunner runner,
    required _PipelineTiming timing,
  }) async {
    if (audioDurMs > 0 && timing.transcribeMs! > 0) {
      final rtf = timing.transcribeMs! / audioDurMs;
      _log.info(
        '[$sid] STT: inference=${timing.transcribeMs}ms '
        'audio=${audioDurMs}ms RTF=${rtf.toStringAsFixed(2)}x',
      );
    }

    if (transcript.isEmpty) {
      timing.outcome = 'empty_transcript';
      _stateMachine.transition(
        RecordingIntent.fail,
        errorMessage: 'transcription_empty',
      );
      return false;
    }

    // ── Transcription cleanup (always applied) ────────────────────
    // Whisper models often insert extraneous newlines. Collapse them
    // into single spaces for clean copy/paste results.
    final replaceSw = Stopwatch()..start();
    var finalText = _cleanupTranscriptWhitespace(sid, transcript);
    replaceSw.stop();
    timing.replaceMs = replaceSw.elapsedMilliseconds;

    // ── Step 4: Save to history (5 s budget) ─────────────────────
    final saveSw = Stopwatch()..start();
    final saveResult = await runner.run<String?>(
      'save_history',
      () async => _saveToHistory(
        finalText,
        Duration(milliseconds: audioDurMs),
        settings,
        (timing.transcribeMs ?? 0) ~/ 1000,
      ),
      timeout: const Duration(seconds: 5),
    );
    saveSw.stop();
    timing.saveMs = saveSw.elapsedMilliseconds;

    // Save failures are non-fatal (best-effort) — log and continue.
    if (saveResult case Ok(:final value)) {
      if (value != null && value != finalText) {
        finalText = value;
      }
    } else if (saveResult case StepTimeout()) {
      _log.warning('[$sid] Save to history timed out after 5s');
    } else if (saveResult case FailedWith(:final error)) {
      _log.error('[$sid] Save to history failed: $error');
    }

    // ── Step 5: After-transcription action (10 s budget) ──────────
    // Timeout prevents a locked clipboard or slow paste from
    // hanging the pipeline.
    final clipSw = Stopwatch()..start();
    final clipResult = await runner.run<void>(
      'after_transcription',
      () async => _handleAfterTranscription(finalText, settings),
      timeout: const Duration(seconds: 10),
    );
    clipSw.stop();
    timing.clipboardMs = clipSw.elapsedMilliseconds;

    _logAfterTranscriptionResult(sid, clipResult);

    // Transition state: transcribing/processing → done.
    // Uses RecordingIntent.complete (transcribing→done) which the
    // state machine maps to completeTranscription on the notifier.
    _stateMachine.transition(RecordingIntent.complete, transcript: finalText);
    ref.read(localSttBundleProvider.notifier).notifyTranscriptionCompleted();
    unawaited(ref.read(reviewPromptProvider.notifier).checkAndMaybePrompt());
    _oomHandler.reset();
    timing.outcome = 'ok';
    return true;
  }

  /// Logs the outcome of the after-transcription action step (Step 5).
  /// Non-fatal failures are logged as warnings.
  void _logAfterTranscriptionResult(String sid, StepResult<void> clipResult) {
    switch (clipResult) {
      case StepTimeout():
        _log.warning('[$sid] After-transcription action timed out (10s)');
      case FailedWith(:final error):
        _log.warning(
          '[$sid] After-transcription action failed (non-fatal): $error',
        );
      case Ok():
        break;
    }
  }

  /// Maps a [TranscriberException] to a stable error code for the UI layer.
  ///
  /// Cloud adapters (OpenAI, Deepgram) carry English prose in
  /// [TranscriberException.message]; the toast layer can only localize
  /// stable codes, so auth/quota failures are mapped via the reason enum.
  /// All other reasons pass the message through — the local adapter already
  /// uses code-shaped messages (e.g. `stt_cuda_oom`).
  String _transcriberErrorCode(TranscriberException e) => switch (e.reason) {
    TranscriberFailureReason.authError => 'cloud_auth_error',
    TranscriberFailureReason.quotaExceeded => 'cloud_quota_exceeded',
    _ => e.message,
  };

  /// Resolves the effective transcription language from [settings].
  ///
  /// `"auto"` is passed through as-is so the whisper model performs real
  /// language detection. The previous behavior (falling back to the app UI
  /// locale, inherited from Go's `GetEffectiveLocalTranscriptionLanguage`)
  /// silently forced every auto-detect user onto their UI language — a
  /// Russian speaker on an English UI got English output (store review,
  /// June 2026).
  String _resolveEffectiveLang(AppSettings settings) {
    final language = settings.sttLanguageCode;
    return language.isEmpty ? 'auto' : language;
  }

  /// Collapses extraneous whitespace from a raw whisper transcript.
  ///
  /// Whisper models often insert extraneous newlines. Collapses them into
  /// single spaces for clean copy/paste results. Logs a summary when the
  /// character count changes.
  String _cleanupTranscriptWhitespace(String sid, String transcript) {
    final rawLen = transcript.length;
    final cleaned = transcript
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    if (cleaned.length != rawLen) {
      _log.info('[$sid] Whitespace cleanup: $rawLen→${cleaned.length} chars');
    }
    return cleaned;
  }

  /// Logs a structured pipeline summary to the app log.
  void _logPipelineSummary(
    String sid,
    Stopwatch pipelineSw,
    _PipelineTiming t,
  ) {
    _log.info(
      '[$sid] Pipeline[${t.outcome}]: '
      'total=${pipelineSw.elapsedMilliseconds}ms '
      'wav=${t.wavReadyMs ?? "-"}ms '
      'stt_ensure=${t.sttEnsureMs ?? "-"}ms '
      'transcribe=${t.transcribeMs ?? "-"}ms '
      'replace=${t.replaceMs ?? "-"}ms '
      'save=${t.saveMs ?? "-"}ms '
      'clipboard=${t.clipboardMs ?? "-"}ms',
    );
  }

  /// Resets the recording state to idle.
  void reset() {
    _cancelAmplitude();
    _stateMachine.transition(RecordingIntent.reset);
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
    ref.read(oomRecoveryPendingProvider.notifier).clear();
    ref.read(localSttBundleProvider.notifier).stop();
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
    _oomHandler.reset();
    ref.read(oomRecoveryPendingProvider.notifier).clear();
    ref.read(localSttBundleProvider.notifier).stop();
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

    final decision = _oomHandler.attemptRecovery(
      currentModelId: currentModelId,
    );

    final (
      nextModelId,
      hasCloudConfigured,
      isPermanentFail,
    ) = switch (decision) {
      TryNextModel(:final nextModelId) => (nextModelId, false, false),
      SwitchToConfiguredCloud() => (null, true, true),
      GiveUp() => (null, false, true),
    };

    ref
        .read(oomRecoveryPendingProvider.notifier)
        .showPending(
          nextModelId: nextModelId,
          hasCloudConfigured: hasCloudConfigured,
          isPermanentFail: isPermanentFail,
        );
    // OOM recovery resets to idle regardless of current phase.
    // The oomRetry intent (error→recording) is intentionally NOT used here
    // because the user must explicitly choose a fallback model first.
    _stateMachine.transition(RecordingIntent.reset);
    ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();

    _log.warning(
      '[$sid] CUDA OOM detected for model=$currentModelId '
      'attempts=${_oomHandler.attemptCount} decision=$decision',
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
        CloudSttProvider.deepgram => SttProviderType.deepgram,
      },
      SttProviderType.openAI,
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
      SttProviderType.deepgram => settings.deepgramApiKey.trim().isNotEmpty,
      SttProviderType.onDevice => false,
    };
  }

  String _cloudProviderValue(SttProviderType provider) {
    return switch (provider) {
      SttProviderType.openAI => CloudSttProvider.openAI.value,
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

    // Cloud providers transcribe over HTTP — they need an API key, not the
    // local whisper runtime. Requiring server/model files here would block
    // cloud-only users who never downloaded a local model.
    final providerType = settings.sttProviderType;
    if (!providerType.isLocal) {
      if (!_hasApiKeyForProvider(settings, providerType)) {
        _log.warning(
          'Preflight FAIL: no API key for cloud provider '
          '${providerType.value}',
        );
        return 'cloud_auth_error';
      }
      _log.info('Preflight OK: cloud provider ${providerType.value}');
      return null;
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

  Future<String?> _saveToHistory(
    String transcript,
    Duration audioDuration,
    AppSettings settings,
    int processingDurationSec,
  ) async {
    try {
      final store = ref.read(recordingStoreProvider);
      final wordCount = transcript.trim().isEmpty
          ? 0
          : transcript.trim().split(RegExp(r'\s+')).length;

      final saved = await store.save(
        RecordingInput(
          transcript: transcript,
          audioDuration: audioDuration,
          modelId: settings.effectiveModelId,
          isLocal: settings.sttProviderType.isLocal,
          languageCode: settings.sttLanguageCode,
          applyTextReplacements: settings.textReplacementsEnabled,
          historyMaxEntries: settings.historyMaxEntries,
          wordCount: wordCount,
          processingDurationSec: processingDurationSec,
        ),
      );

      _log.info('Saved entry ${saved.entryId} to history');

      if (saved.trimmedCount > 0) {
        _log.info(
          'Auto-trimmed ${saved.trimmedCount} old entries to stay within '
          '${settings.historyMaxEntries} limit',
        );
      }

      // Refresh analytics dashboard so counters update immediately.
      ref.invalidate(analyticsProvider);

      return saved.processedTranscript;
    } on Exception catch (e) {
      _log.error('Failed to save to history: $e');
      return null;
    }
  }

  void _cancelAmplitude() {
    _guardSub?.cancel();
    _guardSub = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  // ── Safety guard event routing ────────────────────────────────────────────

  /// Routes a [SafetyEvent] emitted by [SafetyGuard] to the appropriate handler.
  void _routeGuardEvent(SafetyEvent event) {
    switch (event) {
      case DeadMicTimeoutReached():
        _log.warning('Dead-mic guard triggered');
        _handleDeadMic();
      case SilenceAutoStop():
        _log.info('Auto-stop triggered by silence');
        _handleAutoStop();
      case DurationWarningAt90():
        _log.info('90% duration warning');
        _playDurationWarning();
      case DurationLimitReached():
        _log.info('Max recording duration reached');
        _handleAutoStop();
    }
  }

  /// Dead-mic triggered: stop recording and surface error.
  Future<void> _handleDeadMic() async {
    // Guard-fire is expected user behaviour (no microphone input), not a crash.
    // Goes in at info level so the AppLogger pipeline turns it into a Sentry
    // breadcrumb — context for any later real error, but not a standalone issue.
    _log.info('guard-fire: dead-mic (no audio detected before timeout)');
    try {
      _cancelAmplitude();
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      await audioNotifier.stopRecording();
      ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
      _stateMachine.transition(
        RecordingIntent.fail,
        errorMessage: 'recording_guard_failed',
      );
    } on Exception catch (e) {
      _log.warning('Error during dead-mic cleanup: $e');
      ref.read(localSttBundleProvider.notifier).notifyRecordingStopped();
      _stateMachine.transition(
        RecordingIntent.fail,
        errorMessage: 'recording_guard_failed',
      );
    }
  }

  /// Auto-stop triggered: stop recording and run transcription pipeline.
  Future<void> _handleAutoStop() async {
    // Guard-fire is expected user behaviour (silence after speech), not a crash.
    // Goes in at info level so the AppLogger pipeline turns it into a Sentry
    // breadcrumb — context for any later real error, but not a standalone issue.
    _log.info('guard-fire: auto-stop (silence detected after speech)');
    try {
      await stopRecording();
    } on Exception catch (e) {
      _log.warning('Error during auto-stop: $e');
      _stateMachine.transition(RecordingIntent.fail, errorMessage: '$e');
    }
  }

  /// Play duration warning sound (90% of max duration reached).
  void _playDurationWarning() {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    if (!settings.sound.durationWarningSound) return;
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

      await ref.read(localSttBundleProvider.notifier).prewarm();
    } on Exception catch (e) {
      _log.warning('STT pre-warm failed (non-fatal): $e');
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

  /// Copies transcript to clipboard and/or simulates paste depending on the
  /// user's "after transcription" setting.
  Future<void> _handleAfterTranscription(
    String transcript,
    AppSettings settings,
  ) async {
    // In the sandboxed Mac App Store build, simulated paste is unavailable, so
    // paste actions are downgraded to clipboard-only (user pastes with ⌘V).
    final action = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
    );

    switch (action) {
      case AfterTranscriptionAction.nothing:
        return;
      case AfterTranscriptionAction.clipboard:
        await _copyTranscriptToClipboard(transcript);
        return;
      case AfterTranscriptionAction.paste:
        await _pasteTranscript(transcript, settings);
        return;
      case AfterTranscriptionAction.clipboardAndPaste:
        await _copyTranscriptToClipboard(transcript);
        await _pasteTranscript(transcript, settings);
        return;
    }
  }

  Future<bool> _pasteTranscript(String transcript, AppSettings settings) async {
    final paster = ref.read(pasterProvider);
    if (paster == null) return false;

    // Capture the paste target if it hasn't been primed yet (e.g. when this
    // is the first recording, or recording was started externally).
    await paster.prime();

    final outcome = await paster.paste(
      transcript,
      PasteOptions(
        autoPasteDelayMs: settings.autoPasteDelay,
        blocklist: settings.autoPasteBlocklist,
      ),
    );

    switch (outcome) {
      case PasteOutcome.success:
        _log.info('Pasted transcript (${transcript.length} chars)');
        _clearPasteAttention();
        return true;
      case PasteOutcome.blocked:
        _log.info('Auto-paste blocked for current app (in blocklist)');
        return false;
      case PasteOutcome.platformUnavailable:
        _log.warning('Desktop paste not available on this platform');
        return false;
      case PasteOutcome.noTarget:
        _log.warning(
          'Paste failed: no target window — WhisPaste was likely '
          'frontmost when recording started. Focus the destination app '
          'first, then trigger recording.',
        );
        _reportPasteFailure(
          outcome: PasteOutcome.noTarget,
          kind: AttentionKind.pasteBlockedNoTarget,
          title: 'WhisPaste: Auto-Einfügen übersprungen',
          body:
              'Keine Ziel-App erkannt. Fokussiere zuerst die Ziel-App, dann starte die Aufnahme. Der Text liegt in der Zwischenablage.',
          trayLabel: 'Auto-Einfügen: Ziel-App fehlte',
        );
        return false;
      case PasteOutcome.permissionMissing:
        _log.warning(
          'Paste failed: OS denied event injection. On macOS, grant '
          'Accessibility permission in System Settings → Privacy & '
          'Security → Accessibility.',
        );
        _reportPasteFailure(
          outcome: PasteOutcome.permissionMissing,
          kind: AttentionKind.pasteBlockedPermission,
          title: 'WhisPaste: Auto-Einfügen blockiert',
          body:
              'Bedienungshilfen-Berechtigung fehlt. Klicke hier oder das Tray-Icon, um sie in den Systemeinstellungen zu erteilen.',
          trayLabel: 'Auto-Einfügen blockiert — Berechtigung erteilen',
        );
        return false;
      case PasteOutcome.failed:
        _log.warning('Paste failed: native bridge reported an unknown error');
        _reportPasteFailure(
          outcome: PasteOutcome.failed,
          kind: AttentionKind.pasteFailedUnknown,
          title: 'WhisPaste: Auto-Einfügen fehlgeschlagen',
          body:
              'Das System hat den Einfüge-Vorgang abgelehnt. Der Text liegt in der Zwischenablage — füge ihn manuell mit ⌘V / Strg+V ein.',
          trayLabel: 'Auto-Einfügen fehlgeschlagen',
        );
        return false;
    }
  }

  void _reportPasteFailure({
    required PasteOutcome outcome,
    required AttentionKind kind,
    required String title,
    required String body,
    required String trayLabel,
  }) {
    ref.read(pasteFailureNotifierProvider.notifier).report(outcome);

    // Fire out-of-app surfaces (dock-bounce + native notification + tray
    // badge) so the user sees the failure even when the main window is
    // hidden — the common case for WhisPaste.
    unawaited(
      ref
          .read(systemAttentionServiceProvider)
          .requestAttention(kind: kind, title: title, body: body),
    );
    try {
      ref
          .read(trayServiceProvider.notifier)
          .setActionNeeded(
            label: trayLabel,
            tooltip: 'WhisPaste — $trayLabel',
            menuItemKey: 'paste_action_needed',
          );
    } on Exception catch (e) {
      _log.warning('Tray action-needed update failed', e);
    }
  }

  void _clearPasteAttention() {
    unawaited(ref.read(systemAttentionServiceProvider).clearAttention());
    try {
      ref.read(trayServiceProvider.notifier).clearActionNeeded();
    } on Exception catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global recording orchestrator provider.
///
/// The orchestrator is a `void` notifier — it has no state of its own.
/// All observable state lives in [recordingProvider], [audioServiceProvider],
/// and [localSttBundleProvider].
final recordingOrchestratorProvider =
    NotifierProvider<RecordingOrchestrator, void>(RecordingOrchestrator.new);

// ---------------------------------------------------------------------------
// Pipeline step helpers
// ---------------------------------------------------------------------------

/// Mutable container for per-step pipeline timing and outcome, threaded
/// through [RecordingOrchestrator._runTranscriptionPipeline] and the
/// summary logger so local variables in [stopRecording] stay minimal.
class _PipelineTiming {
  String outcome = 'unknown';
  int? wavReadyMs;
  int? sttEnsureMs;
  int? transcribeMs;
  int? replaceMs;
  int? saveMs;
  int? clipboardMs;
}

/// Sealed result of [RecordingOrchestrator._runCaptureStep].
sealed class _CaptureStepResult {
  const _CaptureStepResult();
}

/// Capture step failed — pipeline should abort with [outcome].
final class _CaptureAbort extends _CaptureStepResult {
  const _CaptureAbort(this.outcome);
  final String outcome;
}

/// Capture step succeeded — [path] and [bytes] are ready for transcription.
final class _CaptureOk extends _CaptureStepResult {
  const _CaptureOk({required this.path, required this.bytes});
  final String path;
  final List<int> bytes;
}

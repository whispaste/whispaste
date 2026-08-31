/// Recording pipeline orchestrator — wires audio capture, STT, history,
/// and the [RecordingNotifier] state machine into a single high-level API.
///
/// External code calls [toggleRecording] — everything else is handled
/// internally, including error recovery and temp-file cleanup.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/config/build_config.dart';
import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/perf_instrumentation.dart';
import '../core/recording/recording_state.dart';
import '../core/data/analytics_provider.dart';
import '../core/data/database.dart';
import '../features/recording/clipping_state.dart';
import 'audio_service.dart';
import 'clipboard_history/app_clipboard.dart';
import 'model_download_service.dart';
import 'path_service.dart';
import 'recording/oom_recovery_handler.dart';
import 'recording/pipeline_step_runner.dart';
import 'recording/recording_state_machine.dart';
import 'recording/safety_guard.dart';
import 'review_prompt_service.dart';
import 'store_thank_you_service.dart';
import 'snippet_picker/snippet_picker_controller.dart'
    show snippetPickerAvailableOnPlatform;
import 'snippet_picker/snippet_picker_dispatch.dart';
import 'snippet_picker/snippet_picker_service.dart';
import 'smart_mode/smart_mode_ffi_engine.dart' show smartModeEngineProvider;
import 'smart_mode/smart_mode_model_download_service.dart'
    show smartModeDownloadProvider;
import 'smart_mode/smart_mode_presets.dart';
import 'sound_feedback_service.dart';
import 'support_prompt_service.dart';
import 'telemetry_service.dart';
import 'paste/paste_capability_notifier.dart';
import 'paste/paste_failure_notifier.dart';
import 'paste/paste_policy.dart';
import 'paste/paster.dart';
import 'system_attention_service.dart';
import 'number_transforms.dart';
import 'text_transforms.dart';
import 'tray_service.dart';
import 'recording_store.dart';
import 'stt/inference_client_rejected.dart';
import 'stt/on_device_engine_lifecycle.dart';
import 'stt_engine_lifecycle_provider.dart';
import 'stt_parakeet/parakeet_model_registry.dart' as parakeet;
import 'transcription/transcriber.dart';
import '../core/utils/word_count.dart';

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

  /// Prevents concurrent `stopRecording()` calls from launching multiple
  /// transcription pipelines (e.g. hotkey-stop + auto-stop firing together).
  bool _stopInFlight = false;

  /// Throttle for the "pipeline busy" hint — a held or mashed hotkey hits the
  /// abort branches several times per second, and a toast per press would be
  /// worse than the silence it replaces.
  static const _busyHintThrottle = Duration(seconds: 3);
  DateTime? _lastBusyHintAt;

  /// Pending hotkey-press t₀ for the hotkey→text end-to-end latency KPI
  /// (issue 07-latenz-kpi-erfassung — local-only, never sent as telemetry).
  ///
  /// Captured (peeked, not consumed) in [startRecording] from
  /// [PerfMarkers.pendingHotkeyPressedAt] and persisted once transcription
  /// finishes successfully in [_finalizeTranscription]. A stale value left
  /// over from an aborted start attempt is harmless: the next
  /// [startRecording] call always overwrites it before any session that
  /// could read it exists.
  DateTime? _hotkeyPressedAtForLatencyKpi;

  /// Handles OOM retry policy and model-fallback decisions.
  ///
  /// Initialized lazily in [build] so that [ref] is available for the
  /// callbacks that read settings and downloaded-model state.
  late OomRecoveryHandler _oomHandler;

  /// Exposed for diagnostics/logging only.
  int get oomAttemptCount => _oomHandler.attemptCount;

  /// Sandbox transcript sink for onboarding's "test recording" step
  /// (`TestRecordingStep`). When set, [_handleAfterTranscription] delivers
  /// the finished transcript to this callback instead of the real
  /// clipboard/paste path — the guided test must never write to the system
  /// clipboard or paste into whatever window happens to have focus behind
  /// the onboarding overlay. `null` (the default) for every other caller, so
  /// production behaviour outside onboarding is completely unaffected.
  void Function(String text)? sandboxTranscriptSink;

  /// Registrable override for delivering an appended quick-note text to a
  /// live note editor instead of the direct database write (Ticket 21
  /// registers this once the target note is open in the editor — the editor
  /// owns persistence via its own debounced autosave, and a direct write
  /// here would be clobbered by the next autosave tick). Called with the
  /// note id and the *full new content* (already appended). Return `true` to
  /// mean "handled, skip the database write"; `false` (or leave `null`) to
  /// fall through to it. `null` — the default — means every quick-note
  /// append goes straight to the database, which is the only behaviour this
  /// ticket (19) implements; Ticket 21 adds the registration.
  bool Function(String noteId, String newContent)? quickNoteLiveEditorOverride;

  /// Registrable pre-hook, awaited at the very start of a quick-note append —
  /// **before** the note is read back from the database.
  ///
  /// The note editor persists through a 400 ms debounced autosave, so the
  /// row this method reads is stale for as long as the user's last keystrokes
  /// are still pending. Appending onto that stale content and handing the
  /// result to [quickNoteLiveEditorOverride] would silently discard those
  /// keystrokes. `NotesPage` therefore registers its autosave flush here:
  /// once it has run, the database row is current, and the appended content
  /// contains the typed text as well as the transcript.
  ///
  /// `null` (the default) means "nothing to flush" — every non-editor caller
  /// is unaffected.
  Future<void> Function()? quickNoteEditorFlush;

  /// Fires after a quick-note append completes, naming the target note —
  /// the externally-observable completion hook Ticket 21 hangs its window/
  /// editor-focus reaction on, instead of guessing from the
  /// [RecordingPhase] transition.
  void Function(String noteId)? onQuickNoteAppended;

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
  ///
  /// [target] selects what a successful transcription does with the
  /// finished text — see [RecordingTarget]. Defaults to today's clipboard/
  /// paste behaviour, so every existing caller (tray, shelf button, floating
  /// button, main hotkey) is unaffected.
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
    SmartModePreset? forcedSmartModePreset,
  }) async {
    final recording = ref.read(recordingProvider);
    if (recording.isRecording) {
      await stopRecording();
      return;
    }
    if (recording.phase == RecordingPhase.transcribing ||
        // Smart Mode v2 (ticket 02): the Cleanup pass keeps the pipeline
        // busy here too — without this, a second hotkey press mid-refining
        // would fall through to `startRecording()`, which the state machine
        // then rejects as an invariant violation (no `start` transition is
        // defined from `refining`) after already mutating unrelated
        // orchestrator state (recordingTargetProvider, `_startInFlight`).
        recording.phase == RecordingPhase.refining) {
      return;
    }
    // idle, done, or error → start. Kick off server warm-up before preflight
    // to maximise the parallel window.
    unawaited(_prewarmStt());
    await startRecording(
      target: target,
      forcedSmartModePreset: forcedSmartModePreset,
    );
  }

  /// Starts the recording pipeline.
  ///
  /// [forcedSmartModePreset] (ticket 04 of `.scratch/smart-mode-v2/`)
  /// overrides `settings.smartMode.standardPreset` for this recording only —
  /// used by the Smart-Mode hotkey, which applies its own bound preset
  /// independently of the main hotkey's standard-preset setting. `null` (the
  /// default) means "use the standard preset as usual".
  Future<void> startRecording({
    RecordingTarget target = RecordingTarget.clipboard,
    SmartModePreset? forcedSmartModePreset,
  }) async {
    // Capture the pending hotkey-press t₀ (if any) for the hotkey→text
    // latency KPI. Peeked (not consumed) synchronously, before any `await`
    // below, so it reflects the key-down that triggered THIS call — the
    // existing hotkey→overlay latency pairing (PerfMarkers.markOverlayShown,
    // reset separately) is unaffected.
    _hotkeyPressedAtForLatencyKpi = PerfMarkers.instance.pendingHotkeyPressedAt;

    // Same "next start always overwrites, never reset at exit" pattern as
    // the latency t₀ above: unconditional, before any await, so a target
    // left over from an aborted/ignored start is structurally impossible
    // rather than dependent on covering every abort path.
    ref.read(recordingTargetProvider.notifier).set(target);
    ref
        .read(smartModeHotkeyOverridePresetProvider.notifier)
        .set(forcedSmartModePreset);

    // Concurrency guard: prevent double-start from hotkey spam or rapid taps.
    if (_startInFlight) {
      _log.debug('startRecording ignored — already in flight');
      _hintPipelineBusy();
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
      _hintPipelineBusy();
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

      // No per-start telemetry: a recording's outcome is captured once at the
      // end via the aggregated pipeline-outcome counter (see
      // _trackPipelineOutcome), keeping Matomo volume off the hot path.

      // Notify the active on-device engine that a recording is active
      // (pauses its idle timer, if any).
      final engineLifecycle = ref.read(onDeviceEngineLifecycleProvider);
      engineLifecycle.notifyRecordingStarted();

      // Kick off the on-device engine in parallel — files already confirmed
      // by preflight. Fires before the two async calls below to maximise
      // warm-up lead time. Cloud providers transcribe over HTTP and need no
      // local engine.
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      if (settings.sttProviderType.isLocal) {
        unawaited(engineLifecycle.ensureRunning());
      }

      // Capturing the paste target only makes sense for the clipboard/paste
      // path — a quick-note target never pastes anywhere, so skip it for a
      // pure latency win, not a behaviour change.
      if (target == RecordingTarget.clipboard) {
        await ref.read(pasterProvider)?.prime();
      }

      // Start audio capture.
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      await audioNotifier.startRecording();

      // Verify recording actually started.
      final audioStatus = ref.read(audioServiceProvider);
      if (audioStatus.captureState == AudioCaptureState.error) {
        engineLifecycle.notifyRecordingStopped();
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
      ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
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
    // Concurrency guard: prevent double-stop from hotkey spam, auto-stop, or
    // simultaneous toggleRecording() calls racing through the pipeline.
    if (_stopInFlight) {
      _log.debug('stopRecording ignored — already in flight');
      return;
    }
    _stopInFlight = true;

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
      ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
      _log.error('[$sid] Pipeline error: $e');
    } finally {
      pipelineSw.stop();
      _logPipelineSummary(sid, pipelineSw, timing);
      _trackPipelineOutcome(timing, pipelineSw.elapsedMilliseconds);

      // Always clean up the temp WAV file — unless a diagnosis session has
      // opted into keeping it (see [kRetainDebugAudio]'s doc comment for
      // why: an intermittent transcription drop can only be replayed
      // through the offline harness if the exact audio Whisper received
      // survives past this cleanup step).
      if (wavPath != null) {
        if (kRetainDebugAudio) {
          _log.info('[$sid] kRetainDebugAudio active — kept WAV at $wavPath');
        } else {
          await ref.read(audioServiceProvider.notifier).cleanupFile(wavPath);
        }
      }

      // Release the re-entry guard only after cleanup completes, so a
      // concurrent stop cannot slip into this window and double-clean the
      // same WAV file.
      _stopInFlight = false;
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
          // STT prepare has not run yet, so we do not read the engine
          // lifecycle status here — wav_file_not_created is the correct
          // error in both sub-cases.
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
      wavPath: wavPath,
      sttBundle: sttBundle,
      audioDurMs: audioDurMs,
      timeoutSec: timeoutSec,
      settings: settings,
      runner: runner,
      timing: timing,
    );
  }

  /// Runs Step 2: STT prepare and verifies the local engine is ready.
  ///
  /// Returns the [EngineLifecycleStatus] snapshot when prepare succeeded and
  /// the engine is ready to accept requests. Returns `null` (with
  /// [timing.outcome] set and error-phase transition performed) when the
  /// step should abort.
  Future<EngineLifecycleStatus?> _runSttPrepareStep(
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
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
        return null;
      case FailedWith(:final error) when error is TranscriberException:
        timing.outcome = 'stt_start_error';
        _stateMachine.transition(
          RecordingIntent.fail,
          errorMessage: _transcriberErrorCode(error),
        );
        _log.warning('[$sid] STT prepare failed: ${error.message}');
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
        return null;
      case FailedWith(:final error):
        timing.outcome = 'stt_start_error';
        _stateMachine.transition(RecordingIntent.fail, errorMessage: '$error');
        _log.warning('[$sid] STT prepare failed: $error');
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
        return null;
      case Ok():
        // prepare succeeded — fall through.
        break;
    }

    // Read the engine lifecycle status exactly once — after prepare() ran so
    // ensureRunning() has had a chance to set the error state (e.g. OOM).
    // All downstream branches (after-prepare check, SocketException path)
    // use this single local variable.
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final sttBundle = ref.read(onDeviceEngineLifecycleProvider).status;

    // Verify the local engine is ready before transcribing (on-device only).
    // stt_cuda_oom is whisper/CUDA-specific — Parakeet's CPU ONNX Runtime
    // never emits it, so this branch simply never fires for that engine.
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
    required String wavPath,
    required EngineLifecycleStatus sttBundle,
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
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
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
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
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
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
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
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
        return false;
      case FailedWith(:final error):
        timing.outcome = 'transcribe_error';
        if ('$error'.contains('stt_cuda_oom')) {
          timing.outcome = 'stt_cuda_oom';
          _handleOomRecovery();
          return false;
        }
        _stateMachine.transition(RecordingIntent.fail, errorMessage: '$error');
        ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
        // Downgraded to `_log.warning` — see the parallel comment a
        // few lines up. The notifier-side `captureError` is the
        // single source of truth for inference Sentry events.
        _log.warning('[$sid] Transcription failed: $error');
        return false;
      case Ok(:final value):
        return _finalizeTranscription(
          sid: sid,
          transcript: value,
          wavPath: wavPath,
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
    required String wavPath,
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

    // ── Smart Mode: local Cleanup preset (ticket 02) ──────────────────
    // Runs before history-save/snippet-picker/paste so every downstream
    // consumer of `finalText` sees the same (possibly refined) value — this
    // ticket replaces the transcript in place, it does not keep a separate
    // raw+edited pair (that's the History data model, PRODUCT-SPEC §7, a
    // later ticket's scope). Skipped for the onboarding sandbox recording,
    // same as history-save below — a Smart Mode failure notification during
    // the guided test-recording step would be a confusing false alarm, and
    // "off" (the factory default, ticket 01) is a pure no-op path so this
    // whole block never runs for a recording with no active preset.
    // Ticket 04: the Smart-Mode hotkey's bound preset overrides the standard
    // preset for this recording only — see startRecording's doc comment.
    final activePreset =
        ref.read(smartModeHotkeyOverridePresetProvider) ??
        smartModePresetFromSettingsValue(settings.smartMode.standardPreset);
    if (sandboxTranscriptSink == null && activePreset != SmartModePreset.off) {
      finalText = await _runSmartModeRefine(
        sid,
        finalText,
        runner,
        activePreset,
        settings,
      );
    }

    // ── Snippet-Picker dispatch (exact-match short-circuit, ticket 06) ────
    // A transcript that matches the picker's trigger word exactly (after
    // normalization) never reaches history/replacements or paste. An empty
    // snippet list makes SnippetPickerService.show return false, and the
    // transcript falls through to the normal pipeline below instead of
    // vanishing — same "never silently discard the dictation" contract.
    // Skipped in the same onboarding-sandbox case as history/paste below, and
    // for a quick-note target — the picker inserts by pasting into the
    // focused application, which makes no sense for a note target.
    final snippetPickerDispatched =
        sandboxTranscriptSink == null &&
        ref.read(recordingTargetProvider) == RecordingTarget.clipboard &&
        await _tryDispatchSnippetPicker(sid, finalText, settings);

    if (!snippetPickerDispatched) {
      // ── Step 4: Save to history (5 s budget) ─────────────────────
      // Onboarding's test-recording step redirects the transcript to a local
      // sandbox field only (see sandboxTranscriptSink docs on
      // _handleAfterTranscription below) — it must never be written to the
      // user's real History, so the whole save step is skipped while the sink
      // is set.
      if (sandboxTranscriptSink == null) {
        final saveSw = Stopwatch()..start();
        final saveResult = await runner.run<String?>(
          'save_history',
          () async => _saveToHistory(
            finalText,
            Duration(milliseconds: audioDurMs),
            settings,
            (timing.transcribeMs ?? 0) ~/ 1000,
            wavPath,
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
      }

      // ── Zahlen-Modus (itn-cad-zahlen, digits-only transform) ────────
      // Runs after the history-save block (and its text-replacement pass,
      // so a trigger phrase that happens to contain a number word still
      // fires) but before stripPunctuation (whose ambiguous-punctuation
      // guard for a decimal separator only works once digits already
      // exist). Precedent-conform with stripPunctuation (§6.2 Option D1,
      // itn-cad-zahlen PRD): the history entry keeps the pre-transform
      // text — no second DB write in this latency-critical path.
      if (settings.stt.numericOnlyMode) {
        finalText = toNumericOnly(finalText) ?? finalText;
      }

      // ── Punctuation strip (always applied after text replacements) ──
      // Deterministic, engine-independent — runs regardless of which STT
      // engine/provider produced finalText. Placed after the history-save
      // block (and its text-replacement pass) so a user's own explicit voice
      // shortcut for punctuation (e.g. a "period" → "." trigger) survives;
      // only the STT engine's own auto-inserted punctuation is removed.
      if (settings.stt.stripPunctuation) {
        finalText = stripPunctuation(finalText);
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
    }

    // Text is now in the field (clipboard/paste action above has completed)
    // — this is the "fertig eingefügter Text" moment for the hotkey→text
    // end-to-end latency KPI. Local-only persistence; never touches the
    // outgoing (bucketed) telemetry aggregator.
    await _persistHotkeyLatencyIfPending(sid);

    // Transition state: transcribing/processing → done.
    // Uses RecordingIntent.complete (transcribing→done) which the
    // state machine maps to completeTranscription on the notifier.
    _stateMachine.transition(RecordingIntent.complete, transcript: finalText);
    ref.read(onDeviceEngineLifecycleProvider).notifyTranscriptionCompleted();
    // Two independent fire-and-forget checks, mirroring the existing
    // single-call pattern — the support prompt's coordination check reads
    // (never mutates) the review prompt's in-session/persisted state, so it
    // does not need to be awaited after the review check specifically.
    unawaited(ref.read(reviewPromptProvider.notifier).checkAndMaybePrompt());
    unawaited(ref.read(supportPromptProvider.notifier).checkAndMaybePrompt());
    // Re-evaluate after every real recording (not just at onboarding-complete
    // time) so the engagement gate in shouldShowStoreThankYou — added after
    // Apple's Guideline 5.6.3 rejection of v1.2.66 — actually gets to fire
    // once the user crosses the threshold.
    unawaited(
      ref
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: settings.onboardingCompleted),
    );
    _oomHandler.reset();
    timing.outcome = 'ok';

    // No separate 'complete' event — the aggregated pipeline outcome (emitted
    // once per run in _trackPipelineOutcome) already records the success path.

    return true;
  }

  /// Timeout for the Smart Mode Cleanup engine call itself — the primary
  /// timeout, expected to fire (if anything does) well before
  /// [RecordingNotifier]'s own `refining`-phase safety-net guard (30s). Local
  /// inference is measured at 0.3–2.5s for a typical dictation (ADR 0009);
  /// this budget is generous headroom for slower hardware, not the expected
  /// case.
  static const _smartModeCleanupTimeout = Duration(seconds: 15);

  /// Test-only override for [_smartModeCleanupTimeout] — lets tests exercise
  /// the timeout branch in well under a second instead of waiting 15 real
  /// seconds. Mirrors [sttDirOverride]'s "test-only, must stay null in
  /// production" convention. Must stay `null` in production code.
  @visibleForTesting
  static Duration? smartModeCleanupTimeoutOverride;

  /// Runs the active Smart Mode preset ([SmartModePreset.cleanup],
  /// [SmartModePreset.concise], or [SmartModePreset.translate]) over
  /// [rawText] and returns the result — or [rawText] unchanged on any
  /// failure (model missing, load error, decode error, timeout, blank
  /// result), firing a clearly-visible OS notification in that case. Smart
  /// Mode never blocks the paste (ADR 0009): the caller always gets a usable
  /// string back, never a thrown exception. [preset] is never
  /// [SmartModePreset.off] — the caller already filters that out.
  Future<String> _runSmartModeRefine(
    String sid,
    String rawText,
    PipelineStepRunner runner,
    SmartModePreset preset,
    AppSettings settings,
  ) async {
    if (!ref.read(smartModeDownloadProvider).modelDownloaded) {
      _log.info(
        '[$sid] Smart Mode $preset selected but model not downloaded — '
        'falling back to raw transcript',
      );
      _notifySmartModeFallback();
      return rawText;
    }

    final systemPrompt = switch (preset) {
      SmartModePreset.cleanup => smartModeCleanupSystemPrompt,
      SmartModePreset.concise => smartModeConciseSystemPrompt,
      SmartModePreset.translate => smartModeTranslateSystemPrompt(
        smartModeTargetLanguageFromSettingsValue(
          settings.smartMode.targetLanguage,
        ),
      ),
      SmartModePreset.off => throw StateError(
        '_runSmartModeRefine called with preset off',
      ),
    };

    _stateMachine.transition(
      RecordingIntent.startRefining,
      transcript: rawText,
    );

    final result = await runner.run<String>(
      'smart_mode_refine',
      () => ref
          .read(smartModeEngineProvider)
          .run(systemPrompt: systemPrompt, userText: rawText),
      timeout: smartModeCleanupTimeoutOverride ?? _smartModeCleanupTimeout,
    );

    switch (result) {
      case Ok(:final value):
        if (value.trim().isEmpty) {
          // A blank/whitespace-only response is treated as a failure — never
          // silently paste an empty string where the user dictated real
          // content.
          _log.warning('[$sid] Smart Mode $preset returned empty result');
          _notifySmartModeFallback();
          return rawText;
        }
        _log.debug('[$sid] Smart Mode $preset succeeded');
        return value;
      case StepTimeout():
        _log.warning(
          '[$sid] Smart Mode $preset timed out after '
          '${_smartModeCleanupTimeout.inSeconds}s',
        );
        _notifySmartModeFallback();
        return rawText;
      case FailedWith(:final error):
        _log.warning('[$sid] Smart Mode $preset failed: $error');
        _notifySmartModeFallback();
        return rawText;
    }
  }

  /// Fires the OS notification for a Smart Mode fallback (ticket 02) — the
  /// paste itself still succeeds with the raw transcript, so unlike every
  /// other [SystemAttentionService] call site in this file this is purely
  /// informational: no tray "action needed" badge (there's nothing to click
  /// through to fix) and no error sound (nothing actually failed from the
  /// user's point of view — their text still landed).
  void _notifySmartModeFallback() {
    unawaited(
      ref
          .read(systemAttentionServiceProvider)
          .requestAttention(
            kind: AttentionKind.smartModeFallback,
            title: 'WhisPaste: Smart Mode übersprungen',
            body:
                'Die Nachbearbeitung konnte nicht angewendet werden — der unbearbeitete Text wurde trotzdem eingefügt.',
          ),
    );
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

  /// Aggregated categorical telemetry for a finished pipeline run — the single
  /// per-recording signal. [_PipelineTiming.outcome] is an internal enum string
  /// (no PII); latency is bucketed into its own low-cardinality counter. Both
  /// are tallied in-memory and flushed once at shutdown, never per recording.
  void _trackPipelineOutcome(_PipelineTiming timing, int elapsedMs) {
    final agg = ref.read(telemetrySessionAggregatorProvider);
    agg.count(
      category: 'pipeline',
      action: timing.outcome == 'ok' ? 'success' : 'fail',
      name: timing.outcome,
    );
    agg.count(
      category: 'pipeline',
      action: 'latency',
      name: 'b${_latencyBucketSeconds(elapsedMs)}',
    );
  }

  /// Coarse latency bucket (whole seconds, capped) so no precise timing leaks.
  static int _latencyBucketSeconds(int ms) {
    final s = ms ~/ 1000;
    if (s <= 1) return 1;
    if (s <= 3) return 3;
    if (s <= 5) return 5;
    if (s <= 10) return 10;
    if (s <= 30) return 30;
    return 60;
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
    ref.read(onDeviceEngineLifecycleProvider).stop();
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
    try {
      ref.read(telemetryProvider).trackSettingChange('cloud_stt_provider');
    } catch (e) {
      _log.debug('telemetry failed: $e');
    }
    _oomHandler.reset();
    ref.read(oomRecoveryPendingProvider.notifier).clear();
    ref.read(onDeviceEngineLifecycleProvider).stop();
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
  /// Surfaces a swallowed hotkey press instead of dropping it silently.
  ///
  /// Both abort branches in [startRecording] used to return without any user
  /// feedback whatsoever. During a slow first transcription that window can
  /// last tens of seconds (a captured session: presses at 14:19:05, :19, :52
  /// and :53 all aborted, none of them visible anywhere), and an app that
  /// answers a hotkey with nothing at all is indistinguishable from a broken
  /// one. Throttled via [_busyHintThrottle] so mashing doesn't become spam.
  void _hintPipelineBusy() {
    final now = DateTime.now();
    final last = _lastBusyHintAt;
    if (last != null && now.difference(last) < _busyHintThrottle) return;
    _lastBusyHintAt = now;
    ref.read(recordingInfoProvider.notifier).show('info_pipeline_busy');
  }

  bool _handleSoftPreflight(String errorCode) {
    switch (errorCode) {
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
    ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();

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

    // Block recording while onboarding is active — except for onboarding's
    // own test-recording step, which sets [sandboxTranscriptSink] and relies
    // on this exact preflight/start path to let the user try the hotkey
    // before onboardingCompleted is set.
    if (!settings.onboardingCompleted && sandboxTranscriptSink == null) {
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

    if (settings.onDeviceEngine == OnDeviceEngine.parakeet) {
      if (!parakeet.parakeetModelFilesExistSync()) {
        _log.warning('Preflight FAIL: parakeet model bundle not found');
        return 'stt_model_not_found';
      }
      _log.info('Preflight OK: parakeet model bundle present');
      return null;
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

    _log.info('Preflight OK: model=$modelPath');
    return null;
  }

  /// Checks [transcript] against the single global Snippet-Picker trigger
  /// word (exact match, see [snippetPickerTriggerMatches]) and — on a
  /// match — opens the picker panel near the mouse cursor.
  ///
  /// Returns `true` as soon as the panel is shown, **without** waiting for
  /// the user to pick a snippet (or dismiss the panel) — see
  /// [SnippetPickerController]'s docs on why the dispatch call must return
  /// promptly. The eventual insert happens later, asynchronously, driven by
  /// [SnippetPickerService]'s own event subscription — entirely outside
  /// this pipeline run, and in particular without ever calling
  /// `paster.prime()` again (that's what keeps the paste target captured at
  /// recording start intact while the panel holds keyboard focus).
  Future<bool> _tryDispatchSnippetPicker(
    String sid,
    String transcript,
    AppSettings settings,
  ) async {
    final trigger = settings.behavior.snippetPickerTrigger;
    if (!snippetPickerTriggerMatches(trigger, transcript)) return false;
    final result = await openSnippetPicker(ref, sid);
    // Only `shown` consumes the dictation; `emptyList`/`unavailable` fall
    // back to the normal pipeline (saved + pasted as usual) — the info
    // signal for `emptyList` is already handled inside [openSnippetPicker].
    return result == SnippetPickerShowResult.shown;
  }

  /// In-flight guard for [openSnippetPickerViaHotkey] — set synchronously
  /// before the first `await`, so a second hotkey press landing in the gap
  /// between the busy/already-open checks and [SnippetPickerService.show]
  /// actually flipping `isOpen` (paste-target priming is async and sits in
  /// between) can never open a second panel. Mirrors [_startInFlight]'s
  /// reentrancy-lock idiom.
  bool _snippetPickerHotkeyInFlight = false;

  /// Opens the Snippet-Picker panel from the systemwide Snippet-Picker
  /// hotkey (ticket 26) — functionally identical to what the spoken trigger
  /// word does via [_tryDispatchSnippetPicker]/[openSnippetPicker], except
  /// **without starting any recording, STT run, or history entry**: this is
  /// a one-shot UI action, not a dictation, so it never touches
  /// [RecordingPhase], the microphone, or the overlay.
  ///
  /// Captures the paste target exactly once, right here, before the panel
  /// opens — mirroring [startRecording]'s `paster.prime()` call — because
  /// [SnippetPickerService] itself never primes (see its class doc, updated
  /// for this caller). At key-down the foreign app is still frontmost, so
  /// this is the only correct moment to capture; capturing again on
  /// selection would hit WhisPaste's own window instead.
  ///
  /// Ignored (logged, not silently swallowed) while a recording is in
  /// progress — the two paths would otherwise race for focus and the paste
  /// target — and while the panel is already open.
  Future<void> openSnippetPickerViaHotkey() async {
    if (_snippetPickerHotkeyInFlight) {
      _log.debug('Snippet-Picker hotkey ignored (already opening)');
      return;
    }
    if (!snippetPickerAvailableOnPlatform) {
      _log.info('Snippet-Picker hotkey ignored: unavailable on this platform');
      return;
    }
    final phase = ref.read(recordingProvider).phase;
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        // Smart Mode v2 (ticket 02): a Cleanup pass still owns the pending
        // paste target here — opening the picker now would race it exactly
        // like the transcribing case above.
        phase == RecordingPhase.refining) {
      _log.info('Snippet-Picker hotkey ignored: recording in progress');
      return;
    }
    if (ref.read(snippetPickerServiceProvider.notifier).isOpen) {
      _log.debug('Snippet-Picker hotkey ignored: panel already open');
      return;
    }
    _snippetPickerHotkeyInFlight = true;
    try {
      await ref.read(pasterProvider)?.prime();
      await openSnippetPicker(ref, 'snippet-hotkey');
    } finally {
      _snippetPickerHotkeyInFlight = false;
    }
  }

  /// Captures the paste target once, before the first field of an
  /// interactive snippet starts recording. Individual `templateField`
  /// recordings deliberately skip [pasterProvider]'s `prime()` (see
  /// [startRecording] — "a quick-note target never pastes anywhere"), so
  /// without this call the originally-focused app would never be captured
  /// and [completeInteractiveSnippet] would have nothing to paste into.
  Future<void> primeForInteractiveSnippet() async {
    await ref.read(pasterProvider)?.prime();
  }

  /// Called by `InteractiveSnippetController` once every field of an
  /// interactive snippet has been recorded and composed into [composedText].
  /// Runs the same history-save (exactly one entry for the whole snippet,
  /// never one per field) and clipboard/paste step a regular `clipboard`
  /// recording runs after transcription — without going through the
  /// audio/transcription pipeline itself, since the text is already final.
  Future<void> completeInteractiveSnippet({
    required String composedText,
    required Duration audioDuration,
  }) async {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final saved = await ref
        .read(recordingStoreProvider)
        .save(
          RecordingInput(
            transcript: composedText,
            audioDuration: audioDuration,
            modelId: settings.transcriptionModelId,
            isLocal: settings.sttProviderType.isLocal,
            languageCode: settings.sttLanguageCode,
            // Each field already had replacements applied to it individually
            // (via its own templateField recording's history-save step) —
            // running them again over the composed text (headings included)
            // would risk a heading incidentally matching a trigger phrase.
            applyTextReplacements: false,
            historyMaxEntries: settings.historyMaxEntries,
            wordCount: computeWordCountFast(composedText),
            processingDurationSec: 0,
            recordDailyStat: false,
          ),
        );

    final action = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
    );
    switch (action) {
      case AfterTranscriptionAction.nothing:
        return;
      case AfterTranscriptionAction.clipboard:
        await _copyTranscriptToClipboard(saved.processedTranscript);
      case AfterTranscriptionAction.paste:
        await _pasteTranscript(saved.processedTranscript, settings);
      case AfterTranscriptionAction.clipboardAndPaste:
        await _copyTranscriptToClipboard(saved.processedTranscript);
        await _pasteTranscript(saved.processedTranscript, settings);
    }
  }

  Future<String?> _saveToHistory(
    String transcript,
    Duration audioDuration,
    AppSettings settings,
    int processingDurationSec,
    String wavPath,
  ) async {
    try {
      final store = ref.read(recordingStoreProvider);
      final wordCount = computeWordCountFast(transcript);
      // A quick note already lives in Notes — it must not also land in
      // Verlauf (see _handleAfterTranscription's quickNote branch below,
      // which appends to the note instead of clipboard/paste). A template
      // field is one piece of a still-in-progress interactive snippet — only
      // the final composed result (assembled by
      // `InteractiveSnippetController`) gets its own single history entry,
      // never the individual fields.
      final target = ref.read(recordingTargetProvider);
      final isQuickNote = target == RecordingTarget.quickNote;
      final isTemplateField = target == RecordingTarget.templateField;

      final saved = await store.save(
        RecordingInput(
          transcript: transcript,
          audioDuration: audioDuration,
          modelId: settings.transcriptionModelId,
          isLocal: settings.sttProviderType.isLocal,
          languageCode: settings.sttLanguageCode,
          applyTextReplacements: settings.textReplacementsEnabled,
          historyMaxEntries: settings.historyMaxEntries,
          wordCount: wordCount,
          processingDurationSec: processingDurationSec,
          insertHistoryEntry: !isQuickNote && !isTemplateField,
        ),
      );

      if (isQuickNote) {
        _log.info(
          'Applied text replacements for quick note (not saved to '
          'history)',
        );
      } else if (isTemplateField) {
        _log.info(
          'Applied text replacements for template field (not saved to '
          'history)',
        );
      } else {
        _log.info('Saved entry ${saved.entryId} to history');
      }

      if (saved.trimmedCount > 0) {
        _log.info(
          'Auto-trimmed ${saved.trimmedCount} old entries to stay within '
          '${settings.historyMaxEntries} limit',
        );
      }

      // Debug-only: link the retained WAV to this entry so a diagnosis
      // session can pull the exact audio Whisper received for this
      // transcript. Best-effort — a failure here must not fail the save
      // that already succeeded above. No-op for a quick note: there is no
      // history entry to link the audio to. Takes priority over the
      // user-facing retention setting below — a live diagnosis session
      // wants every WAV kept in place, uncapped, not rotated away.
      if (kRetainDebugAudio && !isQuickNote && !isTemplateField) {
        await _linkDebugAudioAttachment(saved.entryId, wavPath);
      } else if (settings.privacy.retainRecentAudio &&
          !isQuickNote &&
          !isTemplateField) {
        await _retainRecentAudio(saved.entryId, wavPath);
      }

      // Refresh analytics dashboard so counters update immediately.
      ref.invalidate(analyticsProvider);

      return saved.processedTranscript;
    } on Exception catch (e) {
      _log.error('Failed to save to history: $e');
      return null;
    }
  }

  /// Debug-only helper for [_saveToHistory]: records [wavPath]'s size and
  /// links it to [entryId] via [HistoryDatabase.insertAudioAttachment].
  /// Swallows its own errors — a missing/unreadable WAV must not fail the
  /// already-successful history save.
  Future<void> _linkDebugAudioAttachment(String entryId, String wavPath) async {
    try {
      final file = File(wavPath);
      if (!await file.exists()) return;
      final sizeBytes = await file.length();
      await ref
          .read(historyDatabaseProvider)
          .insertAudioAttachment(
            entryId: entryId,
            filePath: wavPath,
            sizeBytes: sizeBytes,
          );
      _log.info('kRetainDebugAudio: linked $wavPath to entry $entryId');
    } on Exception catch (e) {
      _log.warning('kRetainDebugAudio: failed to link WAV attachment: $e');
    }
  }

  /// User-facing counterpart to [_linkDebugAudioAttachment]: moves the WAV
  /// out of the volatile capture directory into [retainedAudioDir] (so
  /// `AudioService.cleanupStaleFiles`'s startup sweep can't delete it),
  /// links it to [entryId], then enforces the rotating cap so at most the
  /// 20 most recent retained WAVs survive. Best-effort — a failure here
  /// must not fail the save that already succeeded above. No-op for a
  /// quick note: there is no history entry to link the audio to.
  Future<void> _retainRecentAudio(String entryId, String wavPath) async {
    try {
      final source = File(wavPath);
      if (!await source.exists()) return;

      final dir = Directory(retainedAudioDir());
      if (!await dir.exists()) await dir.create(recursive: true);
      final destPath = p.join(dir.path, p.basename(wavPath));

      File dest;
      try {
        dest = await source.rename(destPath);
      } on FileSystemException {
        // Capture dir and app-data dir can be on different filesystems
        // (e.g. temp on a RAM disk) — rename() can't cross that boundary.
        dest = await source.copy(destPath);
        await source.delete();
      }

      try {
        final sizeBytes = await dest.length();
        final db = ref.read(historyDatabaseProvider);
        await db.insertAudioAttachment(
          entryId: entryId,
          filePath: dest.path,
          sizeBytes: sizeBytes,
        );

        final evicted = await db.enforceAudioAttachmentCap();
        for (final path in evicted) {
          await ref.read(audioServiceProvider.notifier).cleanupFile(path);
        }

        _log.info('Retained WAV for entry $entryId at ${dest.path}');
      } on Exception {
        // The row insert (source of truth for rotation) failed — without
        // it enforceAudioAttachmentCap can never see or evict this file,
        // so it would otherwise leak in retainedAudioDir forever.
        try {
          await dest.delete();
        } on Exception catch (cleanupError) {
          _log.warning('Failed to clean up orphaned WAV: $cleanupError');
        }
        rethrow;
      }
    } on Exception catch (e) {
      _log.warning('Failed to retain recent audio: $e');
    }
  }

  void _cancelAmplitude() {
    _guardSub?.cancel();
    _guardSub = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  /// Persists the hotkey→text end-to-end latency for this session, if a
  /// hotkey press t₀ was captured at [startRecording].
  ///
  /// Consumes [_hotkeyPressedAtForLatencyKpi] (resets to null) so a stray
  /// re-entry cannot double-record the same sample. No-op when no press was
  /// captured (e.g. recording was started from the UI, not the hotkey).
  /// Best-effort — a DB failure here must not fail the pipeline, which has
  /// already delivered the text to the user.
  Future<void> _persistHotkeyLatencyIfPending(String sid) async {
    final hotkeyAt = _hotkeyPressedAtForLatencyKpi;
    _hotkeyPressedAtForLatencyKpi = null;
    if (hotkeyAt == null) return;

    final now = DateTime.now();
    final latencyMs = now.difference(hotkeyAt).inMilliseconds;
    if (latencyMs < 0) return; // clock-skew guard

    try {
      await ref
          .read(historyDatabaseProvider)
          .recordHotkeyLatency(recordedAt: now, latencyMs: latencyMs);
    } on Exception catch (e) {
      _log.warning('[$sid] Failed to persist hotkey→text latency: $e');
    }
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
    // Phase guard: only act while actually recording.
    // A dead-mic event can arrive in a race window after transcription has
    // already started (the guard stream can queue a sample before
    // _cancelAmplitude() tears it down). Acting here would abort a legitimate
    // transcription in flight — silent data loss.
    final phase = ref.read(recordingProvider).phase;
    if (phase != RecordingPhase.recording) {
      _log.debug('Dead-mic guard skipped — phase is $phase (not recording)');
      return;
    }

    // Re-entry guard: a concurrent stop (regular or auto-stop) may already be
    // driving the pipeline. Don't race against it.
    if (_stopInFlight) {
      _log.debug('Dead-mic guard skipped — stop already in flight');
      return;
    }
    _stopInFlight = true;

    // Guard-fire is expected user behaviour (no microphone input), not a crash.
    // Goes in at info level so the AppLogger pipeline turns it into a Sentry
    // breadcrumb — context for any later real error, but not a standalone issue.
    _log.info('guard-fire: dead-mic (no audio detected before timeout)');
    try {
      _cancelAmplitude();
      final audioNotifier = ref.read(audioServiceProvider.notifier);
      await audioNotifier.stopRecording();
      ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
      _stateMachine.transition(
        RecordingIntent.fail,
        errorMessage: 'recording_guard_failed',
      );
    } on Exception catch (e) {
      _log.warning('Error during dead-mic cleanup: $e');
      ref.read(onDeviceEngineLifecycleProvider).notifyRecordingStopped();
      _stateMachine.transition(
        RecordingIntent.fail,
        errorMessage: 'recording_guard_failed',
      );
    } finally {
      _stopInFlight = false;
    }
  }

  /// Auto-stop triggered: stop recording and run transcription pipeline.
  Future<void> _handleAutoStop() async {
    // Phase guard: only auto-stop while actually recording. A stale
    // SilenceAutoStop / DurationLimitReached event can arrive after the
    // pipeline already moved on (e.g. to done); acting on it would drive a
    // no_audio capture and a fail transition the state machine rejects.
    // Mirrors the dead-mic guard.
    final phase = ref.read(recordingProvider).phase;
    if (phase != RecordingPhase.recording) {
      _log.debug('Auto-stop guard skipped — phase is $phase (not recording)');
      return;
    }

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
    if (settings.sound.soundVolume <= 0) return;
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

      if (settings.onDeviceEngine == OnDeviceEngine.parakeet) {
        if (!parakeet.parakeetModelFilesExistSync()) return;
        await ref.read(onDeviceEngineLifecycleProvider).prewarm();
        return;
      }

      // Only pre-warm when the model is already downloaded.
      final modelPath = sttModelPath(settings.effectiveModelId);
      if (modelPath == null || !await File(modelPath).exists()) return;

      await ref.read(onDeviceEngineLifecycleProvider).prewarm();
    } on Exception catch (e) {
      _log.warning('STT pre-warm failed (non-fatal): $e');
    }
  }

  Future<bool> _copyTranscriptToClipboard(String transcript) async {
    try {
      await AppClipboard.setText(transcript).timeout(
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
    // Onboarding's test-recording step redirects the transcript to a local
    // sandbox field instead of the real clipboard/paste path. See
    // [sandboxTranscriptSink].
    final sink = sandboxTranscriptSink;
    if (sink != null) {
      sink(transcript);
      return;
    }

    if (ref.read(recordingTargetProvider) == RecordingTarget.quickNote) {
      await _appendToQuickNote(transcript);
      return;
    }

    // A template field's transcript is picked up by
    // `InteractiveSnippetController` from `RecordingState.transcript` once
    // this recording completes — it is neither copied to the clipboard nor
    // pasted anywhere on its own (only the composed, whole-snippet result
    // is, once every field is done).
    if (ref.read(recordingTargetProvider) == RecordingTarget.templateField) {
      return;
    }

    // resolveAfterTranscriptionAction downgrades paste/type actions to
    // clipboard-only ONLY if kAutoPasteSupported is false — currently true
    // unconditionally, MAS included (see build_config.dart): the sandboxed
    // Mac App Store build types via the sandbox-compatible PostEvent TCC
    // service instead of the Accessibility API, so simulated text-insertion
    // works there too, not just on the Developer-ID build.
    final action = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
    );

    switch (action) {
      case AfterTranscriptionAction.nothing:
        return;
      case AfterTranscriptionAction.clipboard:
        await _copyTranscriptToClipboard(transcript);
        ref
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'insertion', action: 'clipboard');
        return;
      case AfterTranscriptionAction.paste:
        await _pasteTranscript(transcript, settings);
        ref
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'insertion', action: 'auto_paste');
        return;
      case AfterTranscriptionAction.clipboardAndPaste:
        await _copyTranscriptToClipboard(transcript);
        await _pasteTranscript(transcript, settings);
        ref
            .read(telemetrySessionAggregatorProvider)
            .count(category: 'insertion', action: 'auto_paste');
        return;
    }
  }

  /// Appends [transcript] to the quick note, bypassing clipboard/paste
  /// entirely. Zero-config: if no note is marked — or the marked note is
  /// trashed or no longer exists (both surface as `null` from
  /// [HistoryDatabase.getQuickNote]) — creates a fresh note and marks it
  /// first. Prefers [quickNoteLiveEditorOverride] over the direct database
  /// write when one is registered and handles the append (see its doc
  /// comment); always fires [onQuickNoteAppended] on success.
  ///
  /// Awaits [quickNoteEditorFlush] first so the note is read back *after* a
  /// live editor has persisted its pending keystrokes — see that field.
  @visibleForTesting
  Future<void> appendToQuickNote(String transcript) =>
      _appendToQuickNote(transcript);

  Future<void> _appendToQuickNote(String transcript) async {
    // Must stay ahead of the read below: it is what makes the row current.
    await quickNoteEditorFlush?.call();

    final db = ref.read(historyDatabaseProvider);
    var note = await db.getQuickNote();
    if (note == null) {
      note = await db.createNote();
      await db.setQuickNote(note.id);
    }

    final newContent = appendToQuickNoteContent(note.content, transcript);

    final override = quickNoteLiveEditorOverride;
    final handled = override != null && override(note.id, newContent);
    if (!handled) {
      await db.updateNoteContent(note.id, newContent);
    }

    onQuickNoteAppended?.call(note.id);
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
        // Two distinct causes look identical from the paste outcome alone,
        // so branch on the shared [PasteCapabilityNotifier.needsRestart]
        // signal — the same one the settings indicator and onboarding use —
        // before choosing the click target. A genuinely-missing grant needs
        // the Settings pane; a grant WhisPaste already handed the user off to
        // that still reads as missing is the known stale in-process view
        // (Settings would show the toggle already on, which reads as "nothing
        // to do here" and just re-confuses the user). That case needs a
        // restart, not another trip to Settings. Routing the grant click
        // through the notifier's `openAccessibilitySettings` records the
        // handoff, so the *next* failure/surface correctly resolves to
        // restart instead of sending the user to Settings a second time.
        final capNotifier = ref.read(pasteCapabilityNotifierProvider.notifier);
        final staleGrant = capNotifier.needsRestart;
        // Third arm, ahead of the plain Settings deep-link: on a live-probe
        // build a missing permission can be a TCC entry pinned to a binary
        // that no longer exists, and Settings then shows the toggle already
        // ON — "nichts zu tun" — which is precisely the dead end the user
        // reported. Clearing the entry first makes the row honest before the
        // user ever gets there. See
        // [PasteCapabilityNotifier.grantRequiresEntryReset] for why this is
        // unconditional rather than gated on detected staleness.
        final resetEntryFirst =
            !staleGrant && capNotifier.grantRequiresEntryReset;
        // Name the chosen arm in the log: all three arms report the same
        // `permissionMissing` outcome, so without this a support log cannot
        // tell which recovery the user was actually offered.
        _log.info(
          'Auto-paste permission recovery arm: '
          '${staleGrant
              ? 'restart'
              : resetEntryFirst
              ? 'reset-entry-then-grant'
              : 'open-settings'}',
        );
        _reportPasteFailure(
          outcome: PasteOutcome.permissionMissing,
          kind: AttentionKind.pasteBlockedPermission,
          title: staleGrant
              ? 'WhisPaste: Neustart nötig'
              : 'WhisPaste: Auto-Einfügen blockiert',
          body: staleGrant
              ? 'Die Berechtigung wurde erteilt, aber WhisPaste läuft noch mit dem alten Stand. Klicke hier, um WhisPaste neu zu starten.'
              : resetEntryFirst
              ? 'WhisPaste braucht die Berechtigung, Text in andere Apps einzufügen — macOS nennt sie „Bedienungshilfen“. Klicke hier: WhisPaste räumt einen möglicherweise veralteten Eintrag weg und lässt macOS neu fragen.'
              : 'WhisPaste braucht die Berechtigung, Text in andere Apps einzufügen — macOS nennt sie „Bedienungshilfen“. Klicke hier oder das Tray-Icon, um die Systemeinstellungen zu öffnen.',
          trayLabel: staleGrant
              ? 'Auto-Einfügen blockiert — Neustart nötig'
              : 'Auto-Einfügen blockiert — Systemeinstellungen öffnen',
          // The arms above pick the *wording*; the click itself re-resolves
          // the arm when it fires. A notification can sit unread and the tray
          // entry waits indefinitely, so the state at click time is the one
          // that counts.
          onClick: capNotifier.runMissingPermissionRecovery,
          // Own tray key, so the persistent surface runs this recovery too
          // instead of the default "open the after-transcription settings"
          // jump — being sent to a settings page to hunt for a fix is the
          // dead end this whole branch exists to remove.
          trayMenuItemKey: kTrayPastePermissionActionNeededKey,
          // Own tray key, so the persistent surface runs this recovery too
          // instead of the default "open the after-transcription settings"
          // jump — being sent to a settings page to hunt for a fix is the
          // dead end this whole branch exists to remove.
        );
        return false;
      case PasteOutcome.elevationBlocked:
        _log.warning(
          'Paste failed: target window runs elevated, WhisPaste does not '
          '(Windows UIPI). Restart WhisPaste as an administrator to paste '
          'into that window.',
        );
        _reportPasteFailure(
          outcome: PasteOutcome.elevationBlocked,
          kind: AttentionKind.pasteBlockedElevation,
          title: 'WhisPaste: Auto-Einfügen blockiert',
          body:
              'Die Ziel-App läuft mit Administratorrechten. Starte WhisPaste ebenfalls als Administrator, um dort einzufügen.',
          trayLabel: 'Auto-Einfügen blockiert — Administrator nötig',
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
    void Function()? onClick,
    String trayMenuItemKey = kTrayPasteActionNeededKey,
  }) {
    ref.read(pasteFailureNotifierProvider.notifier).report(outcome);

    // Dezenter Fehlerton — hörbar auch, wenn der Nutzer beim Diktieren nicht
    // auf den Bildschirm schaut. Respektiert Sound-Volume + errorSound-Setting
    // (siehe SoundFeedbackService.playError).
    try {
      ref.read(soundFeedbackProvider.notifier).playError();
    } catch (e) {
      _log.warning('Error sound failed: $e');
    }

    // Fire out-of-app surfaces (dock-bounce + native notification + tray
    // badge) so the user sees the failure even when the main window is
    // hidden — the common case for WhisPaste. Callers that promise a click
    // target in their title/body pass [onClick] so the click actually does
    // that instead of just foregrounding the app.
    unawaited(
      ref
          .read(systemAttentionServiceProvider)
          .requestAttention(
            kind: kind,
            title: title,
            body: body,
            onClick: onClick,
          ),
    );
    try {
      ref
          .read(trayServiceProvider.notifier)
          .setActionNeeded(
            label: trayLabel,
            tooltip: 'WhisPaste — $trayLabel',
            menuItemKey: trayMenuItemKey,
          );
    } on Exception catch (e) {
      _log.warning('Tray action-needed update failed', e);
    }
  }

  void _clearPasteAttention() {
    unawaited(ref.read(systemAttentionServiceProvider).clearAttention());
    try {
      ref.read(trayServiceProvider.notifier).clearActionNeeded();
    } on Exception catch (e) {
      _log.debug('clearActionNeeded failed', e);
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
/// and the active [OnDeviceEngineLifecycle] adapter.
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

/// Riverpod notifier that composes all STT sub-modules.
///
/// Re-exports [SttStatus] and [SttServerState] so external consumers can
/// import from this single file instead of hunting through the subsystem.
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart'
    show Breadcrumb, Sentry, SentryLevel;

import '../../core/app_info.dart' as app;
import '../../core/config/punctuation_priming_prompts.dart';
import '../../core/config/settings_enums.dart' show OnDeviceEngine;
import '../../core/config/settings_provider.dart';
import '../../core/config/whisper_languages.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../core/logging/crash_reporter.dart';
import '../../core/recording/recording_state.dart'
    show
        SttServerState,
        RecordingPhase,
        isDictationBusy,
        recordingPhaseProvider,
        recordingProvider;
import '../../core/recording/transcription_budget.dart';
import '../audio/pcm_wav_codec.dart' show wavFileMatches;
import '../dictionary/vocabulary_terms.dart' show vocabularyPrompt;
import '../hardware_info_service.dart' as hw;
import '../model_download_service.dart';
import '../path_service.dart';
import 'benchmark_freshness.dart';
import 'idle_unload_policy.dart';
import 'inference_client_rejected.dart';
import 'inference_request_validator.dart';
import 'live_preview/live_transcript_previewer.dart';
import 'memory_pressure.dart';
import 'prompt_token_budget.dart';
import 'stt_benchmark.dart' show SttBenchmark;
import 'stt_benchmark_run.dart';
import 'transcription_deadline.dart';
import 'tail_confidence.dart';
import 'transcript_hallucination_filter.dart';
import 'transcript_hygiene.dart';
import 'wav_header_repair.dart';
import 'engine_load_triage.dart';
import '../file_verification_service.dart';
import 'recovery_toast_notifier.dart';
import 'whisper/cuda_ab.dart';
import 'whisper/cuda_pack.dart';
import 'whisper/gpu_load_crash_guard.dart';
import '../gpu_probe_process.dart';
import 'whisper/gpu_probe.dart';
import 'whisper/vram_gate.dart';
import 'whisper/whisper_engine.dart';
import 'whisper/whisper_ffi_engine.dart' show defaultWhisperVadModelPath;
import 'whisper/whisper_isolate_engine.dart';
import 'whisper/whisper_resilience_policy.dart';

// Re-export for external consumers.
export '../../core/recording/recording_state.dart' show SttServerState;
export 'stt_exit_classifier.dart' show SttExitKind, classifySttExitCode;
export 'stt_gpu_fallback_policy.dart' show SttGpuFallbackPolicy;

// ---------------------------------------------------------------------------
// SttStatus (local copy so stt_bundle.dart can re-export without coupling
// to the legacy stt_service.dart)
// ---------------------------------------------------------------------------

/// Immutable snapshot of the STT service.
class SttStatus {
  const SttStatus({
    this.serverState = SttServerState.stopped,
    this.port = 0,
    this.modelId = '',
    this.errorMessage,
    this.startingSince,
    this.isBenchmarking = false,
    this.benchmarkingTier,
    this.cpuFallbackActive = false,
    this.backend,
    this.pendingModelId,
    this.restartNeeded = false,
  });

  final SttServerState serverState;

  /// Model whose switch is deferred until a running native call finishes.
  final String? pendingModelId;

  /// A native call still runs on this engine past its cap, so the engine
  /// cannot be freed or reused in this session. Settings asks for a restart.
  final bool restartNeeded;

  /// Legacy HTTP-era field, permanently `0` since the Issue 03 cutover to the
  /// in-process [WhisperEngine] — there is no localhost port to bind. Kept
  /// (rather than removed) so the existing test fixtures that construct
  /// `SttStatus(..., port: 9999)` keep compiling unchanged; no production
  /// code reads it besides [toString] and [endpoint] (also unused — see
  /// issue 09's `endpoint`/`port` decision).
  final int port;
  final String modelId;
  final String? errorMessage;

  /// When the server entered the [SttServerState.starting] state.
  final DateTime? startingSince;

  /// Whether a benchmark is currently running for this model.
  final bool isBenchmarking;

  /// Which tier is currently being benchmarked, if any.
  final QualityTier? benchmarkingTier;

  /// True when the GPU crashed and the server restarted on CPU automatically.
  final bool cpuFallbackActive;

  /// The compute backend the currently loaded model actually runs on
  /// ([WhisperEngineStatus.backend] at the moment the load/warmup last
  /// completed), or `null` before any model has ever loaded. Distinct from
  /// [cpuFallbackActive]: that flag only covers the load-time GPU→CPU
  /// retry, while this reflects the real backend regardless of *why* it
  /// ended up there (including hardware that was never GPU-capable).
  final WhisperBackend? backend;

  bool get isReady => serverState == SttServerState.ready;

  /// Legacy HTTP-era getter — dead since Issue 03's cutover to the in-process
  /// [WhisperEngine] (no server, no port, nothing listens on this URL). Has
  /// zero production callers; kept as a documented no-op rather than removed
  /// (issue 09's `endpoint`/`port` decision) to avoid an unrelated ripple.
  String get endpoint => 'http://127.0.0.1:$port';

  SttStatus copyWith({
    SttServerState? serverState,
    int? port,
    String? modelId,
    String? errorMessage,
    DateTime? startingSince,
    bool? isBenchmarking,
    QualityTier? benchmarkingTier,
    bool clearBenchmarkingTier = false,
    bool? cpuFallbackActive,
    WhisperBackend? backend,
    String? pendingModelId,
    bool clearPendingModelId = false,
    bool? restartNeeded,
  }) {
    return SttStatus(
      serverState: serverState ?? this.serverState,
      port: port ?? this.port,
      modelId: modelId ?? this.modelId,
      errorMessage: errorMessage ?? this.errorMessage,
      startingSince: startingSince ?? this.startingSince,
      isBenchmarking: isBenchmarking ?? this.isBenchmarking,
      benchmarkingTier: clearBenchmarkingTier
          ? null
          : (benchmarkingTier ?? this.benchmarkingTier),
      cpuFallbackActive: cpuFallbackActive ?? this.cpuFallbackActive,
      backend: backend ?? this.backend,
      pendingModelId: clearPendingModelId
          ? null
          : (pendingModelId ?? this.pendingModelId),
      restartNeeded: restartNeeded ?? this.restartNeeded,
    );
  }

  @override
  String toString() =>
      'SttStatus($serverState, port=$port, model=$modelId, '
      'benchmarking=$isBenchmarking, cpuFallback=$cpuFallbackActive, '
      'backend=$backend)';
}

// ---------------------------------------------------------------------------
// Pure helpers (top-level, testable)
// ---------------------------------------------------------------------------

/// Returns `true` when [fileSizeBytes] is suspiciously small for a valid GGML
/// model, indicating a truncated or failed download.
bool isSttModelFileTooSmall(
  int fileSizeBytes, {
  int minModelBytes = 10 * 1024 * 1024,
}) => fileSizeBytes < minModelBytes;

// ---------------------------------------------------------------------------
// SttServerStateNotifier
// ---------------------------------------------------------------------------

/// Riverpod [Notifier] that drives the in-process [WhisperEngine] behind a
/// single [SttStatus] surface.
///
/// This is the public entry point for the STT subsystem. All callers use
/// [localSttBundleProvider] since issue 15.
///
/// The engine seam replaced the former `whisper-server` subprocess + HTTP
/// transport (Issue 03). The subprocess-era GPU-DLL-gate and CUDA-OOM/exit-code
/// classification had no equivalent against an in-process engine and were
/// removed, along with the rest of the subprocess-runtime stack (`ProcessRunner`,
/// `LocalSttServer`, `SttHealthProbe`, `SttWarmLivenessPolicy`, `SubprocessGuard`)
/// in Issue 08. The `ServerBinaryRecovery` machinery (and the whole server-binary
/// download/manifest stack) was retired in Issue 07. Real backend selection
/// (Metal/CUDA/Vulkan) is Issue 04; OOM/retry resilience against FFI error
/// codes is Issue 05.
class SttServerStateNotifier extends Notifier<SttStatus> {
  static final _log = AppLogger('SttServerState');

  /// Pre-flight whitelist: the full 99-language catalog of the bundled
  /// multilingual Whisper models ([whisperLanguages]). `'auto'` bypasses
  /// the whitelist inside the validator. Until June 2026 this was a
  /// hard-coded en/de/fr/es subset, which wrongly rejected every other
  /// language the models support (store review: Russian).
  static final Set<String> _whisperSupportedLanguages = whisperLanguageCodes;

  /// Defensive pre-flight char-length backstop against obvious-garbage
  /// requests (e.g. a corrupted settings value) — NOT the real prompt
  /// budget. The real, binding ceiling is whisper.cpp's own *tokenized*
  /// `initial_prompt` limit, far below this: ~[promptTokenBudget] tokens,
  /// enforced by [_resolveEffectivePrompt] via [PromptTokenCounter]/
  /// [truncatePromptToTokenBudget] before the prompt ever reaches the
  /// validator below. A prompt that passes this char check can still have
  /// been silently truncated to fit the real token budget — that is
  /// intentional (partial biasing beats a hard reject) and is why this
  /// constant stays generous rather than tight.
  static const int _promptCharLimit = 1024;

  /// Effective token ceiling whisper.cpp applies to the tokenized
  /// `initial_prompt`, derived from the native formula (`whisper.cpp`
  /// `whisper_full_with_state`): `max(1, min(n_max_text_ctx,
  /// whisper_n_text_ctx(ctx) / 2) - 1)`. WhisPaste hard-codes
  /// `n_max_text_ctx = 64` ([WhisperFfiEngine._decodeOnce]) and every
  /// bundled ggml model uses the standard `whisper_n_text_ctx(ctx) = 448`
  /// text context, so `min(64, 224) - 1 = 63` is a fixed, not a measured,
  /// value — it moves in lockstep with `n_max_text_ctx` and must be updated
  /// if that ever changes.
  static const int promptTokenBudget = 63;

  /// Exact whisper.cpp token count of [text] with the loaded model, or null
  /// when no model is loaded (or the count fails). The dictionary uses it to
  /// show where the term list stops reaching the recogniser.
  Future<int?> countPromptTokensOrNull(String text) async {
    final engine = _engine;
    if (engine is! PromptTokenCounter) return null;
    try {
      return await (engine as PromptTokenCounter).countPromptTokens(text);
    } catch (e) {
      _log.warning('Prompt token count failed: $e');
      return null;
    }
  }

  /// Test override of the local time budget (#1639). `null` in production:
  /// each decode then gets [localTranscriptionBudget] for its audio length
  /// and the measured speed, extended by progress up to
  /// [localTranscriptionHardCap]. When set, it is the whole budget (no
  /// progress extension), so resilience tests can shrink it to milliseconds.
  @visibleForTesting
  static Duration? stuckGuardTimeout;

  /// How long an overrun decode may take to return after its abort flag was
  /// raised before the engine counts as hung (#1639).
  @visibleForTesting
  static Duration abortGrace = kLocalAbortGrace;

  /// Bound on how long a restart waits for a running transcription.
  static Duration get _restartDrainCap =>
      stuckGuardTimeout ?? const Duration(minutes: 5);

  /// Upper bound on how long [stop] waits for an in-flight [transcribeBytes]
  /// call to drain before unloading the engine anyway (FLUTTER_WHISPASTE-6X).
  /// The race being closed is a millisecond-scale window between the
  /// readiness check and the engine call, not the multi-minute local
  /// budget an already-running inference can take —
  /// reusing that budget here would block app quit (`app.dart`'s
  /// `onWindowClose`) behind an in-flight transcription instead of the
  /// few-second grace this actually needs. Mutable + [visibleForTesting] so
  /// tests can shrink it further.
  @visibleForTesting
  static Duration stopDrainTimeout = const Duration(seconds: 1);

  /// Upper bound on how long a native call may keep the engine busy before a
  /// model switch, unload or new decode gives up waiting. Past it the switch
  /// is deferred, never forced, and the engine is not unloaded under the call.
  @visibleForTesting
  static Duration nativeIdleCap = const Duration(seconds: 30);

  /// Bound on how long a final decode waits for a live-preview decode that
  /// is still running (the native engine cannot cancel a decode).
  @visibleForTesting
  static Duration previewDrainCap = const Duration(seconds: 2);

  /// Overrides the idle-unload delay in tests.
  @visibleForTesting
  static Duration? debugIdleUnloadDelay;

  /// Overrides the live-preview tick (2 s in the app) in tests, so a test
  /// does not wait for the first preview decode in real time.
  @visibleForTesting
  static Duration? debugLivePreviewInterval;

  /// Quiet period the dictation pipeline must hold before a deferred
  /// benchmark ([_scheduleBenchmark]) claims the worker, so a rapid follow-up
  /// dictation still wins the queue. Mutable + [visibleForTesting] so tests
  /// don't have to wait it out in real time.
  @visibleForTesting
  static Duration benchmarkIdleDelay = const Duration(seconds: 2);

  /// Clock for the benchmark's timing, so tier-selection tests can script the
  /// measured runtime instead of waiting out a real inference.
  @visibleForTesting
  static Stopwatch Function() benchmarkStopwatch = Stopwatch.new;

  /// Quiet period before the CUDA/Vulkan comparison ([_scheduleCudaAb])
  /// claims the GPU, checked again until nothing else runs.
  @visibleForTesting
  static Duration cudaAbIdleDelay = const Duration(seconds: 5);

  /// Quiet period after a model change before the debounced pre-warm loads
  /// the new model, so a burst of switches loads only the last one. Mutable +
  /// [visibleForTesting] so lifecycle tests let the pre-warm race in without
  /// waiting it out in real time.
  @visibleForTesting
  static Duration modelChangeDebounce = const Duration(milliseconds: 500);

  /// Upper bound on automatic retries of a transient transcription failure
  /// before the error is surfaced (internal-notes §3.3 — "bis zu 3 Wiederholungen").
  static const int _maxTranscribeRetries = 3;

  /// Pure decision policy for FFI-era transcription failures (CPU-fallback).
  static const _resiliencePolicy = WhisperResiliencePolicy();

  String? _activeModel;
  Timer? _idleTimer;
  String? _lastPrompt;
  DateTime? _lastPromptTime;
  static const _promptExpiry = Duration(minutes: 10);
  bool _idleExtended = false;

  /// True while a dictation's audio capture is live. Set by
  /// [notifyRecordingStarted] and cleared at capture end. Captures cannot
  /// overlap, so one flag is enough: a decode that runs while a new capture
  /// is live deliberately uses reduced threads.
  bool _isRecordingActive = false;

  /// Post-load benchmark waiting for the dictation pipeline to go quiet —
  /// see [_scheduleBenchmark]. Null when nothing is pending.
  String? _pendingBenchmarkModelId;
  Timer? _benchmarkDeferTimer;
  // Bumped by stop(): a freshness check started before stop() must not queue
  // a benchmark for the engine that stop() just retired.
  int _benchmarkGeneration = 0;

  /// CUDA/Vulkan comparison waiting for a quiet pipeline (#1670, see
  /// [_scheduleCudaAb]). Null when nothing is pending.
  String? _pendingCudaAbModelId;
  Timer? _cudaAbTimer;
  bool _cudaAbRunning = false;

  /// Number of [transcribeBytes] calls currently holding the worker. Covers
  /// the request paths that never touch [notifyRecordingStarted] (voice
  /// notes, re-transcription from the history), which [_isRecordingActive]
  /// alone would miss.
  int _transcribeInFlight = 0;

  /// Set when a load skipped its warm-up and its GPU crash-guard marker is
  /// still pending; cleared by the first real inference that completes.
  bool _crashProofPending = false;

  /// Set once a dictation that fell back to the CPU after a GPU failure
  /// finished successfully: the next model load tries the GPU again (#404)
  /// instead of staying on the CPU engine until the app restarts.
  bool _gpuRetryAfterCpuRun = false;

  /// Open while a failed GPU decode is being recovered (rebuild or CPU swap).
  /// Between the failure and the recovery's native call the busy count is
  /// zero, so a waiting second dictation would otherwise slip through
  /// [_awaitNativeGate] onto the dead context (#404).
  Completer<void>? _gpuRecovery;

  /// Crash-streak key of the GPU load that still has to prove itself with a
  /// real transcription before its streak may be reset. Null when the load
  /// was CPU-only, abandoned for CPU, or its warm-up failed.
  String? _crashStreakResetKey;

  /// True while [_engine] is the CPU engine only because the active model
  /// does not fit the detected GPU VRAM (see [_applyVramGate]).
  bool _vramGatedEngine = false;

  /// True while [runBenchmark] measures its tiers; suppresses the automatic
  /// post-load benchmark for the models that run loads.
  bool _benchmarkSuiteActive = false;

  /// Resolved once [_transcribeInFlight] drops back to zero. Lets [stop]
  /// wait out a request already past the [transcribeBytes] readiness check
  /// before freeing the native engine — see [stop] (FLUTTER_WHISPASTE-6X).
  Completer<void>? _drainCompleter;

  /// Native calls (final decode, live preview, model load) that have not
  /// returned yet. Counted on the native future itself, so a Dart-side
  /// stuck-budget timeout does not hide a call still running in native code.
  int _nativeBusy = 0;
  int _nativePreviewBusy = 0;

  /// Completed when [_nativeBusy] drops to zero. Waiters are the decode
  /// gate, the stop path, the idle unload and a deferred model switch.
  Completer<void>? _nativeIdle;

  /// An engine detached at the cap while its native call still runs. It is
  /// unloaded once that call returns, by [_onNativeIdle] only.
  WhisperEngine? _retiredEngine;

  /// Set by an idle timer that fired during a native call; the unload runs
  /// when the native calls have returned.
  bool _unloadWhenIdle = false;

  /// Set when the stuck guard gave up on a decode whose native call is still
  /// running. A further decode then waits only [previewDrainCap] instead of
  /// [nativeIdleCap] (fail fast). Cleared once no native call runs.
  bool _engineMarkedStuck = false;

  /// Multiplier on the local budget after decodes that ran out of it (1, 2,
  /// 4). Doubles on each overrun and resets after a decode that finished, so
  /// the retry of parked audio does not hit the same wall (#1639).
  int _budgetBoost = 1;

  /// Benchmark RTF of [_measuredRtfModel] on [_measuredRtfBackend], kept from
  /// the last benchmark or freshness check. Feeds [localTranscriptionBudget].
  double? _measuredRtf;
  String? _measuredRtfModel;
  String? _measuredRtfBackend;

  /// Current budget multiplier, for tests.
  @visibleForTesting
  int get debugBudgetBoost => _budgetBoost;

  /// Model switch deferred because a native call outlived [nativeIdleCap].
  String? _deferredModelChangeId;

  /// Bumped by each model-change request: a waiting switch that is superseded
  /// by a newer one stops instead of loading its model.
  int _modelChangeGeneration = 0;

  /// Set when a retired engine was unloaded on release, so a stop that was
  /// waiting for the same native call does not unload it a second time.
  bool _unloadedOnRelease = false;

  /// The stop in progress; a second caller shares its acknowledgement.
  Future<void>? _pendingStop;

  /// True while [build] subscribes to its providers. A listener can fire
  /// during that subscription, before [state] exists, so it must not reach
  /// [_transition] (see the engine listener in [build]).
  bool _building = false;

  Completer<void>? _startCompleter;
  final Set<String> _modelLoadFailedIds = {};
  Timer? _modelChangeDebounce;
  Future<void>? _modelChangePrewarm;

  /// The most recent debounced pre-warm after a model change, once its
  /// debounce has fired; `null` before that. Lets tests await the pre-warm
  /// itself instead of sleeping past it.
  @visibleForTesting
  Future<void>? get debugModelChangePrewarm => _modelChangePrewarm;

  // Nullable rather than `late final`: [FakeSttService]-style test doubles
  // override [build] entirely (skipping the assignment below) while
  // inheriting [stop] unmodified — a `late final` throws
  // `LateInitializationError` from `stop()` in that shape. Real callers
  // always go through [build] first (Riverpod builds before any method is
  // reachable), so `_engine!` is safe at every other call site.
  WhisperEngine? _engine;

  /// Live/partial-transcript stream of the currently active engine (ticket
  /// 11), or `null` if that engine doesn't support it (see
  /// [PartialTranscriptSource]'s doc comment — e.g. no engine loaded yet, or
  /// a future non-whisper local engine). Read fresh on every access rather
  /// than cached: the CPU-fallback path (see [_downgradeToCpuFallback]-style
  /// call sites around `_engine = cpuEngine`) can swap [_engine] to a
  /// different instance mid-session, and a stale stream reference would
  /// silently stop emitting.
  Stream<String>? get partialTranscriptStream {
    final e = _engine;
    if (e is PartialTranscriptSource) {
      return (e as PartialTranscriptSource).partialTranscript;
    }
    return null;
  }

  // ── Live-transcript-DURING-recording preview (live-transcript-streaming
  // ticket) ──────────────────────────────────────────────────────────────

  /// Owns the sliding-window buffering + trigger/debounce logic (see
  /// `live_transcript_previewer.dart`). `null` whenever the feature is
  /// inactive — either the setting is off, or [_engine] doesn't support
  /// [LivePreviewEngine] — so [notifyRecordingStarted]/[feedLivePreviewPcm]
  /// never allocate/compute anything in that case (the performance
  /// guarantee the toggle promises).
  LiveTranscriptPreviewer? _livePreview;

  /// Broadcast stream of live-preview text emitted WHILE a recording is
  /// still in progress, or `null` when the feature is currently inactive.
  /// [FloatingOverlayService] listens to this only during
  /// [RecordingPhase.recording] — distinct from [partialTranscriptStream],
  /// which only ever fires once a recording has stopped and its batch
  /// decode is under way.
  Stream<String>? get livePreviewStream => _livePreview?.preview;

  /// Starts the during-recording live-preview pipeline if — and only if —
  /// [enabled] is true and the active engine supports it. Called from
  /// [notifyRecordingStarted] with the current
  /// `AppSettings.wantsLivePreview` value (option on, local whisper, a size
  /// that paints the text while recording); a caller that never
  /// passes `true` here (setting off) never touches [LivePreviewEngine] at
  /// all — no native state is allocated, no timer starts.
  void _maybeStartLivePreview(bool enabled) {
    if (!enabled || !state.isReady) return;
    final engine = _engine;
    if (engine is! LivePreviewEngine) return;
    final e = engine as LivePreviewEngine;

    _livePreview?.dispose();
    final previewer = LiveTranscriptPreviewer(
      decode: (samples) =>
          _nativeCall(() => e.decodeLivePreview(samples), preview: true),
      triggerInterval:
          debugLivePreviewInterval ?? LiveTranscriptPreviewer.defaultInterval,
    );
    _livePreview = previewer;
    previewer.start();
    unawaited(
      e.startLivePreview().catchError((Object err) {
        _log.warning('Live-preview state init failed: $err');
        previewer.stop();
      }),
    );
  }

  /// Feeds one raw PCM chunk (16-bit mono LE, no WAV header) from the
  /// active recording into the live-preview sliding window. No-op unless
  /// [_maybeStartLivePreview] actually started a previewer for this
  /// recording.
  void feedLivePreviewPcm(Uint8List chunk) {
    _livePreview?.addPcmChunk(chunk);
  }

  /// Tears down the live-preview pipeline (timer + native decode state).
  /// Safe to call unconditionally — including when the feature was never
  /// started — so every recording-ending path (stop, cancel, error) can
  /// call this without first checking whether it applies.
  ///
  /// Only reaches into [LivePreviewEngine.stopLivePreview] (the native
  /// `whisper_free_state` call) when [_livePreview] was actually non-null —
  /// i.e. [_maybeStartLivePreview] actually started it for this recording.
  /// Without that guard this would call into the engine on EVERY
  /// recording-ending path even with `overlayShowLiveTranscript` off,
  /// breaking the performance guarantee the toggle promises (issue's
  /// architecture decision #1 — zero extra native calls while off).
  ///
  /// The native `stopLivePreview()` below is fire-and-forget on purpose: it
  /// only frees preview state. Ordering against the final decode is not
  /// handled here; the decode gate [_awaitNativeGate] waits for a preview
  /// decode still in flight (bounded by [previewDrainCap]) before the engine
  /// is touched.
  void _stopLivePreview() {
    final previewer = _livePreview;
    _livePreview = null;
    if (previewer == null) return;
    previewer.dispose();
    final engine = _engine;
    if (engine is LivePreviewEngine) {
      final e = engine as LivePreviewEngine;
      unawaited(
        e.stopLivePreview().catchError((Object err) {
          _log.warning('Live-preview state teardown failed: $err');
        }),
      );
    }
  }

  @override
  SttStatus build() {
    _building = true;
    _engine = ref.read(whisperEngineProvider);
    // The provider rebuilds when its GPU inputs change (settings finishing
    // their async load, the GPU toggle, detection) and its onDispose shuts
    // the previous engine down. Keeping that instance left `state` ready on
    // a dead engine, so the next dictation failed with
    // whisper_engine_not_loaded (Sentry 120963723) — follow the replacement
    // and reload on next use instead.
    ref.listen<WhisperEngine>(whisperEngineProvider, (_, next) {
      if (identical(next, _engine)) return;
      // Subscribing mounts the engine provider, which can replace the engine
      // right here, during build(). Nothing is loaded yet, so only follow the
      // replacement; stop() would write state that does not exist yet.
      if (_building) {
        _engine = next;
        return;
      }
      _log.info('STT engine replaced — reloading on next use');
      unawaited(stop());
      _engine = next;
    });

    // A freshly installed CUDA pack: load the model on it now, so the
    // comparison with Vulkan (#1670) runs right after the install and not
    // only after the next dictation.
    ref.listen<bool>(cudaPackProvider.select((s) => s.installed), (
      previous,
      next,
    ) {
      if (previous == false && next) unawaited(reloadOnNewBackend());
    });

    // The during-recording preview ends when the recording leaves its phase,
    // whatever ended it (N2): a delivered, empty or fallen-back dictation
    // reaches no `notifyRecordingStopped`, and the trigger timer would keep
    // re-decoding the frozen window until the next recording.
    ref.listen<RecordingPhase>(recordingProvider.select((s) => s.phase), (
      previous,
      next,
    ) {
      if (previous == RecordingPhase.recording &&
          next != RecordingPhase.recording) {
        _stopLivePreview();
      }
    });

    ref.onDispose(() {
      _idleTimer?.cancel();
      _idleTimer = null;
      _modelChangeDebounce?.cancel();
      _modelChangeDebounce = null;
      _benchmarkDeferTimer?.cancel();
      _benchmarkDeferTimer = null;
      _pendingBenchmarkModelId = null;
      _cudaAbTimer?.cancel();
      _cudaAbTimer = null;
      _pendingCudaAbModelId = null;
      _stopLivePreview();
      unawaited(_engine?.unload() ?? Future<void>.value());
      _activeModel = null;
      _lastPrompt = null;
      _lastPromptTime = null;
    });

    ref.listen(settingsProvider, (prev, next) {
      final prevSettings = prev?.value;
      final nextSettings = next.value;
      if (prevSettings == null || nextSettings == null) return;

      if (prevSettings.gpuAcceleration != nextSettings.gpuAcceleration ||
          prevSettings.effectiveModelId != nextSettings.effectiveModelId) {
        _modelLoadFailedIds.remove(prevSettings.effectiveModelId);
      }

      final prevModel = prevSettings.effectiveModelId;
      final nextModel = nextSettings.effectiveModelId;
      if (prevModel == nextModel) return;
      if (!nextSettings.sttProviderType.isLocal) return;

      _debouncedPrewarmOnModelChange(nextModel);
    });

    ref.listen(modelDownloadProvider, (prev, next) {
      if (prev == null) return;
      final newlyDownloaded = next.downloadedModels.difference(
        prev.downloadedModels,
      );
      for (final id in newlyDownloaded) {
        _modelLoadFailedIds.remove(id);
      }
    });

    _building = false;
    return const SttStatus();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// [warmup] = false skips the warm-up inference after the load. Used when the
  /// load runs after a capture start: the real transcription follows and runs
  /// the same first inference, so the silent warm-up would only delay it.
  Future<void> ensureRunning({bool warmup = true}) async {
    if (_startCompleter != null) {
      return _startCompleter!.future;
    }
    final pendingStop = _pendingStop;
    if (pendingStop != null) await pendingStop;
    if (_retiredEngine != null) {
      _log.warning(
        'Start refused: the previous engine is still in native code',
      );
      _fail(_restartNeededCode);
      return;
    }
    if (_nativeBusy > 0 && !await _awaitNativeIdle(nativeIdleCap)) {
      _log.warning('Start refused: a native call is still running');
      _fail(_restartNeededCode);
      return;
    }

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final modelId = settings.effectiveModelId;

    if (_activeModel != null && _activeModel != modelId) {
      _log.info('STT model changed ($_activeModel → $modelId), restarting');
      await _stopForRestart();
    }

    if (state.isReady && state.modelId == modelId) {
      _resetIdleTimer();
      _log.debug('STT engine already loaded (warm) for model $modelId');
      return;
    }

    if (_modelLoadFailedIds.contains(modelId)) {
      _fail(
        'stt_model_corrupted',
        detail: 'model $modelId failed to load before; file treated as corrupt',
      );
      return;
    }

    if (state.serverState != SttServerState.stopped) {
      await _stopForRestart();
    }

    _startCompleter = Completer<void>();
    try {
      await _start(modelId: modelId, warmup: warmup);
      _startCompleter?.complete();
    } on Exception catch (e) {
      _startCompleter?.completeError(e);
      rethrow;
    } finally {
      _startCompleter = null;
    }
  }

  /// Stops the engine ahead of a restart (model switch, prewarm, start over
  /// a stale one). Unlike [stop], it waits for an in-flight transcription to
  /// finish, bounded by [_restartDrainCap], so a restart never unloads the
  /// model underneath a running request (FLUTTER_WHISPASTE-6X, SW-04).
  /// [stop] keeps its short drain on purpose: app quit must not stall.
  Future<void> _stopForRestart() async {
    if (_transcribeInFlight > 0) {
      _drainCompleter ??= Completer<void>();
      await _drainCompleter!.future.timeout(_restartDrainCap, onTimeout: () {});
    }
    await stop();
  }

  Future<void> prewarm() async {
    try {
      await ensureRunning();
      _log.info('STT model pre-warmed (${state.modelId})');
    } on Exception catch (e) {
      _log.debug('Pre-warm skipped: $e');
    }
  }

  /// Measures every installed quality tier (one model each) and leaves the
  /// user's own model loaded again. Progress, cancel and errors go through
  /// [sttBenchmarkRunProvider]; each tier's RTF is stored as soon as it is
  /// measured, so the model-card hints update while the run is still going.
  Future<void> runBenchmark() async {
    final run = ref.read(sttBenchmarkRunProvider.notifier);
    if (ref.read(sttBenchmarkRunProvider).isRunning) return;
    if (_isRecordingActive || _transcribeInFlight > 0) {
      run.fail(BenchmarkRunError.busy);
      return;
    }

    final original =
        ref.read(settingsProvider).value?.effectiveModelId ?? state.modelId;
    final tiers = _benchmarkTierOrder(original);
    if (tiers.isEmpty) {
      run.fail(BenchmarkRunError.noModel);
      return;
    }

    run.begin(total: tiers.length);
    _benchmarkSuiteActive = true;
    var outcome = _BenchmarkOutcome.completed;
    try {
      stop();
      for (var i = 0; i < tiers.length; i++) {
        if (_benchmarkShouldStop()) {
          outcome = _BenchmarkOutcome.cancelled;
          break;
        }
        run.step(done: i, tier: tiers[i]);
        if (!await _measureTierInSuite(tiers[i])) {
          outcome = _BenchmarkOutcome.failed;
          break;
        }
        run.step(done: i + 1, tier: tiers[i]);
      }
    } catch (e) {
      // Any error, not only Exceptions: the engine reports an unloaded engine
      // as a StateError (an Error). Escaping here skipped the restore and left
      // the run in its running phase for good.
      _log.debug('Benchmark run failed: $e');
      outcome = _BenchmarkOutcome.failed;
    } finally {
      _benchmarkSuiteActive = false;
    }

    await _restoreModelAfterBenchmark(original);
    if (!ref.mounted) return;
    switch (outcome) {
      case _BenchmarkOutcome.failed:
        run.fail(BenchmarkRunError.failed);
      case _BenchmarkOutcome.cancelled:
        run.finish(cancelled: true);
      case _BenchmarkOutcome.completed:
        run.finish(cancelled: false);
    }
  }

  /// Installed tiers to measure. The user's own tier goes last, so the run
  /// ends with the model the user selected and needs no reload to restore it.
  List<QualityTier> _benchmarkTierOrder(String originalModelId) {
    final originalTier = tierForModel(originalModelId);
    final installed = [
      for (final tier in QualityTier.values)
        if (_isModelInstalled(bestModelForTier(tier).id)) tier,
    ];
    return [
      ...installed.where((t) => t != originalTier),
      if (installed.contains(originalTier)) originalTier!,
    ];
  }

  /// A cancel request or a dictation starting ends the run after the step in
  /// progress: a native inference cannot be interrupted.
  bool _benchmarkShouldStop() =>
      ref.read(sttBenchmarkRunProvider).cancelRequested ||
      _isRecordingActive ||
      _transcribeInFlight > 0;

  /// Loads [tier]'s model, measures it and stores the result. Returns false
  /// when the model did not come up ready.
  Future<bool> _measureTierInSuite(QualityTier tier) async {
    final modelId = bestModelForTier(tier).id;
    await _start(modelId: modelId);
    if (state.serverState != SttServerState.ready) return false;
    state = state.copyWith(isBenchmarking: true, benchmarkingTier: tier);
    final double rtf;
    try {
      rtf = await _measureRtf();
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          isBenchmarking: false,
          clearBenchmarkingTier: true,
        );
      }
    }
    _log.info('Benchmark completed for $modelId: RTF=$rtf');
    if (ref.mounted) await _storeBenchmarkResult(modelId, rtf);
    return true;
  }

  /// An early stop leaves another tier loaded: put the user's model back.
  Future<void> _restoreModelAfterBenchmark(String original) async {
    if (state.modelId == original || !_isModelInstalled(original)) return;
    try {
      await _start(modelId: original);
    } on Exception catch (e) {
      _log.debug('Restoring the user model after a benchmark failed: $e');
    }
  }

  bool _isModelInstalled(String modelId) {
    final path = sttModelPath(modelId);
    return path != null && File(path).existsSync();
  }

  /// Times one inference of the spoken reference clip on the loaded engine
  /// and returns the real-time factor (processing time / audio duration).
  Future<double> _measureRtf() async {
    final wav = await SttBenchmark.referenceWav();
    final sw = benchmarkStopwatch()..start();
    await _engine!.transcribe(wav);
    sw.stop();
    return sw.elapsedMilliseconds / SttBenchmark.durationMs(wav);
  }

  void notifyRecordingStarted() {
    _isRecordingActive = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    // Only when the on-device engine is actually whisper, the user opted in
    // AND the overlay size paints the text while recording (`wantsLivePreview`) — see [_maybeStartLivePreview]'s doc comment for the
    // performance guarantee this gate provides.
    final settings = ref.read(settingsProvider).value;
    _maybeStartLivePreview(settings != null && settings.wantsLivePreview);
  }

  void notifyTranscriptionCompleted() {
    // Background transcriptions (automation API, file import) report here too.
    // While a dictation is still busy, the flag stays set: the live-preview
    // and reduced-thread gates depend on it. Idle handling is unchanged.
    if (!isDictationBusy(ref.read(recordingPhaseProvider))) {
      _isRecordingActive = false;
    }
    _idleExtended = false;
    _resetIdleTimer(extendAfterTranscription: true);
    _rearmPendingBenchmark();
  }

  void notifyRecordingStopped() {
    _isRecordingActive = false;
    _stopLivePreview();
    _resetIdleTimer();
    _rearmPendingBenchmark();
  }

  Future<String> transcribe(String wavFilePath, {String? language}) async {
    final file = File(wavFilePath);
    if (!file.existsSync()) {
      throw Exception('WAV file not found: $wavFilePath');
    }
    return transcribeBytesWithProgress(
      await file.readAsBytes(),
      language: language,
      wavPath: wavFilePath,
    );
  }

  /// Language the current engine decoded its last transcription in, when the
  /// engine reports one (9.10). `null` when unknown.
  String? get lastDetectedLanguage {
    final engine = _engine;
    if (engine is! DetectedLanguageSource) return null;
    return (engine as DetectedLanguageSource).lastDetectedLanguage;
  }

  /// Shadow-mode protocol (#573): appends the token confidence at the end of
  /// this transcription to a local numbers-only file. Never changes [text].
  void _recordTailConfidence(String text, int audioDurationMs) {
    final engine = _engine;
    if (engine is! TailConfidenceSource || text.isEmpty) return;
    final sample = (engine as TailConfidenceSource).lastTailConfidence;
    if (sample == null) return;
    final record = TailConfidenceRecord.fromSample(
      sample: sample,
      text: text,
      audioMs: audioDurationMs,
      now: DateTime.now(),
      knownPhrase: isNonSpeechTranscript(text),
    );
    if (record == null) return;
    appendTailConfidenceRecord(
      appDataDir(),
      record,
      onError: (e) =>
          _log.debug('tail protocol write failed: ${e.runtimeType}'),
    );
  }

  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) =>
      transcribeBytesWithProgress(wavBytes, language: language);

  /// [transcribeBytes] that also reports engine progress through [onProgress]
  /// (IMP-PROG-2). This is the entry point callers use, so test fakes must
  /// override this method; an override of [transcribeBytes] alone is bypassed.
  ///
  /// [wavPath] (#1665) names the file [wavBytes] were read from. The checks
  /// here still run on [wavBytes], but an engine with [WavFileDecode] reads
  /// the recording from the file itself, a window at a time, so the worker
  /// never gets a copy of all bytes. A path whose file is gone or no longer
  /// holds as many samples falls back to the bytes (see [wavFileMatches]).
  Future<String> transcribeBytesWithProgress(
    List<int> wavBytes, {
    String? language,
    void Function(double fraction)? onProgress,
    String? wavPath,
  }) async {
    if (!state.isReady) {
      throw StateError('STT server is not running');
    }
    // Claims the worker for the *whole* request, not just the engine call:
    // a deferred benchmark ([_scheduleBenchmark]) must not slip into the gap
    // between pre-flight validation and the inference it is about to enqueue.
    _transcribeInFlight++;
    try {
      await _awaitNativeGate();
      return await _transcribeBytesInner(
        wavBytes,
        language: language,
        onProgress: onProgress,
        wavPath: wavPath,
      );
    } finally {
      _transcribeInFlight--;
      if (_transcribeInFlight == 0) {
        _drainCompleter?.complete();
        _drainCompleter = null;
      }
    }
  }

  /// A load that skipped its warm-up leaves the GPU crash-guard marker set.
  /// The first real inference that completes proves the GPU path survived the
  /// first compute dispatch, so only then the marker is cleared. The crash
  /// streak is reset only here too: a successful warm-up alone does not prove
  /// the GPU healthy, because a reload after an idle unload can still crash.
  void _settleCrashGuardAfterInference() {
    final streakKey = _crashStreakResetKey;
    if (!_crashProofPending && streakKey == null) return;
    final crashGuard = ref.read(gpuLoadCrashGuardProvider);
    if (_crashProofPending) {
      _crashProofPending = false;
      crashGuard.clearAttempt();
    }
    if (streakKey != null) {
      _crashStreakResetKey = null;
      crashGuard.resetCrashStreak(key: streakKey);
    }
  }

  Future<String> _transcribeBytesInner(
    List<int> wavBytes, {
    String? language,
    void Function(double fraction)? onProgress,
    String? wavPath,
  }) async {
    _resetIdleTimer();
    final lang = language ?? 'auto';

    _log.info(
      'STT inference: model=${state.modelId} '
      'wavBytes=${wavBytes.length} lang=$lang',
    );
    final stopwatch = Stopwatch()..start();

    // Materialize the payload as a [Uint8List] once so both the pre-flight
    // validator and the engine call use the same byte view.
    final wavView = wavBytes is Uint8List
        ? wavBytes
        : Uint8List.fromList(wavBytes);

    // Derive audio duration (16 kHz mono 16-bit + 44-byte header). Used by
    // breadcrumb extras and the validator context. Clamped at zero so the
    // empty-WAV reject path does not produce a negative value.
    final audioDurationMs = wavBytes.length > 44
        ? ((wavBytes.length - 44) / 32000 * 1000).round()
        : 0;

    final settings = ref.read(settingsProvider).value;
    // The terms as the dictionary list counts them against the budget
    // (#145): no empty entries or stray spaces that cost tokens unseen.
    final vocab = vocabularyPrompt(settings?.customVocabulary ?? '');
    final effectivePrompt = await _resolveEffectivePrompt(
      vocab,
      lang: lang,
      punctuationPriming: settings?.stt.punctuationPriming ?? true,
    );

    // ── Pre-flight validation ─────────────────────────────────────────────
    // Reject obvious-garbage requests before they reach the engine. Sentry
    // sees one breadcrumb in category `stt` but never a captureError — these
    // are user-input issues, not crashes.
    final validation = InferenceRequestValidator.validate(
      wavBytes: wavView,
      language: lang,
      prompt: effectivePrompt,
      supportedLanguages: _whisperSupportedLanguages,
      promptCharLimit: _promptCharLimit,
    );
    if (validation is ValidationReject) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'Inference request rejected pre-flight',
          category: 'stt',
          level: SentryLevel.warning,
          data: <String, dynamic>{
            'reject_reason': validation.reason.name,
            'wav_size_bytes': wavBytes.length,
            'audio_duration_ms': audioDurationMs,
            'language': lang,
          },
        ),
      );
      _log.warning(
        'STT inference rejected pre-flight: reason=${validation.reason.name} '
        'key=${validation.userMessageKey} wavBytes=${wavBytes.length}',
      );
      throw InferenceClientRejected(validation.userMessageKey);
    }

    // ── Pre-send WAV header repair (FLUTTER_WHISPASTE-7X) ─────────────────
    // A recording whose header patch never ran ships valid PCM data behind
    // zeroed RIFF/data size fields — the engine's WAV decoder rejects that
    // container. The sizes are derivable from the byte length, so repair
    // them instead of losing the user's dictation.
    final payload = _repairWavIfNeeded(
      wavView,
      audioDurationMs,
      wavBytes.length,
    );

    // ── Engine input (#1665) ──────────────────────────────────────────────
    // The engine reads the file itself when it still holds these samples.
    // The repair above needs no counterpart on disk: the engine reads the
    // PCM after the 44-byte header up to the end of the file and never
    // looks at the size fields, so the file reads exactly like [payload].
    final filePath = wavPath != null && wavFileMatches(wavPath, payload)
        ? wavPath
        : null;
    if (wavPath != null && filePath == null) {
      _log.warning(
        'WAV file missing or changed since it was read — transcribing the '
        'bytes in memory instead',
      );
    }

    final String rawText;
    try {
      rawText = await _transcribeResilient(
        payload,
        lang,
        effectivePrompt,
        wavBytes.length,
        audioDurationMs,
        settings?.stt.vadEnabled ?? true,
        onProgress: onProgress,
        wavPath: filePath,
      );
      _settleCrashGuardAfterInference();
    } catch (e) {
      stopwatch.stop();
      // The resilience wrapper already classified the failure and (for
      // surfaced failures) captured it to Sentry with the right fingerprint.
      // This warning is deliberately below the AppLogger auto-escalation
      // threshold so it does not add a second capture (see the dedup test).
      // The wrapped string preserves any `stt_cuda_oom` token so the
      // orchestrator's OOM-recovery path keeps firing unchanged.
      _log.warning('STT inference failed: $e');
      // A typed engine failure passes through unchanged: the orchestrator
      // maps it to `stt_server_failed` (or `transcription_timeout`), which
      // keeps the recording in the pending-audio queue and shows the
      // cause-and-next-step notice. Wrapped in a bare Exception it fell
      // through to the raw text: the audio was dropped and the user saw
      // only the generic error toast.
      if (e is WhisperEngineException) rethrow;
      throw Exception('STT inference failed: $e');
    }

    stopwatch.stop();
    // charsPerSec is the fastest drop signal for diagnosing "transcription
    // swallowed part of the audio": a healthy dictation lands around
    // 10-20 chars/sec (German/English speech), so a value far below that
    // for a longer clip flags a likely dropped segment worth pulling from
    // history.db and cross-checking against the retained WAV
    // (kRetainDebugAudio, see build_config.dart).
    final charsPerSec = audioDurationMs > 0
        ? (rawText.length / (audioDurationMs / 1000)).toStringAsFixed(1)
        : 'n/a';
    _log.info(
      'STT inference response: duration=${stopwatch.elapsedMilliseconds}ms '
      'textLen=${rawText.length} audioDurationMs=$audioDurationMs '
      'charsPerSec=$charsPerSec',
    );

    var text = rawText.trim();
    _recordTailConfidence(text, audioDurationMs);
    final stripped = stripNonSpeechMarkers(text);
    if (stripped != text) {
      _log.info('Stripped non-speech markers from transcript');
    }
    text = stripped;
    if (isNonSpeechTranscript(text)) {
      // The whole transcript is a stock phrase or a sound annotation from
      // silence, not dictation.
      // Empty output takes the same path as a blank recording.
      _log.info('Dropped non-speech transcript');
      text = '';
    }
    text = _collapseRepetitions(text);

    if (text.isNotEmpty) {
      _lastPrompt = text.length > 200
          ? text.substring(text.length - 200)
          : text;
      _lastPromptTime = DateTime.now();
    }

    return text;
  }

  /// Unloads the engine if it holds or is loading [modelId], so the model
  /// file can be deleted — Windows refuses to delete a file that is open.
  Future<void> releaseModel(String modelId) async {
    if (_activeModel != modelId && state.modelId != modelId) return;
    await stop();
  }

  /// Stops the engine. Returns a [Future] that completes once the native
  /// context is actually freed — callers that need the app to stay alive
  /// until then (app quit, see `app.dart`'s `onWindowClose`) must await it;
  /// existing fire-and-forget callers (model switch, provider change) can
  /// keep calling `stop()` without awaiting (FLUTTER_WHISPASTE-BC: the
  /// native free racing an imminent process exit is what crashes, not what
  /// this method itself does).
  Future<void> stop() {
    final pending = _pendingStop;
    if (pending != null) return pending;
    late final Future<void> ack;
    ack = _stopNow().whenComplete(() {
      if (identical(_pendingStop, ack)) _pendingStop = null;
    });
    _pendingStop = ack;
    return ack;
  }

  /// App quit: a busy engine is retired at once instead of waited for, so
  /// quit is not held up by a native decode. [hasNativeCallRunning] tells
  /// the caller whether the process must end without a normal exit.
  Future<void> stopForQuit() async {
    if (_nativeBusy == 0) return stop();
    _cancelTimers();
    final engine = _engine;
    if (engine != null) _retireEngine(engine);
    _transition(SttStatus(pendingModelId: _deferredModelChangeId));
  }

  /// True while a native call runs (a decode, a preview or a model load).
  bool get hasNativeCallRunning => _nativeBusy > 0;

  void _cancelTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = null;
    _benchmarkDeferTimer?.cancel();
    _benchmarkDeferTimer = null;
    _cudaAbTimer?.cancel();
    _cudaAbTimer = null;
  }

  Future<void> _stopNow() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = null;
    // A benchmark still waiting for a quiet pipeline belongs to the engine
    // that is going away — dropping it here keeps a model switch from
    // benchmarking the old model against the new one's context.
    _benchmarkDeferTimer?.cancel();
    _benchmarkDeferTimer = null;
    _pendingBenchmarkModelId = null;
    _cudaAbTimer?.cancel();
    _cudaAbTimer = null;
    _pendingCudaAbModelId = null;
    _benchmarkGeneration++;
    _activeModel = null;
    _lastPrompt = null;
    _lastPromptTime = null;
    _idleExtended = false;
    _isRecordingActive = false;
    _stopLivePreview();
    // Transition to stopped immediately (synchronously, before the first
    // await below) — UI responsiveness for the common case (model switch)
    // must not wait on native cleanup. The returned Future still resolves
    // only once the engine confirms it, for callers that need that
    // guarantee (app quit, see `app.dart`'s `onWindowClose`).
    _transition(SttStatus(pendingModelId: _deferredModelChangeId));
    // A caller can already be past transcribeBytes's readiness check (idle
    // timer, model switch, and the OOM/cloud-switch fallback all call stop()
    // without coordinating with in-flight requests) — unloading the native
    // engine underneath that call raced it into "whisper_engine_not_loaded"
    // (FLUTTER_WHISPASTE-6X). Wait for it to finish first, bounded by
    // [stopDrainTimeout] — a short grace for the readiness-check race, not
    // the local decode budget of minutes, which would otherwise stall
    // app quit behind a still-running transcription.
    if (_transcribeInFlight > 0) {
      _drainCompleter ??= Completer<void>();
      await _drainCompleter!.future.timeout(stopDrainTimeout, onTimeout: () {});
    }
    final engine = _engine;
    if (engine == null) return;
    // Never free the engine under a native call that has not returned. The
    // Dart-side stuck budget does not end the native call, so only its return
    // makes the unload safe (de8789eb, b320fb2a).
    if (_nativeBusy > 0) {
      final idle = await _awaitNativeIdle(nativeIdleCap);
      if (!idle) {
        _retireEngine(engine);
        _fail(_restartNeededCode);
        return;
      }
      // The release on return already unloaded this engine.
      if (_unloadedOnRelease) return;
    }
    await engine.unload();
  }

  /// Detaches [engine] from the notifier; it is unloaded when its native
  /// call returns, never while the call runs.
  void _retireEngine(WhisperEngine engine) {
    _retiredEngine = engine;
    _log.warning(
      'Engine still busy in native code; retired and released when it returns',
    );
  }

  /// Runs one native call and counts it until the native future itself
  /// completes, not until a Dart-side timeout gives up on it.
  Future<T> _nativeCall<T>(Future<T> Function() call, {bool preview = false}) {
    _nativeBusy++;
    if (preview) _nativePreviewBusy++;
    final future = Future<T>.sync(call);
    unawaited(
      future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _nativeBusy--;
        if (preview) _nativePreviewBusy--;
        _onNativeIdle();
      }),
    );
    return future;
  }

  /// Waits until no native call runs, at most [cap]. Returns whether the
  /// engine is idle.
  Future<bool> _awaitNativeIdle(Duration cap) async {
    if (_nativeBusy == 0) return true;
    final idle = _nativeIdle ??= Completer<void>();
    _nativeIdleWaiters++;
    try {
      await idle.future.timeout(cap);
      return true;
    } on TimeoutException {
      return _nativeBusy == 0;
    } finally {
      _nativeIdleWaiters--;
    }
  }

  int _nativeIdleWaiters = 0;

  /// Callers parked in [_awaitNativeIdle] right now. Lets tests see that a
  /// model switch or restart has reached its wait for a running native call,
  /// instead of sleeping until it probably has.
  @visibleForTesting
  int get debugNativeIdleWaiters => _nativeIdleWaiters;

  /// Gate in front of a new decode: a decode never starts on a busy instance.
  /// A preview-only backlog gets the short [previewDrainCap], anything else
  /// [nativeIdleCap].
  Future<void> _awaitNativeGate() async {
    // One event-loop turn lets a failing decode's catch block open the
    // recovery marker before this gate decides the engine is idle.
    await Future<void>.delayed(Duration.zero);
    while (_gpuRecovery != null) {
      await _gpuRecovery!.future;
    }
    if (_nativeBusy == 0) return;
    final previewOnly = _nativePreviewBusy == _nativeBusy;
    final cap = (previewOnly || _engineMarkedStuck)
        ? previewDrainCap
        : nativeIdleCap;
    if (!await _awaitNativeIdle(cap)) {
      throw StateError(
        'STT engine is still busy with a native call; decode not started',
      );
    }
    while (_gpuRecovery != null) {
      await _gpuRecovery!.future;
    }
  }

  /// Runs [recovery] while the decode gate holds back new decodes (#404).
  Future<T> _holdingGpuRecovery<T>(Future<T> Function() recovery) async {
    final marker = _gpuRecovery ??= Completer<void>();
    try {
      return await recovery();
    } finally {
      if (identical(_gpuRecovery, marker)) _gpuRecovery = null;
      if (!marker.isCompleted) marker.complete();
    }
  }

  /// The stuck guard gave up on a decode whose native call still runs: the
  /// next decode fails fast and Settings asks for a restart.
  void _markEngineStuck() {
    _engineMarkedStuck = true;
    if (ref.mounted) _transition(state.copyWith(restartNeeded: true));
  }

  /// Runs when a native call returns: wakes the waiters, releases a retired
  /// engine, runs an idle unload and a deferred model switch that were held.
  void _onNativeIdle() {
    if (_nativeBusy > 0) return;
    _engineMarkedStuck = false;
    if (state.restartNeeded) _transition(state.copyWith(restartNeeded: false));
    final idle = _nativeIdle;
    _nativeIdle = null;
    idle?.complete();

    final retired = _retiredEngine;
    if (retired != null) {
      _retiredEngine = null;
      _unloadedOnRelease = true;
      _log.info('Retired engine released after its native call returned');
      if (state.errorMessage == _restartNeededCode) {
        _transition(SttStatus(pendingModelId: _deferredModelChangeId));
      }
      unawaited(retired.unload());
    }

    if (_unloadWhenIdle) {
      _unloadWhenIdle = false;
      if (_isRecordingActive || _transcribeInFlight > 0) {
        // A dictation started meanwhile owns the engine. Re-arm the idle
        // timer instead of unloading under the next decode.
        _resetIdleTimer();
      } else {
        unawaited(stop());
      }
    }

    final deferred = _deferredModelChangeId;
    if (deferred != null) {
      _deferredModelChangeId = null;
      _debouncedPrewarmOnModelChange(deferred);
    }
  }

  // ---------------------------------------------------------------------------
  // transcribeBytes helpers
  // ---------------------------------------------------------------------------

  /// Builds the effective prompt from the custom vocabulary setting and the
  /// rolling context window, updating [_lastPrompt]/[_lastPromptTime] on
  /// expiry.  Extracted from [transcribeBytes] to lower its cyclomatic count.
  ///
  /// When neither [vocab] nor the rolling context yields anything and
  /// [punctuationPriming] is enabled, falls back to a short punctuated
  /// example prompt for [lang] (see `punctuation_priming_prompts.dart`) so
  /// greedy decoding is biased towards punctuated output. Never overrides a
  /// real vocab/context prompt — style-mimicry priming only fills the gap.
  ///
  /// The combined string is then budgeted against whisper.cpp's real
  /// tokenized `initial_prompt` ceiling ([promptTokenBudget]) via
  /// [_truncateToRealTokenBudget] — see [promptTokenBudget]'s doc comment
  /// for why this step exists at all (silent native truncation bug).
  Future<String?> _resolveEffectivePrompt(
    String vocab, {
    required String lang,
    required bool punctuationPriming,
  }) async {
    String? promptValue;
    if (_lastPrompt != null &&
        _lastPrompt!.isNotEmpty &&
        _lastPromptTime != null &&
        DateTime.now().difference(_lastPromptTime!) < _promptExpiry) {
      promptValue = _lastPrompt!;
    } else if (_lastPrompt != null) {
      _lastPrompt = null;
      _lastPromptTime = null;
    }
    final trimmedVocab = vocab.isNotEmpty ? vocab : null;
    final combined = <String>[
      ?trimmedVocab,
      if (promptValue != null && promptValue.isNotEmpty) promptValue,
    ].join(' ');
    if (combined.isEmpty) {
      if (!punctuationPriming) return null;
      return resolvePunctuationPrimingPrompt(lang);
    }
    return _truncateToRealTokenBudget(combined, vocab: trimmedVocab);
  }

  /// Truncates [combined] (vocab + rolling context, already joined) to fit
  /// [promptTokenBudget] real whisper.cpp tokens.
  ///
  /// Fast path: skips the async, isolate-proxied exact token count entirely
  /// whenever [combined]'s UTF-8 byte length already guarantees it fits —
  /// whisper's byte-level BPE tokenizer only ever MERGES base bytes, so a
  /// string's token count can never exceed its byte count. This covers the
  /// overwhelming majority of real prompts (short vocab/context) with zero
  /// isolate round-trips; the exact FFI count only runs for the rare
  /// longer prompt that might actually overflow the budget.
  ///
  /// When it does overflow, [vocab] is preserved preferentially over the
  /// rolling context: the combined string's tail (the rolling context) is
  /// dropped first, and only [vocab] itself is truncated (front-anchored,
  /// see [truncatePromptToTokenBudget]) if even that alone is too long.
  /// This is a deliberate choice, not the only valid one — the user
  /// explicitly configured [vocab] in settings, while the rolling context
  /// is an automatic, best-effort addition.
  ///
  /// Falls back to returning [combined] unchanged if [_engine] doesn't
  /// implement [PromptTokenCounter] (no engine loaded yet, or a future
  /// non-whisper local engine) or the count call itself fails — the
  /// char-length backstop in [InferenceRequestValidator] still applies, so
  /// this degrades to the pre-fix behaviour rather than crashing.
  Future<String> _truncateToRealTokenBudget(
    String combined, {
    required String? vocab,
  }) async {
    if (utf8.encode(combined).length <= promptTokenBudget) return combined;
    final rawEngine = _engine;
    if (rawEngine is! PromptTokenCounter) return combined;
    final engine = rawEngine as PromptTokenCounter;
    try {
      if (await engine.countPromptTokens(combined) <= promptTokenBudget) {
        return combined;
      }
      if (vocab == null || vocab.isEmpty) {
        return await truncatePromptToTokenBudget(
          combined,
          promptTokenBudget,
          engine.countPromptTokens,
        );
      }
      return await truncatePromptToTokenBudget(
        vocab,
        promptTokenBudget,
        engine.countPromptTokens,
      );
    } catch (e) {
      _log.warning(
        'Prompt token-budget check failed, using untruncated prompt: $e',
      );
      return combined;
    }
  }

  /// Moves the active model from the GPU engine onto the always-CPU fallback
  /// engine after a transcribe-time GPU crash, so the retry does not run on
  /// the same crashing GPU configuration. Mirrors the load-time fallback in
  /// [_start]: load the model on the fallback engine, swap [_engine],
  /// then unload the old engine.
  ///
  /// Returns `false` (and leaves [_engine] untouched) when no retry on CPU is
  /// possible — no active model, already on the fallback engine, or the CPU
  /// load itself failed. The caller then surfaces the original crash.
  Future<bool> _swapToCpuEngineForRetry() async {
    final modelId = _activeModel;
    final modelPath = modelId == null ? null : sttModelPath(modelId);
    final gpuEngine = _engine;
    final cpuEngine = ref.read(whisperCpuFallbackEngineProvider);
    if (modelPath == null || gpuEngine == null) return false;
    if (identical(gpuEngine, cpuEngine)) return false;
    _recordGpuLoadContext(
      backend: WhisperBackend.cpu,
      modelId: modelId!,
      cudaPack: false,
    );
    try {
      await _nativeCall(
        () => cpuEngine.load(
          modelPath: modelPath,
          vadModelPath: defaultWhisperVadModelPath(),
        ),
      );
    } catch (cpuError) {
      _log.warning('CPU load after GPU crash failed: $cpuError');
      return false;
    }
    _engine = cpuEngine;
    unawaited(
      gpuEngine.unload().catchError((Object e) {
        _log.warning('Unload of crashed GPU engine failed: $e');
      }),
    );
    if (ref.mounted) {
      state = state.copyWith(
        cpuFallbackActive: true,
        backend: WhisperBackend.cpu,
      );
    }
    _log.warning(
      'GPU crash during inference — reloaded model on CPU and retrying',
    );
    return true;
  }

  /// Recreates the native context of the active engine after a
  /// [WhisperFailureKind.gpuBackendLost]: unload, then load the same model on
  /// the same engine. ggml-metal stays in its error state until the backend is
  /// freed, so retrying on the old context would fail every time (observed
  /// after a system-wide GPU restart during the warm-up: every dictation
  /// failed with `whisper_full` code -6 until the app was restarted).
  ///
  /// Returns `false` when no model is active or the reload failed; the caller
  /// then degrades to CPU via [_swapToCpuEngineForRetry].
  Future<bool> _rebuildEngineForRetry() async {
    final modelId = _activeModel;
    final modelPath = modelId == null ? null : sttModelPath(modelId);
    final engine = _engine;
    if (modelPath == null || engine == null) return false;
    final backend = engine.status.backend;
    // A reload on the GPU can crash the process like any GPU load: mark it
    // for the crash guard (#404). The marker stays until the retried
    // inference proves the context ([_settleCrashGuardAfterInference]).
    final crashGuard = ref.read(gpuLoadCrashGuardProvider);
    final onGpu = backend != WhisperBackend.cpu;
    if (onGpu) {
      crashGuard.markAttempt(
        cuda: ref.read(activeCudaPackDirProvider) != null,
        key: GpuLoadCrashGuard.attemptKey(
          backend: backend.name,
          modelId: modelId!,
          appVersion: app.appVersion,
        ),
      );
    }
    try {
      // One native call for both steps: the busy count stays up between
      // unload and load, so no waiting decode, idle unload or deferred model
      // switch slips into the gap and meets an unloaded engine.
      await _nativeCall(() async {
        await engine.unload();
        await engine.load(
          modelPath: modelPath,
          vadModelPath: defaultWhisperVadModelPath(),
        );
      });
    } catch (e) {
      _log.warning('Rebuilding the ${backend.name} speech engine failed: $e');
      if (onGpu) crashGuard.clearAttempt();
      return false;
    }
    if (onGpu) _crashProofPending = true;
    _log.warning(
      'GPU backend ${backend.name} was in an error state — rebuilt the '
      'speech engine and retrying',
    );
    return true;
  }

  /// Handles a decode that ran out of budget and did not stop at its abort
  /// flag within [abortGrace] (or an engine without [AbortableDecode]). That
  /// call keeps its engine busy; the active model moves to the
  /// CPU engine once and the caller retries there, otherwise every later
  /// dictation would queue behind the hang. Returns normally when a CPU retry
  /// was set up; otherwise captures the failure and throws it. A hang on CPU
  /// has no fallback and ends here.
  Future<void> _handleStuckGuardTimeout({
    required String lang,
    required int wavSizeBytes,
    required int audioDurationMs,
    required bool cpuFallbackTried,
  }) => _holdingGpuRecovery(
    () => _handleStuckGuardTimeoutHeld(
      lang: lang,
      wavSizeBytes: wavSizeBytes,
      audioDurationMs: audioDurationMs,
      cpuFallbackTried: cpuFallbackTried,
    ),
  );

  Future<void> _handleStuckGuardTimeoutHeld({
    required String lang,
    required int wavSizeBytes,
    required int audioDurationMs,
    required bool cpuFallbackTried,
  }) async {
    _markEngineStuck();
    const failure = WhisperEngineException(
      WhisperFailureKind.timeout,
      'pipeline_timeout: transcription exceeded the stuck-guard budget',
    );
    _captureInferenceFailure(
      failure,
      sttExitOther,
      lang,
      wavSizeBytes,
      audioDurationMs,
    );
    final onGpu = _engine!.status.backend != WhisperBackend.cpu;
    if (!cpuFallbackTried && onGpu && await _swapToCpuEngineForRetry()) {
      return;
    }
    throw failure;
  }

  /// Runs [WhisperEngine.transcribe] behind the FFI resilience chain
  /// (internal-notes §3.3), reacting to the engine's distinguishable
  /// [WhisperFailureKind] signals:
  ///
  /// - **Local budget** (#1639) — the call is raced against
  ///   [localTranscriptionBudget] (audio length × measured speed, 60 s
  ///   floor), which each progress report extends up to
  ///   [localTranscriptionHardCap]. On overrun the native decode is aborted
  ///   ([AbortableDecode]); once it stopped the engine is free and the
  ///   failure is a clean [WhisperFailureKind.timeout] (audio parked for a
  ///   retry with a doubled budget). A decode that does not stop within
  ///   [abortGrace] counts as hung: the engine is marked stuck, and a hang on
  ///   a GPU engine moves the model to CPU once and retries.
  /// - **CPU-Fallback** — a [WhisperFailureKind.gpuCrash] degrades to CPU once
  ///   (`cpuFallbackActive` set) and retries.
  /// - **Backend rebuild** — a [WhisperFailureKind.gpuBackendLost] (the GPU
  ///   backend refuses every graph after an earlier command-buffer failure)
  ///   reloads the model on the same engine once; failing that, or failing
  ///   again, it degrades to CPU like a GPU crash. Never retried on the dead
  ///   context.
  /// - **Retry** — a [WhisperFailureKind.transient] failure is retried up to
  ///   [_maxTranscribeRetries] times before being surfaced.
  /// - **OOM** — a [WhisperFailureKind.oom] is not retried here; it is captured
  ///   and rethrown carrying the `stt_cuda_oom` token so the orchestrator's
  ///   `OomRecoveryHandler` (smaller model / cloud) recovers it.
  ///
  /// Surfaced (unrecovered) failures are captured to Sentry with a stable
  /// fingerprint before the exception propagates.
  /// One engine decode. Reports progress only when the engine opts in via
  /// [TranscriptionProgressSource] (IMP-PROG-2); other engines ignore
  /// [onProgress], so the caller simply stays indeterminate. With [wavPath]
  /// an engine with [WavFileDecode] reads the file instead of [payload]
  /// (#1665); an engine without it gets [payload].
  Future<String> _transcribeOnEngine(
    WhisperEngine engine,
    List<int> payload, {
    required String lang,
    required String? prompt,
    required bool vadEnabled,
    void Function(double fraction)? onProgress,
    String? wavPath,
  }) {
    final reducedThreads = _isRecordingActive;
    final progress = onProgress;
    return switch (engine) {
      final WavFileDecode fileDecode when wavPath != null =>
        fileDecode.transcribeFile(
          wavPath,
          language: lang,
          prompt: prompt,
          vadEnabled: vadEnabled,
          reducedThreads: reducedThreads,
          onProgress: progress,
        ),
      final TranscriptionProgressSource progressive when progress != null =>
        progressive.transcribeWithProgress(
          payload,
          language: lang,
          prompt: prompt,
          vadEnabled: vadEnabled,
          reducedThreads: reducedThreads,
          onProgress: progress,
        ),
      _ => engine.transcribe(
        payload,
        language: lang,
        prompt: prompt,
        vadEnabled: vadEnabled,
        reducedThreads: reducedThreads,
      ),
    };
  }

  /// The deadline of one decode on [engine] (#1639): the local budget for
  /// the audio length and the measured speed, extended by progress.
  TranscriptionDeadline _deadlineFor(WhisperEngine engine, int audioMs) {
    final override = stuckGuardTimeout;
    if (override != null) {
      return TranscriptionDeadline(
        initial: override,
        stallWindow: Duration.zero,
        hardCap: override,
      );
    }
    final audio = Duration(milliseconds: audioMs);
    final rtf = _rtfFor(engine);
    return TranscriptionDeadline(
      initial: localTranscriptionBudget(
        audio,
        measuredRtf: rtf,
        boost: _budgetBoost,
      ),
      stallWindow: localProgressStallWindow(
        localBudgetFactor(measuredRtf: rtf, boost: _budgetBoost),
      ),
      hardCap: localTranscriptionHardCap(audio),
    );
  }

  /// A decode ran out of its budget: raises the engine's abort flag and waits
  /// up to [abortGrace] for the native call to return. Throws [_BudgetAbort]
  /// when it stopped (the engine is free). Returns the text when the call
  /// finished anyway before it saw the flag. Returns null when the engine
  /// cannot abort or did not return in time: it counts as hung.
  Future<String?> _abortOverrunDecode(
    WhisperEngine engine,
    Future<String> native,
    Duration budget,
  ) async {
    if (engine is! AbortableDecode) return null;
    _log.warning(
      'Transcription exceeded its ${budget.inSeconds}s budget — aborting '
      'the native decode',
    );
    (engine as AbortableDecode).abortDecode();
    try {
      return await native.timeout(abortGrace);
    } on TimeoutException {
      _log.warning(
        'Aborted decode did not return within ${abortGrace.inSeconds}s',
      );
      return null;
    } on Object {
      throw _BudgetAbort(budget);
    }
  }

  Future<String> _transcribeResilient(
    List<int> payload,
    String lang,
    String? prompt,
    int wavSizeBytes,
    int audioDurationMs,
    bool vadEnabled, {
    void Function(double fraction)? onProgress,
    String? wavPath,
  }) async {
    final gpuRecovery = _GpuRecoveryAttempts();
    try {
      return await _transcribeResilientLoop(
        payload,
        lang,
        prompt,
        wavSizeBytes,
        audioDurationMs,
        vadEnabled,
        gpuRecovery,
        onProgress: onProgress,
        wavPath: wavPath,
      );
    } finally {
      _releaseGpuRecoveryGate(gpuRecovery);
    }
  }

  Future<String> _transcribeResilientLoop(
    List<int> payload,
    String lang,
    String? prompt,
    int wavSizeBytes,
    int audioDurationMs,
    bool vadEnabled,
    _GpuRecoveryAttempts gpuRecovery, {
    void Function(double fraction)? onProgress,
    String? wavPath,
  }) async {
    var transientAttempts = 0;
    while (true) {
      try {
        // `_isRecordingActive` reflects a NEW recording's live audio
        // capture (set/cleared in `notifyRecordingStarted`/
        // `notifyRecordingStopped` — see their doc comments), not this
        // transcription's own recording. Reading it fresh on every retry
        // means: if the user has already started dictating their next
        // utterance while this one is still decoding, this call throttles
        // itself so Whisper's own CPU load doesn't compete with that live
        // capture (see `WhisperFfiEngine._decodeOnce`'s "Audio-capture
        // protection" comment for why this is the one place in this app's
        // batch architecture where that contention is real and something
        // this app actually controls).
        final engine = _engine!;
        final deadline = _deadlineFor(engine, audioDurationMs);
        // Progress is always requested: it extends the deadline (#1639).
        // The caller's sink still gets every report.
        void progress(double fraction) {
          deadline.reportProgress(fraction);
          onProgress?.call(fraction);
        }

        final native = _nativeCall(
          () => _transcribeOnEngine(
            engine,
            payload,
            lang: lang,
            prompt: prompt,
            vadEnabled: vadEnabled,
            onProgress: progress,
            wavPath: wavPath,
          ),
        );
        String text;
        try {
          text = await deadline.guard(native);
        } on TimeoutException {
          final lateText = await _abortOverrunDecode(
            engine,
            native,
            deadline.current,
          );
          if (lateText == null) rethrow;
          text = lateText;
        }
        _budgetBoost = 1;
        // The CPU run after a GPU failure worked: the next load goes back
        // to the GPU (#404).
        if (gpuRecovery.swappedToCpu) _gpuRetryAfterCpuRun = true;
        return text;
      } on _BudgetAbort catch (abort) {
        // The decode stopped at the abort flag: the engine is free again,
        // so the next dictation runs normally. The audio goes to the retry
        // queue (transcription_timeout); the retry gets a larger budget.
        _budgetBoost = math.min(_budgetBoost * 2, kLocalBudgetMaxBoost);
        final failure = WhisperEngineException(
          WhisperFailureKind.timeout,
          'transcription_budget_exceeded: aborted after '
          '${abort.budget.inSeconds}s',
        );
        _captureInferenceFailure(
          failure,
          sttExitOther,
          lang,
          wavSizeBytes,
          audioDurationMs,
        );
        throw failure;
      } on TimeoutException {
        await _handleStuckGuardTimeout(
          lang: lang,
          wavSizeBytes: wavSizeBytes,
          audioDurationMs: audioDurationMs,
          cpuFallbackTried: gpuRecovery.cpuFallbackTried,
        );
        gpuRecovery.cpuFallbackTried = true;
        continue;
      } on WhisperEngineException catch (e) {
        switch (e.kind) {
          case WhisperFailureKind.gpuBackendLost:
          case WhisperFailureKind.gpuCrash:
            if (await _recoverFromGpuFailure(e, gpuRecovery)) continue;
            _captureInferenceFailure(
              e,
              sttExitGpuFatal,
              lang,
              wavSizeBytes,
              audioDurationMs,
            );
            rethrow;
          case WhisperFailureKind.oom:
            _captureInferenceFailure(
              e,
              sttCudaOom,
              lang,
              wavSizeBytes,
              audioDurationMs,
            );
            rethrow;
          case WhisperFailureKind.transient:
            transientAttempts++;
            if (transientAttempts <= _maxTranscribeRetries) {
              _log.warning(
                'Transient STT failure '
                '(attempt $transientAttempts/$_maxTranscribeRetries) — retrying',
              );
              continue;
            }
            _captureInferenceFailure(
              e,
              sttExitOther,
              lang,
              wavSizeBytes,
              audioDurationMs,
            );
            rethrow;
          case WhisperFailureKind.timeout:
          case WhisperFailureKind.other:
            _captureInferenceFailure(
              e,
              sttExitOther,
              lang,
              wavSizeBytes,
              audioDurationMs,
            );
            rethrow;
        }
      } on InferenceClientRejected {
        rethrow;
      } catch (e) {
        // Catch-all for failures the engine raises as a bare error rather
        // than a typed [WhisperEngineException] — e.g. the isolate proxy's
        // `StateError('whisper_engine_not_loaded')` when the worker's native
        // context was freed out from under a stale "ready" state (see
        // `WhisperIsolateEngine.unload`'s doc comment). Previously this fell
        // through both `on` clauses above untouched, so it never reached
        // [_captureInferenceFailure]/Sentry at all — reproduced empirically:
        // the user saw only a generic "Etwas ist schiefgelaufen" toast, and
        // this project's own Sentry had zero events for it.
        final failure = WhisperEngineException(WhisperFailureKind.other, '$e');
        _captureInferenceFailure(
          failure,
          sttExitOther,
          lang,
          wavSizeBytes,
          audioDurationMs,
        );
        // Self-heal: don't leave `state` claiming a model is `ready` when
        // the engine just proved it isn't — otherwise `ensureRunning()`'s
        // warm-engine fast path keeps returning immediately and every
        // subsequent dictation repeats this same failure until an idle
        // unload or app restart happens to clear it (reproduced live: a
        // mid-session model switch broke dictation for the rest of the
        // session). Dropping back to `stopped` makes the next `ensureRunning()`
        // call go through `_start()` for a genuine reload.
        if (ref.mounted) _transition(const SttStatus());
        throw failure;
      }
    }
  }

  /// Recovers a GPU failure for the retry loop of [_transcribeResilient]:
  /// a [WhisperFailureKind.gpuBackendLost] first rebuilds the engine once,
  /// then both GPU kinds degrade to CPU once. Returns `true` when the caller
  /// should retry, `false` when the failure must surface.
  ///
  /// The decode gate stays closed after a successful recovery until the run
  /// ends: a dictation waiting behind this one would otherwise reach the
  /// rebuilt context before the retry proves it, and a context that is still
  /// dead would fail it too (#404).
  Future<bool> _recoverFromGpuFailure(
    WhisperEngineException e,
    _GpuRecoveryAttempts attempts,
  ) async {
    attempts.gate ??= _gpuRecovery ??= Completer<void>();
    final retry = await _recoverFromGpuFailureHeld(e, attempts);
    if (!retry) _releaseGpuRecoveryGate(attempts);
    return retry;
  }

  /// Opens the decode gate [attempts] holds, if any.
  void _releaseGpuRecoveryGate(_GpuRecoveryAttempts attempts) {
    final gate = attempts.gate;
    if (gate == null) return;
    attempts.gate = null;
    if (identical(_gpuRecovery, gate)) _gpuRecovery = null;
    if (!gate.isCompleted) gate.complete();
  }

  Future<bool> _recoverFromGpuFailureHeld(
    WhisperEngineException e,
    _GpuRecoveryAttempts attempts,
  ) async {
    if (e.kind == WhisperFailureKind.gpuBackendLost) {
      _log.warning('GPU backend lost during inference: ${e.message}');
    }
    var rebuildFailed = false;
    if (!attempts.backendRebuildTried &&
        _resiliencePolicy.shouldRebuildBackend(e.kind)) {
      attempts.backendRebuildTried = true;
      if (await _rebuildEngineForRetry()) return true;
      rebuildFailed = true;
    }
    final retryOnCpu =
        !attempts.cpuFallbackTried &&
        _resiliencePolicy.shouldRetryOnCpu(e.kind);
    attempts.cpuFallbackTried = true;
    if (retryOnCpu && await _swapToCpuEngineForRetry()) {
      attempts.swappedToCpu = true;
      // The GPU path is abandoned, so a reload marker left by the rebuild
      // must not read as a crash on the next launch.
      if (_crashProofPending) {
        _crashProofPending = false;
        ref.read(gpuLoadCrashGuardProvider).clearAttempt();
      }
      return true;
    }
    // A failed rebuild may have unloaded the engine already. Leaving `state`
    // on ready would send the next dictation down the warm fast path onto an
    // unloaded engine; `stopped` makes the next `ensureRunning()` load the
    // model fresh (on the GPU again).
    if (rebuildFailed && ref.mounted) _transition(const SttStatus());
    return false;
  }

  /// Captures an unrecovered inference failure to Sentry under [fingerprint]
  /// (from the central inventory), mirroring the pre-cutover HTTP-status
  /// capture path so surfaced FFI errors stay actionable.
  void _captureInferenceFailure(
    WhisperEngineException failure,
    String fingerprint,
    String lang,
    int wavSizeBytes,
    int audioDurationMs,
  ) {
    CrashReporter.instance?.captureError(
      message: 'STT inference failed: ${failure.message}',
      error: failure,
      severity: 'error',
      type: 'stt_inference_failed',
      fingerprint: [fingerprint],
      extras: {
        'failure_kind': failure.kind.name,
        'model_id': state.modelId,
        'language': lang,
        'wav_size_bytes': wavSizeBytes,
        'audio_duration_ms': audioDurationMs,
        'platform': Platform.operatingSystem,
      },
    );
  }

  /// Repairs zeroed WAV size fields in-memory (FLUTTER_WHISPASTE-7X) and
  /// emits a Sentry breadcrumb + warning log when a repair was needed.
  /// Returns [wavView] unmodified when no repair is required.
  Uint8List _repairWavIfNeeded(
    Uint8List wavView,
    int audioDurationMs,
    int wavBytesLength,
  ) {
    final repairedWav = repairZeroedWavSizeFields(wavView);
    if (repairedWav == null) return wavView;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'WAV size fields were zero — repaired before inference',
        category: 'stt',
        level: SentryLevel.warning,
        data: <String, dynamic>{
          'wav_size_bytes': wavBytesLength,
          'audio_duration_ms': audioDurationMs,
        },
      ),
    );
    _log.warning(
      'WAV header size fields were zero (unpatched header) — repaired '
      'in-memory before inference ($wavBytesLength bytes).',
    );
    return repairedWav;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _transition(SttStatus next) {
    // Every state mutation flows through here, so a single mounted-guard
    // covers async resumes that race the provider container shutdown
    // (test teardown, app quit, hot-reload). Without it, a completion that
    // lands after the scope is torn down throws a "Cannot use the Ref …
    // after it has been disposed" deep in async continuations and surfaces
    // as a "failed after test completion" flake on CI.
    if (!ref.mounted) return;

    final prev = state.serverState;

    if (next.serverState == SttServerState.starting &&
        next.startingSince == null) {
      next = SttStatus(
        serverState: next.serverState,
        port: next.port,
        modelId: next.modelId,
        errorMessage: next.errorMessage,
        startingSince: DateTime.now(),
      );
    }

    state = next;
    if (prev == next.serverState) return;

    final extra = StringBuffer();
    if (next.modelId.isNotEmpty) extra.write(' model=${next.modelId}');
    if (next.errorMessage != null) extra.write(' error="${next.errorMessage}"');

    _log.info('STT lifecycle: $prev → ${next.serverState}$extra');
  }

  void _resetIdleTimer({bool extendAfterTranscription = false}) {
    if (_isRecordingActive) return;

    _idleTimer?.cancel();
    _idleTimer = null;

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final baseMinutes = resolveIdleUnloadMinutes(
      configured: settings.stt.idleTimeoutMinutes,
      snapshot: ref.read(memorySnapshotStoreProvider).latest,
      modelMB: hw.sttModelVramMB[settings.effectiveModelId],
    );

    if (baseMinutes <= 0 && debugIdleUnloadDelay == null) return;

    var timeoutMinutes = baseMinutes;

    if (extendAfterTranscription && !_idleExtended) {
      timeoutMinutes = math.min(baseMinutes + 5, baseMinutes * 2);
      _idleExtended = true;
      _log.debug(
        'Idle timer extended: ${timeoutMinutes}min '
        '(base=${baseMinutes}min, burst=+5min)',
      );
    }

    final timeout = debugIdleUnloadDelay ?? Duration(minutes: timeoutMinutes);
    _idleTimer = Timer(timeout, () {
      if (_nativeBusy > 0) {
        _unloadWhenIdle = true;
        _log.info('STT idle unload deferred: a native call is still running');
        return;
      }
      if (_transcribeInFlight > 0) {
        // A transcription has claimed the engine but not reached native yet.
        _resetIdleTimer();
        return;
      }
      _log.info(
        'STT engine idle for ${timeout.inMinutes} min, '
        'unloading to free memory',
      );
      stop();
    });
  }

  void _debouncedPrewarmOnModelChange(String newModelId) {
    _modelChangeDebounce?.cancel();
    final generation = ++_modelChangeGeneration;
    _deferredModelChangeId = null;
    if (state.pendingModelId != null) {
      _transition(state.copyWith(clearPendingModelId: true));
    }
    _modelChangeDebounce = Timer(modelChangeDebounce, () {
      _modelChangePrewarm = _prewarmAfterModelChange(newModelId, generation);
    });
  }

  Future<void> _prewarmAfterModelChange(
    String newModelId,
    int generation,
  ) async {
    _log.info('Model changed to $newModelId, starting debounced pre-warm');

    final modelPath = sttModelPath(newModelId);
    if (modelPath == null || !await File(modelPath).exists()) {
      _log.debug('Model file not downloaded yet, skipping pre-warm');
      return;
    }

    if (state.serverState != SttServerState.stopped) {
      // A switch never frees the engine under a native call. Past the cap
      // it is shown as pending and retried once native is idle (b28cc78c).
      if (_nativeBusy > 0 && !await _awaitNativeIdle(nativeIdleCap)) {
        if (generation != _modelChangeGeneration) return;
        _deferredModelChangeId = newModelId;
        _log.warning(
          'Model switch to $newModelId deferred: a native call is still '
          'running after ${nativeIdleCap.inSeconds}s',
        );
        _transition(state.copyWith(pendingModelId: newModelId));
        return;
      }
      if (generation != _modelChangeGeneration) return;
      await _stopForRestart();
    }
    try {
      await ensureRunning();
      _log.info('Pre-warm after model change complete');
    } on Exception catch (e) {
      _log.debug('Pre-warm after model change skipped: $e');
    }
  }

  /// Best-effort GPU/engine warmup so the first real dictation after a cold
  /// load doesn't pay the one-time kernel-compile/cache-fill penalty.
  /// Failures are non-fatal — mirrors the pre-cutover HTTP warmup's contract.
  /// Returns `false` when the warmup threw: a failed warmup proves nothing
  /// about the GPU, so the caller must not count it as a surviving GPU path.
  /// Keeps a model that does not fit the detected GPU VRAM off the GPU engine:
  /// for this load [_engine] is the always-CPU engine. Only a swap made here
  /// is undone, so a load-time CPU fallback after a GPU crash stays in place.
  void _applyVramGate(String modelId) {
    final primary = ref.read(whisperEngineProvider);
    final gpuInfo = ref.read(hw.gpuInfoProvider).value;
    final gated =
        primary.status.backend != WhisperBackend.cpu &&
        modelExceedsGpuVram(modelId: modelId, gpu: gpuInfo);
    if (gated) {
      if (!identical(_engine, primary) && _vramGatedEngine) return;
      _log.warning(
        'STT model $modelId needs more VRAM than the detected GPU has '
        '(${gpuInfo?.vramMB} MB) — loading on CPU',
      );
      _engine = ref.read(whisperCpuFallbackEngineProvider);
      _vramGatedEngine = true;
    } else if (_vramGatedEngine) {
      _vramGatedEngine = false;
      _engine = primary;
    }
  }

  /// Puts the hardware context of the engine load about to run into Sentry
  /// (breadcrumb plus scope tags and a `gpu` context), so a native crash is
  /// reported with the backend, GPU, VRAM and model it happened on. Only
  /// hardware and model identifiers go in: no paths and no transcript text.
  /// Sentry itself is inert when crash reporting is off (opt-out), so the
  /// consent gate needs no extra check here.
  void _recordGpuLoadContext({
    required WhisperBackend backend,
    required String modelId,
    required bool cudaPack,
  }) {
    final gpu = ref.read(hw.gpuInfoProvider).value;
    final vendor = gpu?.vendor.name ?? 'unknown';
    final gpuName = gpu?.name ?? 'unknown';
    final context = <String, Object?>{
      'backend': backend.name,
      'gpu_vendor': vendor,
      'gpu_name': gpuName,
      'gpu_vram_mb': gpu?.vramMB,
      'model_id': modelId,
      'model_ram_mb': hw.sttModelVramMB[modelId],
      'cuda_pack': cudaPack,
      'app_version': app.appVersion,
    };
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'STT load: backend=${backend.name} model=$modelId',
        category: 'stt.gpu',
        level: SentryLevel.info,
        data: context,
      ),
    );
    Sentry.configureScope((scope) {
      scope.setTag('stt_backend', backend.name);
      scope.setTag('gpu_vendor', vendor);
      scope.setTag('cuda_pack', cudaPack ? 'on' : 'off');
      scope.setContexts('gpu', context);
    });
  }

  Future<bool> _warmupInference() async {
    final sw = Stopwatch()..start();
    try {
      final silentWav = _generateSilentWav();
      await _engine!.transcribe(silentWav);
      sw.stop();
      _log.info(
        'Engine warmup inference completed in ${sw.elapsedMilliseconds}ms',
      );
      return true;
    } catch (e) {
      sw.stop();
      // Warning, not debug: a failed warm-up on a GPU backend is the first
      // sign of a broken backend and must reach the release log file.
      _log.warning('Engine warmup failed: $e');
      return false;
    }
  }

  /// Measures the real-time factor for [modelId] against the spoken benchmark
  /// clip via the engine seam (previously timed over HTTP against the
  /// whisper-server subprocess). Drives the onboarding quality-tier
  /// auto-selection.
  Future<void> _runBenchmark(String modelId) async {
    final tier = tierForModel(modelId);

    if (!ref.mounted) return;

    state = state.copyWith(isBenchmarking: true, benchmarkingTier: tier);

    try {
      final rtf = await _measureRtf();
      _log.info('Benchmark completed for $modelId: RTF=$rtf');

      if (ref.mounted) await _storeBenchmarkResult(modelId, rtf);
    } catch (e) {
      _log.debug('Benchmark failed: $e');
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          isBenchmarking: false,
          clearBenchmarkingTier: true,
        );
      }
    }
  }

  /// Queues the post-load benchmark, but lets the dictation pipeline go first.
  ///
  /// The whisper worker handles one request at a time and knows no priorities,
  /// so a benchmark inference fired while the user is already dictating puts
  /// their real transcription behind 3 s of synthetic audio. On a cold Metal
  /// context that cost 16 s in a captured session (hotkey at 14:19:05,
  /// transcript only at 14:19:37) — which reads as "the app stopped
  /// responding", not as "a benchmark is running".
  void _scheduleBenchmark(String modelId) {
    _pendingBenchmarkModelId = modelId;
    _maybeRunPendingBenchmark();
  }

  /// Queues a benchmark for [modelId] unless this machine already has a
  /// current result for its tier, so a normal start does not re-measure.
  Future<void> _scheduleBenchmarkIfStale(String modelId) async {
    final tier = tierForModel(modelId);
    if (tier == null) return;
    final generation = _benchmarkGeneration;
    try {
      final gpu = await ref.read(hw.gpuInfoProvider.future);
      if (!ref.mounted) return;
      final settings = ref.read(settingsProvider).value;
      final fresh = settings == null
          ? null
          : benchmarkRtfForMachine(
              benchmark: settings.benchmark,
              gpu: gpu,
              backend: _engine?.status.backend.name,
              appVersion: app.appVersion,
            );
      final freshRtf = fresh?[tier];
      if (freshRtf != null) {
        _rememberRtf(modelId, _engine?.status.backend.name, freshRtf);
        return;
      }
    } on Exception catch (e) {
      _log.debug('Benchmark freshness check failed: $e');
    }
    if (!ref.mounted || _benchmarkSuiteActive) return;
    if (generation != _benchmarkGeneration) return;
    _scheduleBenchmark(modelId);
  }

  /// Runs the pending benchmark if nothing else needs the worker; otherwise
  /// leaves it pending for [_rearmPendingBenchmark] to retry.
  void _maybeRunPendingBenchmark() {
    final modelId = _pendingBenchmarkModelId;
    if (modelId == null) return;
    if (_isRecordingActive || _transcribeInFlight > 0) {
      _log.debug('Benchmark deferred — dictation pipeline busy');
      return;
    }
    _pendingBenchmarkModelId = null;
    unawaited(_runBenchmark(modelId));
  }

  /// Retries a deferred benchmark once the pipeline has been quiet for
  /// [benchmarkIdleDelay]. Re-armed on every notification, so a burst of
  /// dictations keeps pushing the benchmark out rather than racing them.
  void _rearmPendingBenchmark() {
    if (_pendingBenchmarkModelId == null) return;
    _benchmarkDeferTimer?.cancel();
    _benchmarkDeferTimer = Timer(benchmarkIdleDelay, _maybeRunPendingBenchmark);
  }

  /// Loads the model on the engine [whisperEngineProvider] provides now,
  /// after one of its inputs changed (the CUDA pack was installed, or the
  /// comparison set it aside), so the next dictation does not pay for the
  /// load. Only when a model was loaded before, for the on-device whisper
  /// engine with its model on disk: an idle-unloaded engine stays unloaded.
  Future<void> reloadOnNewBackend() async {
    if (_activeModel == null && !state.isReady) return;
    final settings = ref.read(settingsProvider).value;
    if (settings == null ||
        !settings.sttProviderType.isLocal ||
        settings.onDeviceEngine != OnDeviceEngine.whisper ||
        !_isModelInstalled(settings.effectiveModelId)) {
      return;
    }
    // Reading rebuilds a provider whose inputs changed; the listener in
    // build() may follow it already, otherwise follow it here.
    final next = ref.read(whisperEngineProvider);
    if (!identical(next, _engine)) {
      _log.info('STT engine replaced — reloading now');
      unawaited(stop());
      _engine = next;
    }
    await prewarm();
  }

  /// Queues the CUDA/Vulkan comparison (#1670, `whisper/cuda_ab.dart`) for
  /// [modelId] when the model now runs on the CUDA pack and this setup has
  /// no result yet. It waits for a quiet pipeline, like the post-load
  /// benchmark, and never runs in the probe child, headless or under tests
  /// ([cudaAbEnabledProvider]).
  void _scheduleCudaAb(String modelId) {
    if (!ref.read(cudaAbEnabledProvider)) return;
    if (!_cudaAbApplies(modelId)) return;
    _pendingCudaAbModelId = modelId;
    _armCudaAb();
  }

  /// Whether the loaded engine runs [modelId] on a CUDA device of the pack
  /// and the comparison for this setup is still missing.
  bool _cudaAbApplies(String modelId) {
    final engine = _engine;
    if (engine == null || state.cpuFallbackActive) return false;
    if (ref.read(activeCudaPackDirProvider) == null) return false;
    if (engine.status.deviceBackend != WhisperBackend.cuda) return false;
    if (ref.read(cudaAbRecordProvider) != null) return false;
    return ref.read(settingsProvider).value?.effectiveModelId == modelId;
  }

  /// Whether a comparison is queued or running. Visible for tests.
  @visibleForTesting
  bool get cudaAbQueued => _pendingCudaAbModelId != null || _cudaAbRunning;

  void _armCudaAb() {
    _cudaAbTimer?.cancel();
    if (_pendingCudaAbModelId == null) return;
    _cudaAbTimer = Timer(cudaAbIdleDelay, _maybeRunCudaAb);
  }

  /// Starts the pending comparison once nothing else needs the GPU; checks
  /// again after [cudaAbIdleDelay] otherwise.
  void _maybeRunCudaAb() {
    final modelId = _pendingCudaAbModelId;
    if (modelId == null || !ref.mounted || _cudaAbRunning) return;
    if (_isRecordingActive ||
        _transcribeInFlight > 0 ||
        state.isBenchmarking ||
        _benchmarkSuiteActive ||
        _pendingBenchmarkModelId != null ||
        !state.isReady) {
      _armCudaAb();
      return;
    }
    _pendingCudaAbModelId = null;
    unawaited(_runCudaAb(modelId));
  }

  /// Measures the loaded CUDA engine against a temporary Vulkan engine with
  /// the same model and the spoken reference clip, stores the result and,
  /// when Vulkan wins, reloads the model on Vulkan. See `cuda_ab.dart`.
  Future<void> _runCudaAb(String modelId) async {
    final engine = _engine;
    final modelPath = sttModelPath(modelId);
    final pack = ref.read(cudaPackProvider).pack;
    final gpu = ref.read(hw.gpuInfoProvider).value;
    if (engine == null ||
        modelPath == null ||
        pack == null ||
        gpu == null ||
        state.modelId != modelId ||
        !_cudaAbApplies(modelId)) {
      return;
    }
    // Two contexts of the model on the card at once: skip a card without
    // room for the second, rather than pushing the dictation engine out.
    final needMb = hw.sttModelVramMB[modelId];
    final vramMb = gpu.vramMB;
    if (needMb != null &&
        vramMb != null &&
        needMb + kCudaAbSecondContextMb > vramMb) {
      _log.info(
        'CUDA/Vulkan comparison skipped: $modelId needs $needMb MB plus '
        '$kCudaAbSecondContextMb MB for the second context, the card has '
        '$vramMb MB',
      );
      return;
    }
    final key = cudaAbKey(
      gpu: gpu,
      appVersion: app.appVersion,
      packId: pack.id,
      modelId: modelId,
    );
    final generation = _benchmarkGeneration;
    final records = ref.read(cudaAbProvider.notifier);
    _cudaAbRunning = true;
    records.markPending(key);
    final total = Stopwatch()..start();
    _log.info('CUDA/Vulkan comparison started for $modelId');
    WhisperEngine? vulkan;
    CudaAbMeasurement result;
    Object? failure;
    try {
      final wav = await SttBenchmark.referenceWav();
      Future<int> timed(WhisperEngine e) async {
        final sw = benchmarkStopwatch()..start();
        await _nativeCall(() => e.transcribe(wav));
        return sw.elapsedMilliseconds;
      }

      result = await measureCudaAb(
        prepareVulkan: () async {
          final temp = ref.read(cudaAbVulkanEngineFactoryProvider)(
            engine.status.backend,
          );
          vulkan = temp;
          await _nativeCall(() => temp.load(modelPath: modelPath));
          final device = temp.status.deviceBackend;
          if (device != WhisperBackend.vulkan) {
            _log.warning(
              'CUDA/Vulkan comparison: temporary engine runs on '
              '${device.name}, not Vulkan',
            );
            return false;
          }
          return true;
        },
        timeCuda: () => timed(engine),
        timeVulkan: () => timed(vulkan!),
        shouldStop: () =>
            !ref.mounted ||
            _isRecordingActive ||
            _transcribeInFlight > 0 ||
            generation != _benchmarkGeneration ||
            !identical(_engine, engine),
      );
    } catch (e) {
      failure = e;
      result = const CudaAbMeasurement(abort: CudaAbAbort.noVulkan);
    } finally {
      final temp = vulkan;
      if (temp != null) {
        try {
          await _nativeCall(() => shutdownTemporaryEngine(temp));
        } catch (e) {
          _log.warning('Temporary Vulkan engine did not shut down: $e');
        }
      }
      _cudaAbRunning = false;
    }
    total.stop();
    if (!ref.mounted) return;

    if (result.abort == CudaAbAbort.busy) {
      records.clearPending(key);
      _log.info(
        'CUDA/Vulkan comparison paused after ${total.elapsedMilliseconds} ms '
        '(dictation or engine change); trying again later',
      );
      if (generation == _benchmarkGeneration && identical(_engine, engine)) {
        _pendingCudaAbModelId = modelId;
        _armCudaAb();
      }
      return;
    }
    if (!result.complete) {
      // No usable Vulkan side: keep CUDA for this setup instead of trying
      // again on every start.
      _log.warning(
        'CUDA/Vulkan comparison inconclusive '
        '(${failure ?? result.abort!.name}); keeping CUDA',
      );
      records.record(
        key,
        CudaAbRecord(
          winner: CudaAbWinner.cuda,
          measuredAt: DateTime.now(),
          interrupted: true,
        ),
      );
      return;
    }
    final winner = pickCudaAbWinner(
      cudaMs: result.cudaMs,
      vulkanMs: result.vulkanMs,
    );
    final record = CudaAbRecord(
      winner: winner,
      measuredAt: DateTime.now(),
      cudaMedianMs: medianMs(result.cudaMs),
      vulkanMedianMs: medianMs(result.vulkanMs),
    );
    _log.info(
      'CUDA/Vulkan comparison for $modelId: CUDA ${result.cudaMs} ms, '
      'Vulkan ${result.vulkanMs} ms (median ${record.cudaMedianMs} / '
      '${record.vulkanMedianMs}) — ${winner.name} stays; took '
      '${total.elapsedMilliseconds} ms',
    );
    records.record(key, record);
    if (winner == CudaAbWinner.vulkan) await reloadOnNewBackend();
  }

  /// Keeps the measured speed of [modelId] on [backend] for the budget.
  void _rememberRtf(String modelId, String? backend, double rtf) {
    _measuredRtf = rtf;
    _measuredRtfModel = modelId;
    _measuredRtfBackend = backend;
  }

  /// The measured RTF for the model and compute path [engine] runs now, or
  /// null (another model, or a CPU fallback after a GPU measurement).
  double? _rtfFor(WhisperEngine engine) {
    if (_measuredRtfModel == null || _measuredRtfModel != _activeModel) {
      return null;
    }
    if (_measuredRtfBackend != engine.status.backend.name) return null;
    return _measuredRtf;
  }

  Future<void> _storeBenchmarkResult(String modelId, double rtf) async {
    final backend = _engine?.status.backend.name;
    _rememberRtf(modelId, backend, rtf);
    try {
      final tier = tierForModel(modelId);
      if (tier == null) return;
      if (!ref.mounted) return;

      final gpuInfo = await ref.read(hw.gpuInfoProvider.future);
      if (!ref.mounted) return;
      final machineKey = benchmarkMachineKey(
        hardwareKey: benchmarkHardwareKey(gpuInfo),
        appVersion: app.appVersion,
      );

      // Results from another machine, build or compute path are not comparable
      // with this one: keep only the tiers measured under the same setup.
      final previous = ref.read(settingsProvider).value?.benchmark;
      final sameSetup =
          previous?.benchmarkHardwareId == machineKey &&
          previous?.benchmarkBackend == backend;
      final currentRtfMap = Map<QualityTier, double>.from(
        sameSetup ? previous?.tierBenchmarkRtf ?? {} : {},
      );
      currentRtfMap[tier] = rtf;

      await ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(
              tierBenchmarkRtf: currentRtfMap,
              benchmarkHardwareId: machineKey,
              benchmarkTimestamp: DateTime.now(),
              benchmarkBackend: backend,
            ),
          );

      _log.info('Benchmark stored: $modelId → tier=$tier, RTF=$rtf');
    } catch (e) {
      _log.debug('Failed to store benchmark: $e');
    }
  }

  static Uint8List _generateSilentWav() {
    const sampleRate = 16000;
    const durationSamples = sampleRate ~/ 4;
    const bitsPerSample = 16;
    const numChannels = 1;
    const bytesPerSample = bitsPerSample ~/ 8;
    const dataSize = durationSamples * numChannels * bytesPerSample;
    const headerSize = 44;

    final buffer = Uint8List(headerSize + dataSize);
    final data = ByteData.sublistView(buffer);

    buffer[0] = 0x52;
    buffer[1] = 0x49;
    buffer[2] = 0x46;
    buffer[3] = 0x46;
    data.setUint32(4, headerSize + dataSize - 8, Endian.little);
    buffer[8] = 0x57;
    buffer[9] = 0x41;
    buffer[10] = 0x56;
    buffer[11] = 0x45;
    buffer[12] = 0x66;
    buffer[13] = 0x6D;
    buffer[14] = 0x74;
    buffer[15] = 0x20;
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, numChannels * bytesPerSample, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    buffer[36] = 0x64;
    buffer[37] = 0x61;
    buffer[38] = 0x74;
    buffer[39] = 0x61;
    data.setUint32(40, dataSize, Endian.little);

    return buffer;
  }

  /// Runs the out-of-process GPU probe (gpu_probe.dart) before the first GPU
  /// load: the GPU backend first runs in a child process, and a GPU that
  /// crashed or hung there is not used in this process. An unknown verdict
  /// keeps the GPU path, with its crash marker. Only the first GPU load per
  /// probe key starts a child. Returns false when the notifier was disposed
  /// while probing.
  Future<bool> _probeGpuBeforeLoad(String modelId) async {
    final backend = _engine!.status.backend;
    if (backend == WhisperBackend.cpu) return true;
    final gpu = ref.read(hw.gpuInfoProvider).value;
    if (gpu == null) return true;
    final verdict = await ref
        .read(gpuProbeServiceProvider)
        .verdict(gpu: gpu, backend: backend.name, modelId: modelId);
    if (!ref.mounted) return false;
    if (verdict == GpuProbeVerdict.unusable) {
      _log.warning(
        '${backend.name} failed the GPU probe — loading $modelId on CPU',
      );
      _engine = ref.read(whisperCpuFallbackEngineProvider);
      // A verdict from a failed real load (#561) names that cause.
      final fromLoad = ref
          .read(gpuProbeServiceProvider)
          .unusableAfterLoad(gpu: gpu, backend: backend.name);
      ref
          .read(recoveryToastNotifierProvider.notifier)
          .report(
            fromLoad
                ? RecoveryToastKind.gpuLoadIncompatible
                : RecoveryToastKind.gpuProbeFailed,
          );
    }
    return true;
  }

  /// Returns the model file path when the file can be loaded. Otherwise the
  /// failure is reported (a truncated file also starts a silent re-download)
  /// and null is returned.
  Future<String?> _usableModelPath(String modelId) async {
    final modelPath = sttModelPath(modelId);
    if (modelPath == null) {
      _fail('stt_model_unknown', detail: 'no model file path for $modelId');
      return null;
    }

    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      _fail('stt_model_file_missing', detail: 'not found at $modelPath');
      return null;
    }

    const minModelBytes = 10 * 1024 * 1024;
    final modelFileSize = await modelFile.length();
    if (isSttModelFileTooSmall(modelFileSize, minModelBytes: minModelBytes)) {
      // Explicit capture under the canonical `sttModelCorrupted` bucket so
      // disk-truncated / interrupted-download model files surface as their
      // own Sentry issue instead of merging into the generic auto-escalate
      // catch-all via `_log.error`. Log is downgraded to warning to avoid
      // a second event from the AppLogger pipeline.
      ref.read(modelCorruptedReporterProvider).report(
        'STT model file corrupted on disk '
        '($modelFileSize bytes, expected >$minModelBytes)',
        {
          'model_id': modelId,
          'model_path': modelPath,
          'file_size_bytes': modelFileSize,
          'min_required_bytes': minModelBytes,
          'platform': Platform.operatingSystem,
        },
      );
      _log.warning(
        'STT model file appears corrupted: $modelPath '
        '($modelFileSize bytes, expected >$minModelBytes). '
        'Triggering silent re-download.',
      );
      await _redownloadDefectModel(modelId, modelFile);
      return null;
    }

    return modelPath;
  }

  /// Deletes the damaged [modelFile] and loads [modelId] again in the
  /// background; the engine parks in stopped meanwhile and starts with the
  /// next dictation. A catalog model only; for another file there is no
  /// download to repeat.
  Future<void> _redownloadDefectModel(String modelId, File modelFile) async {
    // Awaited: the re-download below checks for the file and must not see
    // it while this delete is still pending (Windows run10 race).
    try {
      await modelFile.delete();
    } on FileSystemException catch (e) {
      _log.warning('Failed to delete corrupt model file: $e');
    }
    if (!ref.mounted) return;
    // Mirror the pre-cutover self-heal: park in stopped, then trigger a
    // silent re-download via modelDownloadProvider.
    _transition(const SttStatus(serverState: SttServerState.stopped));
    unawaited(
      ref
          .read(modelDownloadProvider.notifier)
          .downloadModel(modelId)
          .catchError((Object e) {
            _log.warning(
              'Silent re-download of corrupt model $modelId failed: $e',
            );
          }),
    );
  }

  /// After a load failure that points at the file (#561): checks the model
  /// against its catalog hash. A damaged file is loaded again and true is
  /// returned (the start is over); an intact one, or a model outside the
  /// catalog, returns false and the caller goes on with the next step.
  Future<bool> _repairIfModelFileDefect(
    String modelId,
    String modelPath,
  ) async {
    final model = findSttModel(modelId);
    if (model == null) return false;
    final file = File(modelPath);
    final result = await ref
        .read(modelFileVerifierProvider)
        .verify(file, model.sha256);
    if (!ref.mounted) return true;
    if (result is VerificationOk) {
      _log.info('Model $modelId is intact; the load failure is not the file');
      return false;
    }
    // Same reporter as the size check: one event per session in total.
    ref.read(modelCorruptedReporterProvider).report(
      'STT model file failed its hash check after a load failure',
      {'model_id': modelId, 'platform': Platform.operatingSystem},
    );
    _log.warning('Model $modelId failed its hash check; loading it again');
    ref
        .read(recoveryToastNotifierProvider.notifier)
        .report(RecoveryToastKind.modelFileRepair);
    await _redownloadDefectModel(modelId, file);
    return true;
  }

  /// A GPU load failed for a hardware reason and the CPU took over (#561):
  /// remember it for this GPU, driver, OS and app version. This session
  /// already says so through the CPU fallback notice ([cpuFallbackActive]);
  /// the next start loads on the CPU at once and names the cause
  /// ([RecoveryToastKind.gpuLoadIncompatible], see [_probeGpuBeforeLoad]).
  ///
  /// macOS is deliberately left out: the service writes nothing there (ADR
  /// 0030 point 6), and a Metal load failure is covered by the crash marker.
  /// That is only about the GPU verdict. Repairing a damaged model file
  /// ([_repairIfModelFileDefect]) has no platform branch and runs the same on
  /// macOS, Windows and Linux.
  void _rememberGpuIncompatible(WhisperBackend backend, Object error) {
    final gpu = ref.read(hw.gpuInfoProvider).value;
    if (gpu == null) return;
    final reason = '$error';
    ref
        .read(gpuProbeServiceProvider)
        .recordLoadFailure(
          gpu: gpu,
          backend: backend.name,
          reason: reason.length > 200 ? reason.substring(0, 200) : reason,
        );
  }

  Future<void> _start({required String modelId, bool warmup = true}) async {
    _transition(const SttStatus(serverState: SttServerState.starting));

    final modelPath = await _usableModelPath(modelId);
    if (modelPath == null) return;

    _log.info('Loading STT model: $modelId ($modelPath)');

    // Out-of-process GPU probe (gpu_probe.dart), see _probeGpuBeforeLoad.
    if (!await _probeGpuBeforeLoad(modelId)) return;

    // Crash-loop breaker (see gpu_load_crash_guard.dart): a genuine native
    // fault has no catchable Dart exception and kills the whole process
    // before any code below ever runs. Mark intent to disk right before the
    // GPU-backed load, and keep it marked through the warmup inference below:
    // on old/weak GPUs the first *compute dispatch* (not the weight load
    // itself) is the more likely crash point, so clearing right after
    // `load()` would let that exact crash repeat the loop undetected. Only
    // clear once the process has provably survived both load AND the first
    // inference, or once the GPU path has been abandoned for CPU.
    final crashGuard = ref.read(gpuLoadCrashGuardProvider);
    if (_gpuRetryAfterCpuRun) {
      _gpuRetryAfterCpuRun = false;
      if (!crashGuard.crashedLastAttempt) {
        _engine = ref.read(whisperEngineProvider);
      }
    }
    _applyVramGate(modelId);
    final attemptingGpu = _engine!.status.backend != WhisperBackend.cpu;
    final cudaPack = ref.read(activeCudaPackDirProvider) != null;
    final attemptKey = GpuLoadCrashGuard.attemptKey(
      backend: _engine!.status.backend.name,
      modelId: modelId,
      appVersion: app.appVersion,
    );
    _recordGpuLoadContext(
      backend: _engine!.status.backend,
      modelId: modelId,
      cudaPack: cudaPack,
    );
    if (attemptingGpu) {
      crashGuard.markAttempt(cuda: cudaPack, key: attemptKey);
    }
    // Tracks whether the marker set above still needs clearing — a plain
    // bool rather than re-deriving from `attemptingGpu` at each call site,
    // so the catch branch's clear (GPU abandoned for CPU) and the
    // post-warmup clear (GPU path survived) can't both fire for one load.
    var gpuAttemptPending = attemptingGpu;

    try {
      _unloadedOnRelease = false;
      await _nativeCall(
        () => _engine!.load(
          modelPath: modelPath,
          vadModelPath: defaultWhisperVadModelPath(),
        ),
      );
    } catch (e) {
      if (gpuAttemptPending) {
        crashGuard.clearAttempt();
        gpuAttemptPending = false;
      }
      // FLUTTER_WHISPASTE-80: a GPU/driver cold-start (e.g. first-ever
      // shader compile) can hang past the engine's internal load timeout
      // and fail the whole session even though CPU would have worked fine.
      // Mirrors the existing GPU-crash-during-transcribe CPU fallback
      // (_transcribeResilient) — degrade once, don't just surface the raw
      // timeout to the user.
      // #561: a damaged file and an incompatible GPU need opposite answers.
      final failedBackend = _engine!.status.backend;
      final onGpu = failedBackend != WhisperBackend.cpu;
      final cause = classifyWhisperLoadFailure(e, onGpu: onGpu);
      _log.warning('STT model load failed on ${failedBackend.name}: $e');
      var fileChecked = false;
      // On the CPU no driver sits in between: check the file whatever the
      // message says (an I/O error can name a "device" too).
      if (cause == EngineLoadCause.fileDefect || !onGpu) {
        fileChecked = true;
        if (await _repairIfModelFileDefect(modelId, modelPath)) return;
      }
      if (!onGpu) {
        _fail('stt_model_load_failed', detail: '$e');
        return;
      }
      _log.warning(
        'STT model load failed on ${failedBackend.name} backend '
        '($e) — retrying once on CPU',
      );
      final cpuEngine = ref.read(whisperCpuFallbackEngineProvider);
      _recordGpuLoadContext(
        backend: WhisperBackend.cpu,
        modelId: modelId,
        cudaPack: false,
      );
      try {
        await cpuEngine.load(
          modelPath: modelPath,
          vadModelPath: defaultWhisperVadModelPath(),
        );
      } catch (cpuError) {
        // GPU and CPU both failed: then it is most likely the file after all.
        if (!fileChecked &&
            await _repairIfModelFileDefect(modelId, modelPath)) {
          return;
        }
        _fail('stt_model_load_failed', detail: 'CPU retry: $cpuError');
        return;
      }
      unawaited(_engine!.unload());
      _engine = cpuEngine;
      if (ref.mounted) {
        state = state.copyWith(cpuFallbackActive: true);
        if (!isTransientWhisperLoadFailure(e)) {
          _rememberGpuIncompatible(failedBackend, e);
        }
      }
    }
    if (!ref.mounted) {
      // The load returned, so the process survived it: no marker may stay
      // behind to be read as a crash on the next launch.
      if (gpuAttemptPending) crashGuard.clearAttempt();
      return;
    }

    _activeModel = modelId;
    _resetIdleTimer();

    final warmupOk = warmup ? await _warmupInference() : null;
    // Reaching here proves the process survived the first GPU compute
    // dispatch, not just the weight load — see the crash-loop-breaker
    // comment above. Only fires if the catch branch above didn't already
    // clear it (GPU abandoned for CPU before we got this far). The in-flight
    // marker is cleared either way (a Dart-level warmup exception is not a
    // native crash).
    if (gpuAttemptPending && warmup) {
      crashGuard.clearAttempt();
      gpuAttemptPending = false;
    }
    // The streak is not reset here. Only a real transcription on this same
    // key proves the GPU healthy (see [_settleCrashGuardAfterInference]); a
    // failed warm-up is no proof at all, so it leaves no reset pending.
    final gpuInUse = _engine!.status.backend != WhisperBackend.cpu;
    _crashStreakResetKey = gpuInUse && (!warmup || (warmupOk ?? false))
        ? attemptKey
        : null;
    // Without the warm-up the marker stays set until the first real inference
    // completes (see [_settleCrashGuardAfterInference]).
    _crashProofPending = gpuAttemptPending;
    // A user-triggered run measures its own tiers; it must not also queue the
    // automatic post-load benchmark.
    if (!_benchmarkSuiteActive) {
      unawaited(_scheduleBenchmarkIfStale(modelId));
      _scheduleCudaAb(modelId);
    }

    _transition(
      SttStatus(
        serverState: SttServerState.ready,
        modelId: modelId,
        // Preserve a load-time CPU fallback (FLUTTER_WHISPASTE-80) — this
        // constructs a fresh SttStatus rather than copyWith-ing the current
        // one, so cpuFallbackActive would otherwise silently reset to false.
        cpuFallbackActive: state.cpuFallbackActive,
        // The real backend this load ended up on — reads _engine.status
        // directly rather than trusting the pre-load `attemptingGpu` guess,
        // so it reflects the CPU swap above when that branch fired.
        backend: _engine!.status.deviceBackend,
      ),
    );
  }

  /// Removes a whisper decoder loop (one letter or the same sentence again
  /// and again), see [dropLetterLoops] and [collapseRepeatedSentences]. Clears
  /// the prompt memory when it fires, otherwise the loop primes the next
  /// recording and repeats there.
  String _collapseRepetitions(String text) {
    final collapsed = collapseRepeatedSentences(dropLetterLoops(text));
    if (collapsed != text) {
      _log.warning('Whisper hallucination detected: removed a decoder loop');
      _lastPrompt = null;
      _lastPromptTime = null;
    }
    return collapsed;
  }

  /// Enters the error state with a stable [code] (shown localized by the UI).
  /// Free text and paths go to the log only, never into the code.
  /// Error code for "the engine is still in native code; restart the app".
  static const _restartNeededCode = 'stt_engine_restart_needed';

  static const _expectedFailureCodes = {
    'stt_model_file_missing',
    'stt_model_unknown',
  };

  void _fail(String code, {String? detail}) {
    final line = 'STT error: $code${detail == null ? '' : ' ($detail)'}';
    // A model that is not downloaded yet is a user state the UI explains;
    // only real failures go to the error log and on to Sentry.
    if (_expectedFailureCodes.contains(code)) {
      _log.warning(line);
    } else {
      _log.error(line);
    }
    _transition(
      SttStatus(serverState: SttServerState.error, errorMessage: code),
    );
  }
}

// Providers are defined in stt_providers.dart and re-exported via stt_bundle.dart.

/// How a user-triggered benchmark run ended.
enum _BenchmarkOutcome { completed, cancelled, failed }

/// Which one-shot GPU recoveries one [SttServerStateNotifier] transcription
/// has already used, so each runs at most once per dictation.
/// A decode that ran out of its budget and stopped at the abort flag.
class _BudgetAbort implements Exception {
  const _BudgetAbort(this.budget);
  final Duration budget;
}

class _GpuRecoveryAttempts {
  bool cpuFallbackTried = false;
  bool backendRebuildTried = false;

  /// A GPU failure moved the run onto the CPU engine.
  bool swappedToCpu = false;

  /// The decode gate this run holds from its first GPU recovery until the run
  /// ends, so the retried decode proves the rebuilt context first.
  Completer<void>? gate;
}

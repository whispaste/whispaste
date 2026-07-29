/// Riverpod notifier that composes all STT sub-modules.
///
/// Re-exports [SttStatus] and [SttServerState] so external consumers can
/// import from this single file instead of hunting through the subsystem.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart'
    show Breadcrumb, Sentry, SentryLevel;

import '../../core/config/punctuation_priming_prompts.dart';
import '../../core/config/settings_provider.dart';
import '../../core/config/whisper_languages.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../core/logging/crash_reporter.dart';
import '../../core/recording/recording_state.dart' show SttServerState;
import '../hardware_info_service.dart' as hw;
import '../model_download_service.dart';
import '../path_service.dart';
import 'inference_client_rejected.dart';
import 'inference_request_validator.dart';
import 'stt_benchmark.dart' show SttBenchmark;
import 'wav_header_repair.dart';
import 'whisper/gpu_load_crash_guard.dart';
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
  });

  final SttServerState serverState;

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
    );
  }

  @override
  String toString() =>
      'SttStatus($serverState, port=$port, model=$modelId, '
      'benchmarking=$isBenchmarking, cpuFallback=$cpuFallbackActive)';
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

  /// Upper bound on the combined `vocab + lastPrompt` string used for
  /// pre-flight validation. The engine seam ([WhisperEngine.transcribe])
  /// has no prompt/vocab parameter yet, so [_resolveEffectivePrompt]'s
  /// result is validated but not forwarded — see the `decisions:` note in
  /// this issue's Evidence block.
  static const int _promptCharLimit = 1024;

  /// Stuck-Guard budget: a single in-flight [WhisperEngine.transcribe] that
  /// never returns is abandoned after this timeout with a clean error instead
  /// of hanging the app (CONTEXT.md §3.3). Mutable + [visibleForTesting] so
  /// resilience tests can shrink it to milliseconds; production keeps the 5 min
  /// budget the subprocess-era pipeline used.
  @visibleForTesting
  static Duration stuckGuardTimeout = const Duration(minutes: 5);

  /// Upper bound on automatic retries of a transient transcription failure
  /// before the error is surfaced (CONTEXT.md §3.3 — "bis zu 3 Wiederholungen").
  static const int _maxTranscribeRetries = 3;

  /// Pure decision policy for FFI-era transcription failures (CPU-fallback).
  static const _resiliencePolicy = WhisperResiliencePolicy();

  String? _activeModel;
  Timer? _idleTimer;
  String? _lastPrompt;
  DateTime? _lastPromptTime;
  static const _promptExpiry = Duration(minutes: 10);
  bool _idleExtended = false;
  bool _isRecordingActive = false;
  Completer<void>? _startCompleter;
  final Set<String> _modelLoadFailedIds = {};
  Timer? _modelChangeDebounce;

  // Nullable rather than `late final`: [FakeSttService]-style test doubles
  // override [build] entirely (skipping the assignment below) while
  // inheriting [stop] unmodified — a `late final` throws
  // `LateInitializationError` from `stop()` in that shape. Real callers
  // always go through [build] first (Riverpod builds before any method is
  // reachable), so `_engine!` is safe at every other call site.
  WhisperEngine? _engine;

  @override
  SttStatus build() {
    _engine = ref.read(whisperEngineProvider);

    ref.onDispose(() {
      _idleTimer?.cancel();
      _idleTimer = null;
      _modelChangeDebounce?.cancel();
      _modelChangeDebounce = null;
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

    return const SttStatus();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> ensureRunning() async {
    if (_startCompleter != null) {
      return _startCompleter!.future;
    }

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final modelId = settings.effectiveModelId;

    if (_activeModel != null && _activeModel != modelId) {
      _log.info('STT model changed ($_activeModel → $modelId), restarting');
      stop();
    }

    if (state.isReady && state.modelId == modelId) {
      _resetIdleTimer();
      _log.debug('STT engine already loaded (warm) for model $modelId');
      return;
    }

    if (_modelLoadFailedIds.contains(modelId)) {
      _fail(
        'STT model file is corrupted. '
        'Please re-download the model in Settings.',
      );
      return;
    }

    if (state.serverState != SttServerState.stopped) {
      stop();
    }

    _startCompleter = Completer<void>();
    try {
      await _start(modelId: modelId);
      _startCompleter?.complete();
    } on Exception catch (e) {
      _startCompleter?.completeError(e);
      rethrow;
    } finally {
      _startCompleter = null;
    }
  }

  Future<void> prewarm() async {
    try {
      await ensureRunning();
      _log.info('STT model pre-warmed (${state.modelId})');
    } on Exception catch (e) {
      _log.debug('Pre-warm skipped: $e');
    }
  }

  Future<void> runBenchmark() async {
    final currentModelId = state.modelId;
    if (currentModelId.isEmpty) {
      _log.debug('Cannot run benchmark: no model is currently active');
      return;
    }
    stop();
    try {
      await _start(modelId: currentModelId);
      _log.info('Re-benchmark completed for $currentModelId');
    } on Exception catch (e) {
      _log.debug('Re-benchmark failed: $e');
    }
  }

  void notifyRecordingStarted() {
    _isRecordingActive = true;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void notifyTranscriptionCompleted() {
    _isRecordingActive = false;
    _idleExtended = false;
    _resetIdleTimer(extendAfterTranscription: true);
  }

  void notifyRecordingStopped() {
    _isRecordingActive = false;
    _resetIdleTimer();
  }

  Future<String> transcribe(String wavFilePath, {String? language}) async {
    final file = File(wavFilePath);
    if (!file.existsSync()) {
      throw Exception('WAV file not found: $wavFilePath');
    }
    return transcribeBytes(await file.readAsBytes(), language: language);
  }

  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    if (!state.isReady) {
      throw StateError('STT server is not running');
    }

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
    final vocab = settings?.customVocabulary.trim() ?? '';
    final effectivePrompt = _resolveEffectivePrompt(
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

    final String rawText;
    try {
      rawText = await _transcribeResilient(
        payload,
        lang,
        effectivePrompt,
        wavBytes.length,
        audioDurationMs,
        settings?.stt.vadEnabled ?? true,
      );
    } catch (e) {
      stopwatch.stop();
      // The resilience wrapper already classified the failure and (for
      // surfaced failures) captured it to Sentry with the right fingerprint.
      // This warning is deliberately below the AppLogger auto-escalation
      // threshold so it does not add a second capture (see the dedup test).
      // The wrapped string preserves any `stt_cuda_oom` token so the
      // orchestrator's OOM-recovery path keeps firing unchanged.
      _log.warning('STT inference failed: $e');
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
    text = _stripNonSpeechMarkers(text);
    text = _collapseRepetitions(text);

    if (text.isNotEmpty) {
      _lastPrompt = text.length > 200
          ? text.substring(text.length - 200)
          : text;
      _lastPromptTime = DateTime.now();
    }

    return text;
  }

  /// Stops the engine. Returns a [Future] that completes once the native
  /// context is actually freed — callers that need the app to stay alive
  /// until then (app quit, see `app.dart`'s `onWindowClose`) must await it;
  /// existing fire-and-forget callers (model switch, provider change) can
  /// keep calling `stop()` without awaiting (FLUTTER_WHISPASTE-BC: the
  /// native free racing an imminent process exit is what crashes, not what
  /// this method itself does).
  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = null;
    _activeModel = null;
    _lastPrompt = null;
    _lastPromptTime = null;
    _idleExtended = false;
    _isRecordingActive = false;
    // Transition to stopped immediately (synchronously, before the first
    // await below) — UI responsiveness for the common case (model switch)
    // must not wait on native cleanup. The returned Future still resolves
    // only once the engine confirms it, for callers that need that
    // guarantee (app quit, see `app.dart`'s `onWindowClose`).
    _transition(const SttStatus());
    await (_engine?.unload() ?? Future<void>.value());
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
  String? _resolveEffectivePrompt(
    String vocab, {
    required String lang,
    required bool punctuationPriming,
  }) {
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
    final combined = <String>[
      if (vocab.isNotEmpty) vocab,
      if (promptValue != null && promptValue.isNotEmpty) promptValue,
    ].join(' ');
    if (combined.isNotEmpty) return combined;
    if (!punctuationPriming) return null;
    return resolvePunctuationPrimingPrompt(lang);
  }

  /// Runs [WhisperEngine.transcribe] behind the FFI resilience chain
  /// (CONTEXT.md §3.3), reacting to the engine's distinguishable
  /// [WhisperFailureKind] signals:
  ///
  /// - **Stuck-Guard** — the call is raced against [stuckGuardTimeout]; a hang
  ///   ends as a clean [WhisperFailureKind.timeout] error, never a deadlock.
  /// - **CPU-Fallback** — a [WhisperFailureKind.gpuCrash] degrades to CPU once
  ///   (`cpuFallbackActive` set) and retries.
  /// - **Retry** — a [WhisperFailureKind.transient] failure is retried up to
  ///   [_maxTranscribeRetries] times before being surfaced.
  /// - **OOM** — a [WhisperFailureKind.oom] is not retried here; it is captured
  ///   and rethrown carrying the `stt_cuda_oom` token so the orchestrator's
  ///   `OomRecoveryHandler` (smaller model / cloud) recovers it.
  ///
  /// Surfaced (unrecovered) failures are captured to Sentry with a stable
  /// fingerprint before the exception propagates.
  Future<String> _transcribeResilient(
    List<int> payload,
    String lang,
    String? prompt,
    int wavSizeBytes,
    int audioDurationMs,
    bool vadEnabled,
  ) async {
    var transientAttempts = 0;
    var cpuFallbackTried = false;

    while (true) {
      try {
        return await _engine!
            .transcribe(
              payload,
              language: lang,
              prompt: prompt,
              vadEnabled: vadEnabled,
            )
            .timeout(stuckGuardTimeout);
      } on TimeoutException {
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
        throw failure;
      } on WhisperEngineException catch (e) {
        switch (e.kind) {
          case WhisperFailureKind.gpuCrash:
            if (!cpuFallbackTried &&
                _resiliencePolicy.shouldRetryOnCpu(e.kind)) {
              cpuFallbackTried = true;
              if (ref.mounted) {
                state = state.copyWith(cpuFallbackActive: true);
              }
              _log.warning(
                'GPU crash during inference — degrading to CPU and retrying',
              );
              continue;
            }
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
      }
    }
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
    final baseMinutes = settings.sttIdleTimeoutMinutes;

    if (baseMinutes <= 0) return;

    var timeoutMinutes = baseMinutes;

    if (extendAfterTranscription && !_idleExtended) {
      timeoutMinutes = math.min(baseMinutes + 5, baseMinutes * 2);
      _idleExtended = true;
      _log.debug(
        'Idle timer extended: ${timeoutMinutes}min '
        '(base=${baseMinutes}min, burst=+5min)',
      );
    }

    final timeout = Duration(minutes: timeoutMinutes);
    _idleTimer = Timer(timeout, () {
      _log.info(
        'STT engine idle for ${timeout.inMinutes} min, '
        'unloading to free memory',
      );
      stop();
    });
  }

  void _debouncedPrewarmOnModelChange(String newModelId) {
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = Timer(const Duration(milliseconds: 500), () async {
      _log.info('Model changed to $newModelId, starting debounced pre-warm');

      final modelPath = sttModelPath(newModelId);
      if (modelPath == null || !await File(modelPath).exists()) {
        _log.debug('Model file not downloaded yet, skipping pre-warm');
        return;
      }

      if (state.serverState != SttServerState.stopped) stop();
      try {
        await ensureRunning();
        _log.info('Pre-warm after model change complete');
      } on Exception catch (e) {
        _log.debug('Pre-warm after model change skipped: $e');
      }
    });
  }

  /// Best-effort GPU/engine warmup so the first real dictation after a cold
  /// load doesn't pay the one-time kernel-compile/cache-fill penalty.
  /// Failures are non-fatal — mirrors the pre-cutover HTTP warmup's contract.
  Future<void> _warmupInference() async {
    final sw = Stopwatch()..start();
    try {
      final silentWav = _generateSilentWav();
      await _engine!.transcribe(silentWav);
      sw.stop();
      _log.info(
        'Engine warmup inference completed in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e) {
      sw.stop();
      _log.debug('Engine warmup skipped: $e');
    }
  }

  /// Measures the real-time factor for [modelId] against a 3 s benchmark WAV
  /// via the engine seam (previously timed over HTTP against the whisper-server
  /// subprocess). Drives the onboarding quality-tier auto-selection.
  Future<void> _runBenchmark(String modelId) async {
    final tier = tierForModel(modelId);

    if (!ref.mounted) return;

    state = state.copyWith(isBenchmarking: true, benchmarkingTier: tier);

    final sw = Stopwatch()..start();
    try {
      final benchmarkWav = SttBenchmark.generateBenchmarkWav();
      await _engine!.transcribe(benchmarkWav);
      sw.stop();

      const audioDurationMs = 3000;
      final rtf = sw.elapsedMilliseconds / audioDurationMs;

      _log.info(
        'Benchmark completed for $modelId: ${sw.elapsedMilliseconds}ms '
        '(RTF=$rtf)',
      );

      if (ref.mounted) await _storeBenchmarkResult(modelId, rtf);
    } catch (e) {
      sw.stop();
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

  Future<void> _storeBenchmarkResult(String modelId, double rtf) async {
    try {
      final tier = tierForModel(modelId);
      if (tier == null) return;
      if (!ref.mounted) return;

      final currentSettings = ref.read(settingsProvider).value;
      final currentRtfMap = Map<QualityTier, double>.from(
        currentSettings?.tierBenchmarkRtf ?? {},
      );
      currentRtfMap[tier] = rtf;

      final gpuInfo = await ref.read(hw.gpuInfoProvider.future);
      if (!ref.mounted) return;
      final hwId = gpuInfo.vendor == hw.GpuVendor.none
          ? 'cpu'
          : '${gpuInfo.vendor.name}_${gpuInfo.vramMB ?? 0}';

      await ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(
              tierBenchmarkRtf: currentRtfMap,
              benchmarkHardwareId: hwId,
              benchmarkTimestamp: DateTime.now(),
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

  Future<void> _start({required String modelId}) async {
    _transition(const SttStatus(serverState: SttServerState.starting));

    final modelPath = sttModelPath(modelId);
    if (modelPath == null) {
      _fail('Unknown STT model: $modelId');
      return;
    }

    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      _fail(
        'STT model file not found at $modelPath. '
        'Download the model first.',
      );
      return;
    }

    const minModelBytes = 10 * 1024 * 1024;
    final modelFileSize = await modelFile.length();
    if (isSttModelFileTooSmall(modelFileSize, minModelBytes: minModelBytes)) {
      // Explicit capture under the canonical `sttModelCorrupted` bucket so
      // disk-truncated / interrupted-download model files surface as their
      // own Sentry issue instead of merging into the generic auto-escalate
      // catch-all via `_log.error`. Log is downgraded to warning to avoid
      // a second event from the AppLogger pipeline.
      CrashReporter.instance?.captureError(
        message:
            'STT model file corrupted on disk '
            '($modelFileSize bytes, expected >$minModelBytes)',
        severity: 'error',
        type: 'stt_model_corrupted',
        fingerprint: const [sttModelCorrupted],
        extras: {
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
      unawaited(
        modelFile.delete().catchError((Object e) {
          _log.warning('Failed to delete corrupt model file: $e');
          return modelFile;
        }),
      );
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
      return;
    }

    _log.info('Loading STT model: $modelId ($modelPath)');

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
    final attemptingGpu = _engine!.status.backend != WhisperBackend.cpu;
    if (attemptingGpu) crashGuard.markAttempt();
    // Tracks whether the marker set above still needs clearing — a plain
    // bool rather than re-deriving from `attemptingGpu` at each call site,
    // so the catch branch's clear (GPU abandoned for CPU) and the
    // post-warmup clear (GPU path survived) can't both fire for one load.
    var gpuAttemptPending = attemptingGpu;

    try {
      await _engine!.load(
        modelPath: modelPath,
        vadModelPath: defaultWhisperVadModelPath(),
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
      if (_engine!.status.backend == WhisperBackend.cpu) {
        _fail('Failed to load STT model: $e');
        return;
      }
      _log.warning(
        'STT model load failed on ${_engine!.status.backend.name} backend '
        '($e) — retrying once on CPU',
      );
      final cpuEngine = ref.read(whisperCpuFallbackEngineProvider);
      try {
        await cpuEngine.load(
          modelPath: modelPath,
          vadModelPath: defaultWhisperVadModelPath(),
        );
      } catch (cpuError) {
        _fail('Failed to load STT model: $cpuError');
        return;
      }
      unawaited(_engine!.unload());
      _engine = cpuEngine;
      if (ref.mounted) {
        state = state.copyWith(cpuFallbackActive: true);
      }
    }
    if (!ref.mounted) return;

    _activeModel = modelId;
    _resetIdleTimer();

    await _warmupInference();
    // Reaching here proves the process survived the first GPU compute
    // dispatch, not just the weight load — see the crash-loop-breaker
    // comment above. Only fires if the catch branch above didn't already
    // clear it (GPU abandoned for CPU before we got this far). Also resets
    // the consecutive-crash streak: the GPU just proved itself, so any
    // prior crash(es) toward the two-strike threshold no longer apply.
    if (gpuAttemptPending) {
      crashGuard.clearAttempt();
      crashGuard.resetCrashStreak();
      gpuAttemptPending = false;
    }
    unawaited(_runBenchmark(modelId));

    _transition(
      SttStatus(
        serverState: SttServerState.ready,
        modelId: modelId,
        // Preserve a load-time CPU fallback (FLUTTER_WHISPASTE-80) — this
        // constructs a fresh SttStatus rather than copyWith-ing the current
        // one, so cpuFallbackActive would otherwise silently reset to false.
        cpuFallbackActive: state.cpuFallbackActive,
      ),
    );
  }

  /// Strips whisper.cpp non-speech annotations from the transcript.
  ///
  /// On silence or background noise, whisper emits bracketed sound tags
  /// instead of words — `[Musik]`, `[Music]`, `[BLANK_AUDIO]`, `[Applause]`,
  /// `[ Pause ]` and the like. These are never something the user dictated,
  /// yet they were being pasted into the active text field and saved to the
  /// history. whisper.cpp wraps these markers in square brackets, so we drop
  /// any token wholly enclosed in `[...]`. Round brackets are deliberately
  /// left untouched — a user may legitimately dictate parenthesised text,
  /// whereas square brackets effectively never occur in spoken input.
  ///
  /// If the whole transcript was nothing but such markers the result is the
  /// empty string, which the orchestrator already surfaces as
  /// `transcription_empty` instead of inserting noise.
  String _stripNonSpeechMarkers(String text) {
    if (text.isEmpty) return text;
    final stripped = text
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (stripped != text) {
      _log.info('Stripped non-speech markers from transcript');
    }
    return stripped;
  }

  String _collapseRepetitions(String text) {
    if (text.length < 20) return text;

    final sentences = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      buf.writeCharCode(text.codeUnitAt(i));
      final c = text[i];
      if (c == '.' || c == '?' || c == '!') {
        sentences.add(buf.toString().trim());
        buf.clear();
      }
    }
    final trailing = buf.toString().trim();
    if (trailing.isNotEmpty) sentences.add(trailing);

    if (sentences.length < 3) return text;

    final result = <String>[];
    var prevSentence = '';
    var runCount = 0;
    var hadRepetition = false;

    for (final s in sentences) {
      if (s == prevSentence) {
        runCount++;
        if (runCount < 3) {
          result.add(s);
        } else {
          hadRepetition = true;
        }
      } else {
        prevSentence = s;
        runCount = 1;
        result.add(s);
      }
    }

    if (hadRepetition) {
      _log.warning(
        'Whisper hallucination detected: collapsed ${sentences.length} '
        'sentences to ${result.length}',
      );
      _lastPrompt = null;
      _lastPromptTime = null;
    }

    return result.join(' ');
  }

  void _fail(String message) {
    _log.error('STT error: $message');
    _transition(
      SttStatus(serverState: SttServerState.error, errorMessage: message),
    );
  }
}

// Providers are defined in stt_providers.dart and re-exported via stt_bundle.dart.

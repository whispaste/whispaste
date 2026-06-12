/// Riverpod notifier that composes all STT sub-modules.
///
/// Re-exports [SttStatus] and [SttServerState] so external consumers can
/// import from this single file instead of hunting through the subsystem.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart'
    show Breadcrumb, Sentry, SentryLevel;

import '../../core/config/settings_provider.dart';
import '../../core/config/whisper_languages.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../core/logging/crash_reporter.dart';
import '../../core/recording/recording_state.dart' show SttServerState;
import '../hardware_info_service.dart' as hw;
import '../model_download_service.dart';
import '../path_service.dart';
import '../process_runner.dart';
import '../subprocess_guard.dart' as guard;
import 'inference_client_rejected.dart';
import 'inference_error_classifier.dart';
import 'inference_request_validator.dart';
import 'recovery_toast_notifier.dart';
import 'server_binary_recovery.dart';
import 'stt_exit_classifier.dart';
import 'stt_gpu_fallback_policy.dart';
import 'stt_providers.dart';
import 'stt_warm_liveness_policy.dart';
import 'wav_header_repair.dart';

// Re-export for external consumers.
export '../../core/recording/recording_state.dart' show SttServerState;
export 'server_binary_recovery.dart'
    show
        RecoveryExhausted,
        RecoveryExhaustedKind,
        RecoveryFellBackToCpu,
        RecoveryReason,
        RecoveryResult,
        RecoveryRetried,
        ServerBinaryRecovery,
        nextVariant;
export 'stt_exit_classifier.dart' show SttExitKind, classifySttExitCode;
export 'stt_gpu_fallback_policy.dart' show SttGpuFallbackPolicy;
export 'stt_providers.dart'
    show
        SttStartupHeartbeatConfig,
        processRunnerProvider,
        serverBinaryRecoveryProvider,
        sttHttpClientProvider,
        sttStartupHeartbeatConfigProvider;

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

/// Injectable seam for the Windows pre-launch backend-loader DLL gate
/// (`firstUnresolvableBackendLoaderDll`). The real implementation does
/// Windows-only filesystem I/O — it probes the server dir + `System32` for the
/// GPU build's load-time loader (`vulkan-1.dll` / the CUDA runtime). Routing the
/// call through a provider lets tests make the gate deterministic on every host
/// OS (the GPU-gating unit tests run on the Windows runner too, where the real
/// probe would otherwise see an empty server dir and short-circuit `_start`
/// before the `--no-gpu` args are built). Returns the name of the first
/// unresolvable loader DLL, or null when every required loader is present.
final backendLoaderGateProvider = Provider<String? Function(String)>(
  (ref) => hw.firstUnresolvableBackendLoaderDll,
);

/// Riverpod [Notifier] that composes [SttExitClassifier], [SttGpuFallbackPolicy],
/// [SttHealthProbe], [SttIdleTimer], [SttBenchmark] and [LocalSttServer] behind
/// a single [SttStatus] surface.
///
/// This is the public entry point for the new modular STT subsystem.
/// All callers use [localSttBundleProvider] since issue 15.
class SttServerStateNotifier extends Notifier<SttStatus> {
  static final _log = AppLogger('SttServerState');
  static const _cudaOomErrorCode = 'stt_cuda_oom';
  static const _maxStderrLines = 50;

  /// Pre-flight whitelist: the full 99-language catalog of the bundled
  /// multilingual Whisper models ([whisperLanguages]). `'auto'` bypasses
  /// the whitelist inside the validator. Until June 2026 this was a
  /// hard-coded en/de/fr/es subset, which wrongly rejected every other
  /// language the models support (store review: Russian).
  static final Set<String> _whisperSupportedLanguages = whisperLanguageCodes;

  /// Upper bound on the combined `vocab + lastPrompt` string handed to the
  /// whisper-server. The server itself accepts ~224 tokens (~900 chars) but
  /// we keep a conservative 1024-char cap so a runaway custom-vocab does
  /// not turn into a 413 on the inference response.
  static const int _promptCharLimit = 1024;

  Process? _process;
  String? _activeModel;
  Timer? _idleTimer;
  String? _lastPrompt;
  DateTime? _lastPromptTime;
  static const _promptExpiry = Duration(minutes: 10);
  bool _idleExtended = false;
  bool _isRecordingActive = false;
  Completer<void>? _startCompleter;
  bool _gpuFallbackActive = false;
  final Set<String> _modelLoadFailedIds = {};
  Timer? _modelChangeDebounce;

  late final http.Client _httpClient;
  late final ProcessRunner _processRunner;
  late final Duration _heartbeatWindow;
  late final int _heartbeatMaxMissedWindows;
  late final Duration _startupDeadline;

  static const _policy = SttGpuFallbackPolicy();

  @override
  SttStatus build() {
    _httpClient = ref.read(sttHttpClientProvider);
    _processRunner = ref.read(processRunnerProvider);
    final hbConfig = ref.read(sttStartupHeartbeatConfigProvider);
    _heartbeatWindow = hbConfig.window;
    _heartbeatMaxMissedWindows = hbConfig.maxMissedWindows;
    _startupDeadline = hbConfig.overallDeadline;

    ref.onDispose(() {
      _idleTimer?.cancel();
      _idleTimer = null;
      _modelChangeDebounce?.cancel();
      _modelChangeDebounce = null;
      _cleanupProcess();
      _lastPrompt = null;
      _lastPromptTime = null;
      _httpClient.close();
    });

    ref.listen(settingsProvider, (prev, next) {
      final prevSettings = prev?.value;
      final nextSettings = next.value;
      if (prevSettings == null || nextSettings == null) return;

      if (prevSettings.gpuAcceleration != nextSettings.gpuAcceleration ||
          prevSettings.effectiveModelId != nextSettings.effectiveModelId) {
        _gpuFallbackActive = false;
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

    if (state.isReady && state.modelId == modelId && _process != null) {
      final port = state.port;
      final livenessResult = await SttWarmLivenessPolicy().checkWithGrace(
        () => _quickHealthCheck(port),
      );
      if (livenessResult == WarmLivenessResult.healthy) {
        _resetIdleTimer();
        _log.debug('STT server already running (warm) on port $port');
        return;
      }
      _log.info('STT warm liveness grace exhausted on port $port — restarting');
      _cleanupProcess();
    }

    if (_startCompleter != null) {
      return _startCompleter!.future;
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
      await _start(
        modelId: modelId,
        gpuAcceleration: _gpuFallbackActive
            ? 'disabled'
            : settings.gpuAcceleration,
      );
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
      _log.info('STT server pre-warmed on port ${state.port}');
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
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      await _start(
        modelId: currentModelId,
        gpuAcceleration: _gpuFallbackActive
            ? 'disabled'
            : settings.gpuAcceleration,
      );
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
      'STT inference: port=${state.port} model=${state.modelId} '
      'wavBytes=${wavBytes.length} lang=$lang',
    );
    final stopwatch = Stopwatch()..start();

    // Materialize the payload as a [Uint8List] once so both the pre-flight
    // validator and the multipart request use the same byte view.
    final wavView = wavBytes is Uint8List
        ? wavBytes
        : Uint8List.fromList(wavBytes);

    // Derive audio duration (16 kHz mono 16-bit + 44-byte header). Used by
    // breadcrumb extras and the classifier context. Clamped at zero so the
    // empty-WAV reject path does not produce a negative value.
    final audioDurationMs = wavBytes.length > 44
        ? ((wavBytes.length - 44) / 32000 * 1000).round()
        : 0;

    final settings = ref.read(settingsProvider).value;
    final vocab = settings?.customVocabulary.trim() ?? '';
    final effectivePrompt = _resolveEffectivePrompt(vocab);

    // ── Pre-flight validation ─────────────────────────────────────────────
    // Reject obvious-garbage requests before they leave the process. Sentry
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
    // zeroed RIFF/data size fields — whisper-server rejects that container
    // with HTTP 400 "Invalid request". The sizes are derivable from the byte
    // length, so repair them instead of losing the user's dictation. The
    // breadcrumb keeps a field signal for how often this still fires.
    final payload = _repairWavIfNeeded(
      wavView,
      audioDurationMs,
      wavBytes.length,
    );

    final request = _buildInferenceRequest(
      payload: payload,
      lang: lang,
      effectivePrompt: effectivePrompt,
    );

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _httpClient
          .send(request)
          .timeout(
            const Duration(seconds: 300),
            onTimeout: () => throw TimeoutException(
              'STT inference timed out after 300s',
              const Duration(seconds: 300),
            ),
          );
    } on SocketException catch (e) {
      _captureInferenceConnectionLost(
        exceptionType: 'SocketException',
        exceptionMessage: '$e',
        audioDurationMs: audioDurationMs,
        wavBytes: wavBytes.length,
        language: lang,
        gpuMode: settings?.gpuAcceleration,
      );
      throw Exception(
        'STT server connection lost during inference (server may have crashed)',
      );
    } on http.ClientException catch (e) {
      _captureInferenceConnectionLost(
        exceptionType: 'ClientException',
        exceptionMessage: '$e',
        audioDurationMs: audioDurationMs,
        wavBytes: wavBytes.length,
        language: lang,
        gpuMode: settings?.gpuAcceleration,
      );
      throw Exception(
        'STT server connection lost during inference (server may have crashed)',
      );
    }
    final responseBody = await streamedResponse.stream.bytesToString();

    stopwatch.stop();
    _log.info(
      'STT inference response: status=${streamedResponse.statusCode} '
      'duration=${stopwatch.elapsedMilliseconds}ms bodyLen=${responseBody.length}',
    );

    if (streamedResponse.statusCode != 200) {
      // Classify the non-2xx response and emit exactly one Sentry capture
      // with a stable fingerprint + redacted body + six request extras.
      // The orchestrator path that rethrows this HttpException no longer
      // logs the failure at SEVERE level — that line was downgraded to
      // `_log.warning` to prevent the AppLogger's auto-escalation pipeline
      // from emitting a duplicate Sentry event under a different
      // fingerprint. See `CHANGELOG.md` — Unreleased.
      final failure = InferenceErrorClassifier.classify(
        statusCode: streamedResponse.statusCode,
        responseBody: responseBody,
        context: InferenceRequestContext(
          wavSizeBytes: wavBytes.length,
          audioDurationMs: audioDurationMs,
          language: lang,
          modelId: state.modelId,
          promptLength: effectivePrompt?.length ?? 0,
          vocabLength: vocab.length,
        ),
      );
      CrashReporter.instance?.captureError(
        message: 'STT inference failed (HTTP ${streamedResponse.statusCode})',
        severity: 'error',
        type: 'stt_inference_failed',
        fingerprint: [failure.fingerprint],
        extras: <String, dynamic>{
          ...failure.extras,
          'response_body': failure.redactedBody,
        },
      );
      throw HttpException(
        'Inference failed (HTTP ${streamedResponse.statusCode}): '
        '$responseBody',
      );
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    var text = (json['text'] as String? ?? '').trim();

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

  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = null;
    _cleanupProcess();
    _lastPrompt = null;
    _lastPromptTime = null;
    _idleExtended = false;
    _isRecordingActive = false;
    _transition(const SttStatus());
  }

  // ---------------------------------------------------------------------------
  // transcribeBytes helpers
  // ---------------------------------------------------------------------------

  /// Builds the effective prompt from the custom vocabulary setting and the
  /// rolling context window, updating [_lastPrompt]/[_lastPromptTime] on
  /// expiry.  Extracted from [transcribeBytes] to lower its cyclomatic count.
  String? _resolveEffectivePrompt(String vocab) {
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
    return combined.isEmpty ? null : combined;
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

  /// Assembles the multipart inference request for [payload], setting the
  /// optional language and prompt fields only when non-empty / non-null.
  http.MultipartRequest _buildInferenceRequest({
    required Uint8List payload,
    required String lang,
    required String? effectivePrompt,
  }) {
    final uri = Uri.parse('${state.endpoint}/inference');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes('file', payload, filename: 'audio.wav'),
      )
      ..fields['response_format'] = 'json'
      ..fields['temperature'] = '0.0';

    // `auto` is sent explicitly: whisper-server resolves an *omitted* field
    // to its startup default (`en` unless --language was passed), which
    // silently disabled language detection for auto-detect users.
    if (lang.isNotEmpty) {
      request.fields['language'] = lang;
    }
    if (effectivePrompt != null) {
      request.fields['prompt'] = effectivePrompt;
    }
    return request;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _transition(SttStatus next) {
    // Every state mutation flows through here, so a single mounted-guard
    // covers async resumes that race the provider container shutdown
    // (test teardown, app quit, hot-reload). Without it, a recovery
    // chain that completes after the scope is torn down throws a
    // "Cannot use the Ref … after it has been disposed" deep in
    // `_attemptRecovery` and surfaces as a "failed after test
    // completion" flake on CI.
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
    if (next.port > 0) extra.write(' port=${next.port}');
    if (next.modelId.isNotEmpty) extra.write(' model=${next.modelId}');
    if (next.errorMessage != null) extra.write(' error="${next.errorMessage}"');

    _log.info('STT lifecycle: $prev → ${next.serverState}$extra');
  }

  void _cleanupProcess() {
    final proc = _process;
    _process = null;
    _activeModel = null;

    if (proc != null) {
      try {
        proc.kill();
        proc.exitCode
            .timeout(const Duration(seconds: 2), onTimeout: () => -1)
            .then((_) {});
      } on ProcessException catch (e) {
        _log.debug('Kill whisper-server: $e');
      }
      guard.deletePid('whisper-server');
    }
  }

  Future<bool> _quickHealthCheck(int port) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse('http://127.0.0.1:$port/health');
      final resp = await _httpClient
          .get(uri)
          .timeout(const Duration(milliseconds: 500));
      sw.stop();
      final ok = resp.statusCode == 200;
      _log.debug(
        'Health check: ${ok ? "ok" : "status=${resp.statusCode}"} '
        '(${sw.elapsedMilliseconds}ms)',
      );
      return ok;
    } on Exception catch (e) {
      sw.stop();
      _log.debug('Health check: failed (${sw.elapsedMilliseconds}ms) $e');
      return false;
    }
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
        'STT server idle for ${timeout.inMinutes} min, '
        'shutting down to free GPU memory',
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
      final serverPath = whisperServerPath();
      if (!await File(serverPath).exists()) {
        _log.debug('Server binary not downloaded yet, skipping pre-warm');
        return;
      }

      if (_process != null) stop();
      try {
        await ensureRunning();
        _log.info('Pre-warm after model change complete');
      } on Exception catch (e) {
        _log.debug('Pre-warm after model change skipped: $e');
      }
    });
  }

  Future<void> _warmupInference(int port) async {
    final sw = Stopwatch()..start();
    try {
      final silentWav = _generateSilentWav();
      final uri = Uri.parse('http://127.0.0.1:$port/inference');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            silentWav,
            filename: 'warmup.wav',
          ),
        )
        ..fields['response_format'] = 'json'
        ..fields['temperature'] = '0.0';

      final response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 30));
      await response.stream.drain<void>();
      sw.stop();
      _log.info(
        'GPU warmup inference completed in ${sw.elapsedMilliseconds}ms',
      );
    } on Exception catch (e) {
      sw.stop();
      _log.debug('GPU warmup skipped: $e');
    }
  }

  Future<void> _runBenchmark(int port, String modelId) async {
    final tier = tierForModel(modelId);

    if (!ref.mounted) return;

    state = state.copyWith(isBenchmarking: true, benchmarkingTier: tier);

    final sw = Stopwatch()..start();
    try {
      final benchmarkWav = _generateBenchmarkWav();
      final uri = Uri.parse('http://127.0.0.1:$port/inference');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            benchmarkWav,
            filename: 'benchmark.wav',
          ),
        )
        ..fields['response_format'] = 'json'
        ..fields['temperature'] = '0.0';

      final response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 30));
      await response.stream.drain<void>();
      sw.stop();

      const audioDurationMs = 3000;
      final rtf = sw.elapsedMilliseconds / audioDurationMs;

      _log.info(
        'Benchmark completed for $modelId: ${sw.elapsedMilliseconds}ms '
        '(RTF=$rtf)',
      );

      if (ref.mounted) await _storeBenchmarkResult(modelId, rtf);
    } on Exception catch (e) {
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

  static Uint8List _generateBenchmarkWav() {
    const sampleRate = 16000;
    const durationSeconds = 3;
    const durationSamples = sampleRate * durationSeconds;
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

  Future<void> _start({
    required String modelId,
    required String gpuAcceleration,
  }) async {
    _transition(const SttStatus(serverState: SttServerState.starting));

    final serverPath = whisperServerPath();
    final modelPath = sttModelPath(modelId);

    if (modelPath == null) {
      _fail('Unknown STT model: $modelId');
      return;
    }

    if (!await File(serverPath).exists()) {
      _fail(
        'whisper-server executable not found at $serverPath. '
        'Download the local transcription runtime first.',
      );
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
      // Mirror the SHA-mismatch self-heal: park in stopped, then trigger a
      // silent re-download via modelDownloadProvider — identical to the
      // hashMismatch path in _handleModelLoadFailure.
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

    final int port;
    try {
      final socket = await ServerSocket.bind('127.0.0.1', 0);
      port = socket.port;
      await socket.close();
    } on SocketException catch (e) {
      _fail('Cannot find free port: $e');
      return;
    }

    // Route GPU detection through `gpuInfoProvider` so test overrides
    // actually take effect. The direct `hw.detectGpu()` call here used to
    // bypass the Riverpod override entirely, which made the Windows CI
    // runner spin up real WMI/PowerShell probes inside unit tests —
    // polluting Sentry-spy lists and blowing the recovery-path timing
    // windows that those tests rely on.
    final gpu = await ref.read(hw.gpuInfoProvider.future);
    if (!ref.mounted) return;
    _log.info(
      'GPU: ${gpu.name} (${gpu.vendor.name}, backend=${gpu.optimalBackend})',
    );

    if (!hw.isServerBinaryCompatible(sttDir(), gpu)) {
      // State-sync correction, not a crash: the installed binary's backend
      // does not match what the current GPU needs. With CPU binaries now
      // treated as universally compatible (see [hw.isServerBinaryCompatible],
      // the FLUTTER_WHISPASTE-80 loop fix), this only fires on a genuine
      // hardware/driver change — e.g. the STT dir moved to a machine with a
      // different GPU vendor, so a stored `cuda` binary no longer fits.
      //
      // `validateAndCleanIncompatibleBinary` (main.dart, unawaited) normally
      // heals this silently at startup; reaching here is a race with that
      // task. Hand off to the download notifier's self-heal instead of
      // dead-ending with a user-facing "re-download in Settings" error:
      // `invalidateServerBinary` deletes the wrong variant AND pulls the
      // correct one in the background, so the next recording just works.
      // `_log.warning` (not `_fail`/`_log.error`) keeps this off the Sentry
      // auto-escalate path. If the re-pulled GPU build then fails to start,
      // ServerBinaryRecovery drops to the now-durable CPU fallback.
      _log.warning(
        'Proactive check: server binary incompatible with current GPU '
        '(${gpu.vendor.name}, needs backend=${gpu.optimalBackend}). '
        'Triggering silent self-heal re-download.',
      );
      _transition(const SttStatus(serverState: SttServerState.stopped));
      unawaited(
        ref
            .read(modelDownloadProvider.notifier)
            .invalidateServerBinary()
            .catchError((Object e) {
              _log.warning('Self-heal re-download failed: $e');
            }),
      );
      return;
    }

    // ── Pre-launch dependency gate (Windows GPU builds) ────────────────────
    // The installed GPU-variant binary imports a system loader DLL at LOAD
    // time — `vulkan-1.dll` for the Vulkan build, the CUDA runtime for cuda —
    // that the (statically linked) GGML backend needs but that is NOT bundled
    // beside the binary. On a machine whose driver never shipped that loader
    // (e.g. a Kepler GTX 6xx routed to the Vulkan build), spawning the binary
    // aborts with STATUS_DLL_NOT_FOUND (0xC0000135) BEFORE it reads `--no-gpu`,
    // so a same-binary CPU retry cannot help — FLUTTER_WHISPASTE-A0. Detect
    // the unresolvable loader here and hand the variant swap to
    // ServerBinaryRecovery (which drops to the dependency-free CPU/BLAS build)
    // *before* the crash, rather than relying on the post-mortem exit
    // classifier. The proactive `isServerBinaryCompatible` check above only
    // matches backend-to-GPU-vendor; it does not verify the loader is present.
    if (Platform.isWindows && gpuAcceleration != 'disabled') {
      final missingLoader = ref.read(backendLoaderGateProvider)(sttDir());
      if (missingLoader != null) {
        _log.warning(
          'Pre-launch gate: GPU speech engine needs "$missingLoader" but the '
          'system cannot resolve it — switching to the CPU build before launch '
          'to avoid STATUS_DLL_NOT_FOUND.',
        );
        _process = null;
        _activeModel = null;
        unawaited(
          _attemptRecovery(
            reason: RecoveryReason.dllMissing,
            gpu: gpu,
            modelId: modelId,
          ),
        );
        return;
      }
    }

    // ── Proactive GPU capability gate ─────────────────────────────────────────
    // Precedence:
    //   1. User override (`enabled`/`disabled`): respect as-is.
    //   2. `auto` + shouldUseGpu==false: route to CPU without a Sentry error.
    //      This avoids the slow reactive stall→CPU path for known-bad GPUs
    //      (Kepler/Fermi NVIDIA, old AMD GCN). The reactive _gpuFallbackActive
    //      path remains the safety net for unknown/missed cases.
    //   3. `auto` + shouldUseGpu==true: normal auto-path continues below.
    final effectiveGpuAcceleration =
        (gpuAcceleration == 'auto' && !hw.shouldUseGpu(gpu))
        ? 'disabled'
        : gpuAcceleration;

    if (effectiveGpuAcceleration != gpuAcceleration) {
      _log.info(
        'GPU capability gate: proactively routing "${gpu.name}" to CPU '
        '(shouldUseGpu=false, user setting=$gpuAcceleration). '
        'Reactive fallback remains active.',
      );
    }

    final threads = _threadCount(effectiveGpuAcceleration);
    // FLUTTER_WHISPASTE-A0: under the Microsoft Store / MSIX build the spawned
    // whisper-server child does not inherit the parent's AppData redirection,
    // so the virtualized `%APPDATA%\WhisPaste\…` path resolves to an empty real
    // Roaming dir for the child ("search path … does not exist" → exit 3). Hand
    // the child the physical package-local path instead. No-op off MSIX.
    final childModelPath = deVirtualizeMsixChildPath(modelPath);
    final args = _serverArgs(
      modelPath: childModelPath,
      port: port,
      threads: threads,
      gpuMode: effectiveGpuAcceleration,
      gpu: gpu,
    );

    _log.info(
      'Starting whisper-server: model=$modelId threads=$threads '
      'gpu=$effectiveGpuAcceleration port=$port',
    );
    _log.info('Command: $serverPath ${args.join(' ')}');

    if (Platform.isMacOS) {
      await Process.run('xattr', ['-d', 'com.apple.quarantine', serverPath]);
    }

    // Launch with the server binary's own directory as the working directory
    // so the variants that DO ship sibling DLLs (cuda: cublas64_12 / ggml-cuda;
    // blas: ggml-blas / libopenblas) resolve them at runtime regardless of the
    // inherited cwd. NOTE: this is defence-in-depth, not the FLUTTER_WHISPASTE-A0
    // fix — the A0 STATUS_DLL_NOT_FOUND (0xC0000135) root cause is a missing
    // *system* loader (vulkan-1.dll) for the GPU build, which no working
    // directory can supply; that is handled by the pre-launch dependency gate
    // above (`hw.firstUnresolvableBackendLoaderDll`). A Windows smoke test
    // confirmed the model loads with cwd=System32 too, so the working directory
    // alone was never the blocker.
    // Launch via the child-resolvable path too (FLUTTER_WHISPASTE-A0): the
    // child derives its own module directory — and thus its ggml backend-DLL
    // search path — from the path it was launched with, so launching via the
    // virtualized path makes it scan an empty real Roaming dir. The physical
    // path keeps both the model arg and the backend search consistent.
    final childServerPath = deVirtualizeMsixChildPath(serverPath);
    final serverDir = File(childServerPath).parent.path;

    final Process proc;
    try {
      proc = await _processRunner.start(
        childServerPath,
        args,
        workingDirectory: serverDir,
      );
    } on ProcessException catch (e, st) {
      // Spawn failure (binary missing, path invalid, exec bit, ENOENT, …).
      // Previously only `_fail()`'d into local state — Sentry never saw it,
      // which made "whisper-server doesn't start" reports undiagnosable on
      // Windows where this is the common 1.2.x failure shape.
      CrashReporter.instance?.captureError(
        message: 'Failed to spawn whisper-server: ${e.message}',
        error: e,
        stackTrace: st,
        severity: 'error',
        type: 'stt_spawn_failed',
        fingerprint: const [sttSpawnFailed],
        extras: {
          'binary_path': serverPath,
          'args': args,
          'errno': e.errorCode,
          'os_message': e.message,
          'platform': Platform.operatingSystem,
          'model_id': modelId,
          'gpu_mode': effectiveGpuAcceleration,
        },
      );
      _fail('Failed to start whisper-server: $e');
      return;
    }

    _process = proc;
    guard.writePid('whisper-server', proc.pid);

    final stderrLines = <String>[];
    // Single-element list used as a mutable bool reference so that
    // `_recordStderrLine` (a class method, not a closure) can set the flag
    // and the `exitCode.then(...)` callback can read its final value.
    final sawCudaOom = [false];

    proc.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) => _log.debug('whisper-server: $line'));

    final stderrBroadcast = proc.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    stderrBroadcast.listen(
      (line) => _recordStderrLine(line, stderrLines, sawCudaOom),
    );

    unawaited(
      proc.exitCode.then((code) {
        _handleProcessExit(
          code: code,
          proc: proc,
          modelId: modelId,
          gpu: gpu,
          stderrLines: stderrLines,
          sawCudaOom: sawCudaOom[0],
          args: args,
          serverPath: serverPath,
          gpuAcceleration: effectiveGpuAcceleration,
        );
      }),
    );

    _transition(
      SttStatus(
        serverState: SttServerState.starting,
        port: port,
        modelId: modelId,
      ),
    );

    final coldStart = Stopwatch()..start();
    final startupFailed = await _awaitServerReady(
      port: port,
      proc: proc,
      stderrBroadcast: stderrBroadcast,
      stderrLines: stderrLines,
      args: args,
      serverPath: serverPath,
      modelId: modelId,
      gpuAcceleration: effectiveGpuAcceleration,
      gpu: gpu,
    );
    if (startupFailed) return;
    coldStart.stop();

    _activeModel = modelId;
    _resetIdleTimer();

    _log.info(
      'STT cold start completed in ${coldStart.elapsedMilliseconds}ms '
      'on port $port (model=$modelId)',
    );

    if (gpu.vramMB != null) {
      final requiredVram = hw.sttModelVramMB[_activeModel] ?? 0;
      if (requiredVram > gpu.vramMB!) {
        _log.warning(
          'Model "$_activeModel" requires ~${requiredVram}MB VRAM '
          'but GPU has ${gpu.vramMB}MB — risk of crash/inference failure.',
        );
      }
    }

    await _warmupInference(port);
    unawaited(_runBenchmark(port, modelId));

    _transition(
      SttStatus(
        serverState: SttServerState.ready,
        port: port,
        modelId: modelId,
        cpuFallbackActive: _gpuFallbackActive,
      ),
    );
  }

  Future<void> _waitReady(
    int port,
    Process proc,
    Stream<String> stderrLines, {
    Duration heartbeatWindow = const Duration(seconds: 60),
    int maxMissedWindows = 3,
    Duration overallDeadline = const Duration(seconds: 180),
  }) async {
    final healthUrl = Uri.parse('http://127.0.0.1:$port/health');
    final client = _httpClient;
    var interval = const Duration(milliseconds: 100);
    const maxInterval = Duration(seconds: 1);
    var iteration = 0;

    var missedWindows = 0;
    var windowStart = DateTime.now();
    final deadlineAt = DateTime.now().add(overallDeadline);

    final stderrSub = stderrLines.listen((_) {
      windowStart = DateTime.now();
      missedWindows = 0;
    });

    try {
      while (true) {
        if (_process != proc) {
          throw _EarlyExitException(
            'whisper-server exited before becoming ready',
          );
        }

        if (DateTime.now().isAfter(deadlineAt)) {
          throw _StartupDeadlineException(
            'whisper-server still not ready after '
            '${overallDeadline.inSeconds}s wall-clock deadline',
          );
        }

        final elapsed = DateTime.now().difference(windowStart);
        if (elapsed >= heartbeatWindow) {
          missedWindows++;
          _log.warning(
            'STT startup: no stderr progress for '
            '${heartbeatWindow.inSeconds}s '
            '(missed window $missedWindows/$maxMissedWindows)',
          );
          if (missedWindows >= maxMissedWindows) {
            throw _HeartbeatTimeoutException(
              'whisper-server made no progress for '
              '${maxMissedWindows * heartbeatWindow.inSeconds}s '
              '($maxMissedWindows consecutive ${heartbeatWindow.inSeconds}s '
              'windows without stderr output)',
            );
          }
          windowStart = DateTime.now();
        }

        try {
          final resp = await client
              .get(healthUrl)
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode == 200) return;

          if (iteration % 10 == 9) {
            _log.info(
              'STT server loading model... '
              '(${iteration + 1}s, status=${resp.statusCode})',
            );
          }
        } on Exception {
          if (iteration % 10 == 9) {
            _log.info('STT server not reachable yet (${iteration + 1}s)');
          }
        }

        iteration++;
        await Future<void>.delayed(interval);

        final nextMs = (interval.inMilliseconds * 1.5).round();
        interval = Duration(
          milliseconds: math.min(nextMs, maxInterval.inMilliseconds),
        );
      }
    } finally {
      await stderrSub.cancel();
    }
  }

  List<String> _serverArgs({
    required String modelPath,
    required int port,
    required int threads,
    required String gpuMode,
    required hw.GpuInfo gpu,
  }) {
    final args = <String>[
      '--model',
      modelPath,
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
      '--threads',
      '$threads',
      '--no-timestamps',
      '--entropy-thold',
      '2.6',
      '--logprob-thold',
      '-1.0',
    ];

    final useGpu = gpuMode != 'disabled';
    if (!useGpu) {
      args.add('--no-gpu');
    } else {
      if (gpu.supportsFlashAttn) {
        args.add('--flash-attn');
      } else {
        // The whisper-server binary defaults flash-attn ON on GPU builds.
        // Explicitly disable it on GPUs that do not support it to prevent an
        // illegal-instruction abort (e.g. Maxwell GTX 9xx, Pascal GTX 10xx).
        args.add('--no-flash-attn');
      }
    }

    return args;
  }

  int _threadCount(String gpuMode) {
    final cores = Platform.numberOfProcessors;
    if (gpuMode != 'disabled') {
      final n = (cores * 3) ~/ 4;
      return n.clamp(2, 8);
    }
    return (cores - 1).clamp(2, 12);
  }

  bool _looksLikeCudaOom(String message) {
    final hasGpuContext =
        message.contains('cuda') ||
        message.contains('cublas') ||
        message.contains('ggml_cuda') ||
        message.contains('gpu');

    return message.contains('cuda out of memory') ||
        message.contains('cublas_status_alloc_failed') ||
        (hasGpuContext && message.contains('out of memory')) ||
        (hasGpuContext && message.contains('failed to allocate'));
  }

  bool _stderrHasCudaOom(List<String> stderrLines) {
    for (final line in stderrLines) {
      if (_looksLikeCudaOom(line.toLowerCase())) return true;
    }
    return false;
  }

  void _handleCudaOom({
    required Process proc,
    required String failedModelId,
    required hw.GpuInfo gpu,
    required List<String> stderrLines,
  }) {
    if (_process != proc) return;

    _process = null;
    _activeModel = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = null;

    final requiredVramMB = hw.sttModelVramMB[failedModelId];

    // Downgraded from error → warning so AppLogger's auto-escalation does
    // not also emit a duplicate event under the `appLoggerAutoEscalated`
    // bucket — the explicit capture below carries the full hardware
    // context and owns the Sentry signal for this path.
    _log.warning(
      'whisper-server hit CUDA OOM for model=$failedModelId '
      'gpu=${gpu.name} stderr=${stderrLines.join(' | ')} '
      'errorCode=$_cudaOomErrorCode',
    );

    CrashReporter.instance?.captureError(
      message: 'whisper-server CUDA OOM on "${gpu.name}"',
      severity: 'error',
      type: 'stt_cuda_oom',
      fingerprint: const [sttCudaOom],
      extras: {
        'model_id': failedModelId,
        'gpu_vendor': gpu.vendor.name,
        'gpu_name': gpu.name,
        'gpu_vram_mb': gpu.vramMB,
        'required_vram_mb': requiredVramMB,
        'cuda_available': gpu.cudaAvailable,
        'vulkan_available': gpu.vulkanAvailable,
        'platform': Platform.operatingSystem,
        'stderr_tail': stderrLines,
      },
    );

    _transition(
      const SttStatus(
        serverState: SttServerState.error,
        errorMessage: _cudaOomErrorCode,
      ),
    );
  }

  /// Inference-time socket loss capture — used when the whisper-server
  /// dies while answering /inference. Downgrades the in-process log to
  /// warning so AppLogger's auto-escalation does not duplicate the
  /// explicit fingerprinted capture below.
  void _captureInferenceConnectionLost({
    required String exceptionType,
    required String exceptionMessage,
    required int audioDurationMs,
    required int wavBytes,
    required String language,
    required String? gpuMode,
  }) {
    _log.warning(
      'STT server connection lost during inference ($exceptionType): '
      '$exceptionMessage',
    );
    CrashReporter.instance?.captureError(
      message:
          'STT server connection lost during inference '
          '($exceptionType)',
      severity: 'error',
      type: 'stt_inference_connection_lost',
      fingerprint: const [sttInferenceConnectionLost],
      extras: {
        'exception_type': exceptionType,
        'exception_message': exceptionMessage,
        'model_id': state.modelId,
        'port': state.port,
        'wav_bytes': wavBytes,
        'audio_duration_ms': audioDurationMs,
        'language': language,
        'gpu_mode': gpuMode ?? '<unknown>',
        'cpu_fallback_active': _gpuFallbackActive,
        'platform': Platform.operatingSystem,
      },
    );
  }

  Future<void> _handleModelLoadFailure({
    required String modelId,
    required int exitCode,
    List<String> stderrLines = const <String>[],
  }) async {
    final modelInfo = findSttModel(modelId);
    final modelPath = sttModelPath(modelId);

    // Exit code 3 alone does NOT mean "binary/model ABI mismatch". whisper.cpp
    // also exits 3 when it cannot even open the model file
    // (`whisper_init_from_file…: failed to open '<path>'`). On the GTX 650 /
    // GTX 650 Kepler repro (FLUTTER_WHISPASTE-A0) the model SHA-256 verified intact
    // moments earlier, so the SHA-only heuristic mislabelled a file-access
    // fault as ABI drift and kicked off a pointless vulkan→cpu binary
    // fallback. A different binary variant cannot fix a path/access fault, so
    // we short-circuit here: surface an honest error and capture a distinct
    // signal instead of handing the crash to ServerBinaryRecovery.
    if (classifyModelLoadFailure(stderrLines) ==
        ModelLoadFailureCause.fileUnreadable) {
      _log.warning(
        'whisper-server could not open model $modelId (code $exitCode): the '
        'file is present and intact but unreadable by the server process — '
        'this is a path/launch-context fault, not an ABI mismatch. '
        'stderr=${stderrLines.join(' | ')}',
      );
      CrashReporter.instance?.captureError(
        message: 'whisper-server could not open model file',
        severity: 'error',
        type: 'stt_model_file_unreadable',
        fingerprint: const [sttModelFileUnreadable],
        extras: {
          'model_id': modelId,
          'model_path': modelPath ?? '<unknown>',
          'exit_code': exitCode,
          'stderr_tail': stderrLines,
          'platform': Platform.operatingSystem,
        },
      );
      _process = null;
      _activeModel = null;
      _transition(
        const SttStatus(
          serverState: SttServerState.error,
          errorMessage:
              'Sprachdienst kann das Sprachmodell nicht öffnen, obwohl die '
              'Datei vorhanden ist. Bitte WhisPaste neu starten. Tritt das '
              'erneut auf, erstelle bitte über „Debug-Informationen kopieren" '
              'eine Diagnose und sende sie uns.',
        ),
      );
      return;
    }

    bool hashMismatch = false;
    if (modelInfo != null && modelPath != null) {
      try {
        final file = File(modelPath);
        if (await file.exists()) {
          final digest = await crypto.sha256.bind(file.openRead()).first;
          final actualHash = digest.toString();
          hashMismatch = actualHash != modelInfo.sha256;
          if (hashMismatch) {
            _log.warning(
              'Exit code $exitCode: model SHA-256 mismatch for $modelId '
              '(expected=${modelInfo.sha256.substring(0, 8)}… '
              'actual=${actualHash.substring(0, 8)}…). '
              'File is corrupted — triggering silent re-download.',
            );
          } else {
            // Warning instead of error: the ServerBinaryRecovery
            // exhausted-path owns the Sentry signal under
            // `sttModelAbiMismatch`. Auto-escalation here would only
            // bucket a duplicate under the catch-all.
            _log.warning(
              'Exit code $exitCode: model SHA-256 is correct for $modelId '
              '— runtime incompatibility (binary/model ABI mismatch).',
            );
          }
        }
      } catch (e) {
        _log.warning('SHA-256 check failed for $modelId: $e');
        hashMismatch = true;
      }
    }

    if (hashMismatch) {
      _log.info('Triggering silent re-download for corrupted model $modelId');
      _transition(const SttStatus(serverState: SttServerState.stopped));
      unawaited(
        ref
            .read(modelDownloadProvider.notifier)
            .downloadModel(modelId)
            .catchError((Object e) {
              _log.warning('Silent re-download of $modelId failed: $e');
            }),
      );
      return;
    }

    // Warning instead of error: the ServerBinaryRecovery exhausted-path
    // owns the Sentry signal under `sttModelAbiMismatch`. Auto-escalation
    // here would only bucket a duplicate under the catch-all.
    _log.warning(
      'whisper-server failed to load model $modelId (code $exitCode): '
      'incompatible runtime — model file is intact but cannot be loaded '
      'by the installed whisper-server binary.',
    );

    // PRD Modul 1: ABI-mismatch is one of the three crash paths that hand
    // off to ServerBinaryRecovery. The old behaviour was to surface a
    // generic "re-download in Settings" string and wait for the user; the
    // recovery orchestrator instead picks the next-most-conservative
    // server variant, downloads it, and restarts the server so the next
    // recording works without further interaction. Sentry capture happens
    // only on RecoveryExhausted (inside the orchestrator).
    // Route GPU detection through `gpuInfoProvider` (same rationale as
    // `_start`) so tests can pin a deterministic GpuInfo via Riverpod
    // override instead of triggering real WMI/PowerShell probes on the
    // Windows CI runner.
    final gpu = await ref.read(hw.gpuInfoProvider.future);
    if (!ref.mounted) return;
    await _attemptRecovery(
      reason: RecoveryReason.abiMismatch,
      gpu: gpu,
      modelId: modelId,
    );
  }

  /// Hands a recoverable server-binary crash to [ServerBinaryRecovery]
  /// and reacts to the sealed [RecoveryResult] — either restarts the
  /// whisper-server with the new variant (so the next `startRecording()`
  /// just works), or transitions to `error` with the PRD-spec German
  /// user message when no fallback variant is left.
  Future<void> _attemptRecovery({
    required RecoveryReason reason,
    required hw.GpuInfo gpu,
    required String modelId,
  }) async {
    final recovery = ref.read(serverBinaryRecoveryProvider);

    // Move the surface state to `stopped` while recovery is in flight so
    // any UI listening to `SttStatus.serverState` knows the previous
    // process is gone, and push the PRD's
    // „Lade Sprachmodell neu — bitte warten." info-toast on the
    // abiMismatch path. The UI listener (`recording_behavior.dart`)
    // picks it up and renders the passive (no-action) toast.
    _transition(const SttStatus(serverState: SttServerState.stopped));
    if (reason == RecoveryReason.abiMismatch && ref.mounted) {
      ref
          .read(recoveryToastNotifierProvider.notifier)
          .report(RecoveryToastKind.abiInfo);
    }

    final RecoveryResult result;
    try {
      result = await recovery.recover(
        reason: reason,
        gpu: gpu,
        sttDirPath: sttDir(),
        activeModelId: modelId,
      );
    } on Object catch (e, st) {
      // Defensive: the recovery orchestrator should not throw — it
      // returns RecoveryExhausted instead. If it does, treat that as
      // exhausted so we still surface the actionable message.
      _log.error('ServerBinaryRecovery threw unexpectedly: $e\n$st');
      // Push the actionable „Einstellungen öffnen" toast to the UI; the
      // listener in `recording_behavior.dart` navigates to the
      // `cloud_advanced_section` reset area on tap. `ref.mounted`
      // guards against the post-completion-async-leak case — see the
      // identical guard in the RecoveryExhausted branch below.
      if (ref.mounted) {
        ref
            .read(recoveryToastNotifierProvider.notifier)
            .report(RecoveryToastKind.exhausted);
      }
      _transition(
        const SttStatus(
          serverState: SttServerState.error,
          errorMessage:
              'Sprachdienst kann nicht starten. '
              'Bitte App neu starten oder Sprachmodell neu laden.',
        ),
      );
      return;
    }

    switch (result) {
      case RecoveryRetried(:final chosenVariant):
        _log.info(
          'Recovery succeeded — retrying with variant "$chosenVariant"; '
          'restarting whisper-server.',
        );
        // Same-GPU retry: let the GPU-acceleration setting drive the
        // next launch (no forced CPU-fallback).
        await _restartAfterRecovery(forceCpu: false);
        return;
      case RecoveryFellBackToCpu():
        _log.info(
          'Recovery fell back to CPU variant — restarting in CPU mode.',
        );
        _gpuFallbackActive = true;
        await _restartAfterRecovery(forceCpu: true);
        return;
      case RecoveryExhausted(:final userMessage, :final kind):
        // Warning instead of error: `ServerBinaryRecovery._exhaust`
        // already captured a dedicated Sentry event under the
        // reason-specific fingerprint. Auto-escalating here would only
        // emit a duplicate in the catch-all bucket.
        _log.warning('Recovery exhausted — surfacing actionable error state.');
        // Push the actionable toast to the UI; the listener in
        // `recording_behavior.dart` navigates to the
        // `cloud_advanced_section` reset area on tap (generic) or opens the
        // VC++ Redistributable download (vcRuntimeMissing). The
        // `ref.mounted` guard mirrors the `ref.invalidate` call below —
        // without it, a recovery completing after the provider container
        // has been torn down (test teardown, app shutdown) throws an async
        // leak into a disposed Riverpod scope.
        if (ref.mounted) {
          ref
              .read(recoveryToastNotifierProvider.notifier)
              .report(
                kind == RecoveryExhaustedKind.vcRuntimeMissing
                    ? RecoveryToastKind.vcRuntimeMissing
                    : RecoveryToastKind.exhausted,
              );
        }
        _transition(
          SttStatus(
            serverState: SttServerState.error,
            errorMessage: userMessage,
          ),
        );
        return;
    }
  }

  /// Arms the one-shot CPU fallback for a GPU launch that *stalled* during
  /// startup — either a silent stall ([_HeartbeatTimeoutException]) or an
  /// alive-but-never-ready stall ([_StartupDeadlineException]) — and kicks
  /// off an immediate CPU restart.
  ///
  /// A stall produces no process exit code, so the `proc.exitCode` switch
  /// (gpuFatal / heapCorruption / abnormal-exit arms) never runs and the
  /// working CPU floor would otherwise never be tried. The field shape this
  /// closes is FLUTTER_WHISPASTE-9W: a Vulkan build on a Kepler GeForce
  /// GTX 6xx (or an old AMD card) that allocates all its compute buffers and
  /// then hangs — the GTX-650 report where the exit-code-only fallback
  /// (commit `33c6150f`) did not help.
  ///
  /// Returns `true` when the fallback was armed and a CPU restart kicked off
  /// (the caller then returns without emitting a Sentry capture, matching
  /// the "successful auto-recovery emits no Sentry event" convention).
  /// Returns `false` — leaving the caller to capture + fail — when there is
  /// no meaningful CPU fallback to make:
  ///   - already in CPU fallback this session (`_gpuFallbackActive`), or
  ///   - the launch was already CPU-only (`gpuAcceleration == 'disabled'`), or
  ///   - the host has no real GPU (`!gpu.hasGpu`) — a stall there is a disk /
  ///     model-load problem, not a GPU one, and `--no-gpu` would not change
  ///     anything.
  Future<bool> _tryStallCpuFallback({
    required hw.GpuInfo gpu,
    required String gpuAcceleration,
    required String stallKind,
  }) async {
    final launchedOnGpu = gpuAcceleration != 'disabled';
    if (_gpuFallbackActive || !launchedOnGpu || !gpu.hasGpu) return false;

    _gpuFallbackActive = true;
    // Warning, not error: a recovered stall is not a crash, and `_log.error`
    // would auto-escalate into the catch-all Sentry bucket.
    _log.warning(
      'whisper-server $stallKind on "${gpu.name}" GPU launch — activating '
      'one-shot CPU fallback and restarting in CPU mode.',
    );
    stop();
    await _restartAfterRecovery(forceCpu: true);
    return true;
  }

  /// Restarts the whisper-server after a successful recovery — clears any
  /// in-flight startCompleter, drops the just-killed process handle, and
  /// drives `ensureRunning()` so the next `startRecording()` call just
  /// works.
  Future<void> _restartAfterRecovery({required bool forceCpu}) async {
    // Make sure we don't deadlock against a stale startCompleter from
    // the crashed launch.
    _startCompleter = null;
    _process = null;
    _activeModel = null;

    // Drop the GPU-detection cache so the post-recovery launch re-probes
    // the hardware. Cheap (~100–500ms) and re-arms the once-per-session
    // `gpuDetectionFailed` capture guard — if the second detection is
    // also blind, Sentry sees that explicitly instead of silently
    // inheriting a stale „using CPU" cache from app start. Also
    // invalidate the Riverpod cache so the next `ref.read` inside
    // `_start` actually re-runs `detectGpu()` instead of returning the
    // cached future from before the recovery.
    hw.clearGpuCache();
    if (ref.mounted) ref.invalidate(hw.gpuInfoProvider);

    try {
      await ensureRunning();
    } on Exception catch (e) {
      _log.warning('Auto-restart after recovery failed: $e');
      // Leave whatever state ensureRunning left us in; if it set an
      // error message, the UI already has something to show.
    }
  }

  // ---------------------------------------------------------------------------
  // _start helpers
  // ---------------------------------------------------------------------------

  /// Appends a whisper-server stderr [line] to [buffer], updates the
  /// [sawCudaOom] flag (index 0), and emits a Sentry breadcrumb for lines
  /// that look like errors.  Extracted from [_start] to lower its cyclomatic
  /// count; behaviour is identical to the original `rememberStderr` closure.
  void _recordStderrLine(
    String line,
    List<String> buffer,
    List<bool> sawCudaOom,
  ) {
    final normalized = line.trim();
    if (normalized.isEmpty) return;
    buffer.add(normalized);
    if (buffer.length > _maxStderrLines) buffer.removeAt(0);
    final lower = normalized.toLowerCase();
    if (_looksLikeCudaOom(lower)) sawCudaOom[0] = true;
    final looksBad =
        lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('fatal') ||
        lower.contains('abort');
    if (looksBad) {
      _log.warning('whisper-server: $normalized');
      // Selective Sentry breadcrumb: only the lines that look like they
      // describe a problem. Goal is to attach the stderr signal to ANY
      // Sentry event captured shortly after (not just the dedicated
      // stt_exit captures, which already carry the full tail). Trimmed
      // to 500 chars to avoid blowing the breadcrumb size budget.
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: normalized.length > 500
              ? '${normalized.substring(0, 500)}…'
              : normalized,
          category: 'stt.stderr',
          level: SentryLevel.warning,
        ),
      );
    } else {
      _log.debug('whisper-server: $normalized');
    }
  }

  /// Handles the process exit event fired by [proc.exitCode.then(...)].
  /// Extracted from [_start] to lower its cyclomatic count.  All captured
  /// variables are passed explicitly so this method can be unit-tested in
  /// isolation.  [sawCudaOom] is evaluated at call-time (when the exit fires),
  /// matching the original closure-capture semantics exactly.
  void _handleProcessExit({
    required int code,
    required Process proc,
    required String modelId,
    required hw.GpuInfo gpu,
    required List<String> stderrLines,
    required bool sawCudaOom,
    required List<String> args,
    required String serverPath,
    required String gpuAcceleration,
  }) {
    if (_process != proc) return;

    guard.deletePid('whisper-server');
    if (sawCudaOom || _stderrHasCudaOom(stderrLines)) {
      _handleCudaOom(
        proc: proc,
        failedModelId: modelId,
        gpu: gpu,
        stderrLines: stderrLines,
      );
      return;
    }

    final exitKind = classifySttExitCode(code);
    // Map the classifier output to a constant from the central fingerprint
    // inventory.  Each exit-kind keeps its own Sentry bucket; modelLoad
    // branches to ABI-mismatch vs corrupted later inside
    // `_handleModelLoadFailure`, so the bucket here is only a default for
    // branches that capture before the SHA check.
    final fingerprint = switch (exitKind) {
      SttExitKind.dllMissing ||
      SttExitKind.dllEntryPoint => const [sttExitDllMissing],
      SttExitKind.gpuFatal => const [sttExitGpuFatal],
      SttExitKind.heapCorruption => const [sttExitHeapCorruption],
      // modelLoad doesn't capture directly here — see
      // `_handleModelLoadFailure` for the corrupted vs ABI split.
      SttExitKind.modelLoad => const [sttModelAbiMismatch],
      SttExitKind.other => const [sttExitOther],
    };

    // Use the GPU fallback policy to decide if CPU retry is warranted.
    final shouldFallback = _policy.shouldRetryOnCpu(exitKind);

    switch (exitKind) {
      case SttExitKind.dllMissing:
      case SttExitKind.dllEntryPoint:
        // PRD Modul 1: hand the crash to ServerBinaryRecovery rather than
        // capturing here.  The orchestrator picks the next-most-conservative
        // variant, downloads it, validates it, and tells us whether to
        // restart, fall back to CPU, or surface an exhausted-toast.  Sentry
        // capture happens only on RecoveryExhausted (inside the orchestrator),
        // matching the AC "successful Auto-Recoveries do not emit a Sentry
        // event".
        _log.warning(
          'DLL crash (${exitKind.name}, code $code) — '
          'invoking ServerBinaryRecovery.',
        );
        _process = null;
        _activeModel = null;
        final reason = exitKind == SttExitKind.dllMissing
            ? RecoveryReason.dllMissing
            : RecoveryReason.dllEntryPoint;
        unawaited(_attemptRecovery(reason: reason, gpu: gpu, modelId: modelId));
        return;

      case SttExitKind.gpuFatal:
        if (!_gpuFallbackActive && shouldFallback) {
          _gpuFallbackActive = true;
          _log.warning(
            'GPU fatal abort (code $code / ${exitKind.name}) on '
            '"${gpu.name}" — CPU fallback activated.',
          );
          _process = null;
          _activeModel = null;
          _transition(const SttStatus(serverState: SttServerState.stopped));
          return;
        }
        final gpuFatalMsg =
            'whisper-server GPU fatal abort (code $code / ${exitKind.name}) '
            'on "${gpu.name}" and CPU fallback also failed.';
        // Warning instead of error: the explicit captureError below owns the
        // Sentry signal under `sttExitGpuFatal`; an additional `_log.error`
        // would trigger AppLogger auto-escalation into the catch-all bucket.
        _log.warning(gpuFatalMsg);
        CrashReporter.instance?.captureError(
          message: gpuFatalMsg,
          severity: 'error',
          type: 'stt_exit',
          fingerprint: fingerprint,
        );
        _process = null;
        _activeModel = null;
        _transition(
          SttStatus(
            serverState: SttServerState.error,
            errorMessage:
                'Speech engine failed on both GPU and CPU (code $code). '
                'Please restart the app or re-download the model.',
          ),
        );
        return;

      case SttExitKind.heapCorruption:
        if (!_gpuFallbackActive && shouldFallback) {
          _gpuFallbackActive = true;
          _log.warning(
            'Memory error (${exitKind.name}, code $code) on '
            '"${gpu.name}" — CPU fallback activated.',
          );
          _process = null;
          _activeModel = null;
          _transition(const SttStatus(serverState: SttServerState.stopped));
          return;
        }
        final heapMsg =
            'whisper-server memory error (${exitKind.name}, code $code) '
            'and CPU fallback also failed.';
        // Warning instead of error: avoids duplicate Sentry event via
        // AppLogger auto-escalation; explicit capture below owns the
        // `sttExitHeapCorruption` signal.
        _log.warning(heapMsg);
        CrashReporter.instance?.captureError(
          message: heapMsg,
          severity: 'error',
          type: 'stt_exit',
          fingerprint: fingerprint,
        );
        _process = null;
        _activeModel = null;
        _transition(
          SttStatus(
            serverState: SttServerState.error,
            errorMessage:
                'Speech engine failed on both GPU and CPU (code $code). '
                'Please restart the app or re-download the model.',
          ),
        );
        return;

      case SttExitKind.modelLoad:
        _process = null;
        _activeModel = null;
        unawaited(
          _handleModelLoadFailure(
            modelId: modelId,
            exitCode: code,
            stderrLines: List<String>.of(stderrLines),
          ),
        );
        return;

      case SttExitKind.other:
        // An abnormal termination (negative exit code: Windows raw DWORD
        // crash like -1, or POSIX signal kill) on a GPU launch is, in the
        // field, almost always a GPU runtime the card cannot initialise —
        // e.g. the cuda12 build on a Kepler GTX 6xx (FLUTTER_WHISPASTE-6X
        // / -39).  Give CPU exactly one shot, guarded by `_gpuFallbackActive`
        // so a CPU binary that also dies cannot loop.  A clean positive exit
        // (e.g. 99) is a deliberate server exit that CPU mode would not fix.
        final launchedOnGpu = gpuAcceleration != 'disabled';
        final abnormalTermination = code < 0;
        if (!_gpuFallbackActive && launchedOnGpu && abnormalTermination) {
          _gpuFallbackActive = true;
          _log.warning(
            'whisper-server abnormal exit (code $code / ${exitKind.name}) '
            'on "${gpu.name}" — CPU fallback activated.',
          );
          _process = null;
          _activeModel = null;
          _transition(const SttStatus(serverState: SttServerState.stopped));
          return;
        }
        final otherMsg = 'whisper-server exited unexpectedly (code $code)';
        // Warning instead of error: avoids duplicate Sentry event via
        // AppLogger auto-escalation; explicit capture below owns the
        // `sttExitOther` signal with full diagnostic context.
        _log.warning(otherMsg);
        CrashReporter.instance?.captureError(
          message: otherMsg,
          severity: 'error',
          type: 'stt_exit',
          fingerprint: fingerprint,
          extras: {
            'exit_code': code,
            'exit_kind': exitKind.name,
            'stderr_tail': stderrLines,
            'args': args,
            'binary_path': serverPath,
            'model_id': modelId,
            'gpu_mode': gpuAcceleration,
            'gpu_fallback_active': _gpuFallbackActive,
            'platform': Platform.operatingSystem,
          },
        );
        _process = null;
        _activeModel = null;
        _transition(
          SttStatus(
            serverState: SttServerState.error,
            errorMessage:
                'whisper-server exited before becoming ready (code $code)',
          ),
        );
        return;
    }
  }

  /// Calls [_waitReady] and handles the three startup-failure exceptions.
  ///
  /// Returns `true` when startup failed and [_start] should return early,
  /// or `false` when the server reached the ready state and [_start] should
  /// continue to post-ready setup.
  Future<bool> _awaitServerReady({
    required int port,
    required Process proc,
    required Stream<String> stderrBroadcast,
    required List<String> stderrLines,
    required List<String> args,
    required String serverPath,
    required String modelId,
    required String gpuAcceleration,
    required hw.GpuInfo gpu,
  }) async {
    try {
      await _waitReady(
        port,
        proc,
        stderrBroadcast,
        heartbeatWindow: _heartbeatWindow,
        maxMissedWindows: _heartbeatMaxMissedWindows,
        overallDeadline: _startupDeadline,
      );
      return false; // success — server is ready
    } on _StartupDeadlineException catch (e) {
      // Server kept producing stderr heartbeats but `/health` never returned
      // 200 within the wall-clock deadline.  On a GPU launch this is also a
      // struggling-GPU shape, so give CPU one shot before surfacing an error.
      if (await _tryStallCpuFallback(
        gpu: gpu,
        gpuAcceleration: gpuAcceleration,
        stallKind: 'startup deadline exceeded',
      )) {
        return true;
      }
      // Captured under its own fingerprint so the disk-pressure cluster is
      // visible independently from silent stalls.
      CrashReporter.instance?.captureError(
        message: 'whisper-server startup deadline exceeded: ${e.message}',
        severity: 'error',
        type: 'stt_startup_deadline',
        fingerprint: const [sttStartupDeadline],
        extras: {
          'deadline_seconds': _startupDeadline.inSeconds,
          'stderr_tail': stderrLines,
          'args': args,
          'binary_path': serverPath,
          'model_id': modelId,
          'gpu_mode': gpuAcceleration,
          'gpu_fallback_active': _gpuFallbackActive,
          'platform': Platform.operatingSystem,
        },
      );
      stop();
      _fail('whisper-server not ready: $e');
      return true;
    } on _HeartbeatTimeoutException catch (e) {
      // Server is alive but produces no progress on stderr — typically a
      // model-load stall or a hang inside whisper.cpp (FLUTTER_WHISPASTE-9W).
      // Give CPU exactly one shot before failing.
      if (await _tryStallCpuFallback(
        gpu: gpu,
        gpuAcceleration: gpuAcceleration,
        stallKind: 'heartbeat timeout',
      )) {
        return true;
      }
      // Sentry needs the stderr tail plus args/binary to guess at the cause.
      CrashReporter.instance?.captureError(
        message: 'whisper-server heartbeat timeout: ${e.message}',
        severity: 'error',
        type: 'stt_heartbeat_timeout',
        fingerprint: const [sttHeartbeatTimeout],
        extras: {
          'stderr_tail': stderrLines,
          'args': args,
          'binary_path': serverPath,
          'model_id': modelId,
          'gpu_mode': gpuAcceleration,
          'gpu_fallback_active': _gpuFallbackActive,
          'platform': Platform.operatingSystem,
        },
      );
      stop();
      _fail('whisper-server not ready: $e');
      return true;
    } on _EarlyExitException catch (e) {
      _process = null;
      _activeModel = null;
      if (_gpuFallbackActive && gpuAcceleration != 'disabled') return true;
      // Already captured by the proc.exitCode handler above (dllMissing /
      // gpuFatal / heapCorruption / modelLoad / other) — emitting again here
      // would double-count the same incident in Sentry.
      if (state.serverState == SttServerState.error) return true;
      if (state.serverState == SttServerState.stopped && _process == null) {
        return true;
      }
      // Reaches here only when the early-exit path did NOT correspond to a
      // classified exit (e.g. process disappeared without an exitCode that
      // ran through the switch above).  This is the FLUTTER_WHISPASTE-4P
      // shape — "exited before becoming ready".
      CrashReporter.instance?.captureError(
        message: 'whisper-server early exit: ${e.message}',
        severity: 'error',
        type: 'stt_early_exit',
        fingerprint: const [sttEarlyExit],
        extras: {
          'stderr_tail': stderrLines,
          'args': args,
          'binary_path': serverPath,
          'model_id': modelId,
          'gpu_mode': gpuAcceleration,
          'gpu_fallback_active': _gpuFallbackActive,
          'platform': Platform.operatingSystem,
        },
      );
      _fail(e.message);
      return true;
    }
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

// ---------------------------------------------------------------------------
// Internal exceptions
// ---------------------------------------------------------------------------

class _EarlyExitException implements Exception {
  _EarlyExitException(this.message);
  final String message;

  @override
  String toString() => 'EarlyExitException: $message';
}

class _HeartbeatTimeoutException implements Exception {
  _HeartbeatTimeoutException(this.message);
  final String message;

  @override
  String toString() => 'HeartbeatTimeoutException: $message';
}

class _StartupDeadlineException implements Exception {
  _StartupDeadlineException(this.message);
  final String message;

  @override
  String toString() => 'StartupDeadlineException: $message';
}

// Providers are defined in stt_providers.dart and re-exported via stt_bundle.dart.

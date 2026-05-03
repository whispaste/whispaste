/// Local whisper-server subprocess manager.
///
/// Manages the full lifecycle of the whisper-server HTTP process:
/// find free port → start subprocess → health-poll → transcribe → stop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_state.dart' show SttServerState;
import 'hardware_info_service.dart' as hw;
import 'model_download_service.dart';
import 'path_service.dart';
import 'process_runner.dart';
import 'subprocess_guard.dart' as guard;

// Re-export so existing importers of stt_service.dart still see SttServerState.
export '../core/recording/recording_state.dart' show SttServerState;

// ---------------------------------------------------------------------------
// STT service state
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
  /// Used by the status bar to show elapsed warm-up time.
  final DateTime? startingSince;

  /// Whether a benchmark is currently running for this model.
  final bool isBenchmarking;

  /// Which tier is currently being benchmarked, if any.
  final QualityTier? benchmarkingTier;

  /// True when the GPU crashed and the server restarted on CPU automatically.
  /// Resets when the user changes the GPU setting or active model.
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
// STT service notifier
// ---------------------------------------------------------------------------

/// Manages the local whisper-server subprocess with keep-alive pooling.
///
/// Exposes [SttStatus] as state and provides [ensureRunning] / [transcribe] /
/// [stop] for the recording orchestrator.
///
/// **Keep-alive strategy**: The server process stays alive between
/// transcriptions, eliminating the ~10 s cold-start for every recording after
/// the first. An idle timer kills the server after [_idleTimeout] to free GPU
/// memory. The server is also restarted transparently when the model changes.
class SttServiceNotifier extends Notifier<SttStatus> {
  static final _log = AppLogger('SttService');
  static const _cudaOomErrorCode = 'stt_cuda_oom';
  static const _maxStderrLines = 50;

  Process? _process;
  String? _activeModel;
  Timer? _idleTimer;

  /// Last successful transcription (~200 chars). Passed as `prompt` to
  /// subsequent inference calls for faster decoder convergence and improved
  /// language consistency.
  String? _lastPrompt;

  /// When [_lastPrompt] was set. Cleared after 10 min regardless of
  /// server keep-alive to avoid stale context poisoning later sessions.
  DateTime? _lastPromptTime;
  static const _promptExpiry = Duration(minutes: 10);

  /// Whether the idle timer has already been extended once after a
  /// transcription (+5 min burst, hard max 2× base timeout).
  bool _idleExtended = false;

  /// Whether a recording is currently in progress. Used to gate idle timer
  /// resets so that pre-warm health checks don't inadvertently reset the
  /// timer when no user activity is happening.
  bool _isRecordingActive = false;

  /// Guards against concurrent [ensureRunning] calls (e.g. rapid
  /// toggle-recording). If a startup is already in flight, subsequent callers
  /// await the same future instead of spawning a second process.
  Completer<void>? _startCompleter;

  /// When true, the GPU crashed with a fatal error and [_start] should use CPU.
  /// Reset when the user explicitly changes the GPU setting or active model.
  bool _gpuFallbackActive = false;

  /// Model IDs that exited with code 3 (failed to load) on the last attempt.
  /// Used to fail fast on subsequent [ensureRunning] calls instead of looping.
  /// Cleared when the user changes model/GPU settings or re-downloads a model.
  final Set<String> _modelLoadFailedIds = {};

  /// Debounce timer for model-change pre-warm.
  Timer? _modelChangeDebounce;

  /// Reusable HTTP client with connection pooling (mirrors Go's
  /// `sttInferenceClient`). Localhost — no compression needed.
  late final http.Client _httpClient;

  /// Injectable process runner for the whisper-server subprocess.
  late final ProcessRunner _processRunner;

  @override
  SttStatus build() {
    _httpClient = ref.read(sttHttpClientProvider);
    _processRunner = ref.read(processRunnerProvider);

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

    // Watch settings to detect model changes and trigger debounced pre-warm.
    ref.listen(settingsProvider, (prev, next) {
      final prevSettings = prev?.value;
      final nextSettings = next.value;
      if (prevSettings == null || nextSettings == null) return;

      // Reset CPU fallback and model-load-failure guard when the user explicitly
      // changes GPU mode or model so that the new configuration is retried.
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

    // Clear load-failure flag when a model is (re-)downloaded so the server
    // is allowed to start again with the fresh file.
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

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Ensures the server is running with the configured model.
  ///
  /// **Warm path**: If the server is already running with the same model and
  /// passes a fast health check, returns immediately (< 500 ms).
  ///
  /// **Model-change path**: If the user switched models, the running server is
  /// stopped and a fresh one is started.
  ///
  /// **Cold path**: Starts a new server subprocess and waits for it to become
  /// ready (may take 10+ s while the model loads into GPU memory).
  ///
  /// Thread-safe: concurrent callers share a single in-flight startup.
  Future<void> ensureRunning() async {
    // If a startup is already in-flight, piggy-back on it.
    if (_startCompleter != null) {
      return _startCompleter!.future;
    }

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final modelId = settings.effectiveModelId;

    // ── Model-change detection ───────────────────────────────────────────
    if (_activeModel != null && _activeModel != modelId) {
      _log.info('STT model changed ($_activeModel → $modelId), restarting');
      stop();
    }

    // ── Warm path — server already running with same model ───────────────
    if (state.isReady && state.modelId == modelId && _process != null) {
      if (await _quickHealthCheck(state.port)) {
        _resetIdleTimer();
        _log.debug('STT server already running (warm) on port ${state.port}');
        return;
      }
      // Health check failed — server crashed silently. Clean up and restart.
      _log.warning('STT server health check failed, restarting');
      _cleanupProcess();
    }

    // Re-check: another caller may have started while we awaited health check.
    if (_startCompleter != null) {
      return _startCompleter!.future;
    }

    // ── Cold path — start a new server ───────────────────────────────────
    // Fail fast if this model previously exited with code 3 (failed to load)
    // to prevent an infinite retry loop after a corrupted/incompatible model.
    // Cleared when the user re-downloads the model or changes configuration.
    if (_modelLoadFailedIds.contains(modelId)) {
      _fail(
        'STT model file is corrupted. '
        'Please re-download the model in Settings.',
      );
      return;
    }

    // Gate concurrent callers through a single Completer.
    if (state.serverState != SttServerState.stopped) {
      stop();
    }

    _startCompleter = Completer<void>();
    try {
      await _start(
        modelId: modelId,
        gpuAcceleration:
            _gpuFallbackActive ? 'disabled' : settings.gpuAcceleration,
      );
      _startCompleter?.complete();
    } on Exception catch (e) {
      _startCompleter?.completeError(e);
      rethrow;
    } finally {
      _startCompleter = null;
    }
  }

  /// Pre-warms the STT server in the background.
  ///
  /// Call this at app startup so the first recording doesn't pay the cold-start
  /// penalty. Failures are logged but never thrown — pre-warming is best-effort.
  Future<void> prewarm() async {
    try {
      await ensureRunning();
      _log.info('STT server pre-warmed on port ${state.port}');
    } on Exception catch (e) {
      _log.debug('Pre-warm skipped: $e');
    }
  }

  /// Runs a fresh benchmark for the currently active model.
  ///
  /// Stops the current server, starts it again, and runs the benchmark.
  /// Used by the settings UI to let users re-measure performance.
  Future<void> runBenchmark() async {
    final currentModelId = state.modelId;
    if (currentModelId.isEmpty) {
      _log.debug('Cannot run benchmark: no model is currently active');
      return;
    }

    _log.info('Starting re-benchmark for model: $currentModelId');

    // Stop current server if running
    stop();

    // Start and benchmark
    try {
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      await _start(
        modelId: currentModelId,
        gpuAcceleration:
            _gpuFallbackActive ? 'disabled' : settings.gpuAcceleration,
      );
      _log.info('Re-benchmark completed for $currentModelId');
    } on Exception catch (e) {
      _log.debug('Re-benchmark failed: $e');
    }
  }

  /// Notifies the STT service that a recording has started.
  ///
  /// While recording is active, the idle timer is paused (not reset on
  /// health checks) so the server won't shut down mid-session.
  void notifyRecordingStarted() {
    _isRecordingActive = true;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Notifies the STT service that a transcription just completed.
  ///
  /// Extends the idle timer by +5 min (one-step burst) up to 2× base timeout
  /// so consecutive short recordings don't trigger a cold restart.
  void notifyTranscriptionCompleted() {
    _isRecordingActive = false;
    _idleExtended = false; // allow one burst extension
    _resetIdleTimer(extendAfterTranscription: true);
  }

  /// Notifies the STT service that a recording was cancelled/failed without
  /// transcription (e.g. dead mic, user cancel).
  void notifyRecordingStopped() {
    _isRecordingActive = false;
    _resetIdleTimer();
  }

  /// Transcribes a WAV file and returns the text.
  ///
  /// Throws [StateError] if the server is not ready.
  /// Throws [HttpException] on non-200 responses.
  Future<String> transcribe(String wavFilePath, {String? language}) async {
    final file = File(wavFilePath);
    if (!file.existsSync()) {
      throw Exception('WAV file not found: $wavFilePath');
    }
    return transcribeBytes(await file.readAsBytes(), language: language);
  }

  /// Transcribes pre-loaded WAV bytes — avoids file-system races when the
  /// caller already holds the data in memory.
  ///
  /// Uses prompt conditioning from the last transcription to improve decoder
  /// convergence speed and language consistency.
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

    // Build multipart request (mirrors Go's Transcribe).
    final uri = Uri.parse('${state.endpoint}/inference');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes('file', wavBytes, filename: 'audio.wav'),
      )
      ..fields['response_format'] = 'json'
      ..fields['temperature'] = '0.0';

    if (lang.isNotEmpty && lang != 'auto') {
      request.fields['language'] = lang;
    }

    // Prompt conditioning: pass last transcript for faster decoder
    // convergence and consistent language detection.
    // Expire stale prompts after 10 min to prevent context poisoning.
    // Custom vocabulary is prepended to give Whisper domain-specific hints.
    final settings = ref.read(settingsProvider).value;
    final vocab = settings?.customVocabulary.trim() ?? '';
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
    // Prepend custom vocabulary so Whisper biases toward those terms.
    if (vocab.isNotEmpty || (promptValue != null && promptValue.isNotEmpty)) {
      final parts = [
        if (vocab.isNotEmpty) vocab,
        if (promptValue != null && promptValue.isNotEmpty) promptValue,
      ];
      request.fields['prompt'] = parts.join(' ');
    }

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
      _log.error(
        'STT server connection lost during inference (SocketException): $e',
      );
      throw Exception(
        'STT server connection lost during inference (server may have crashed)',
      );
    } on http.ClientException catch (e) {
      _log.error(
        'STT server connection lost during inference (ClientException): $e',
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
      throw HttpException(
        'Inference failed (HTTP ${streamedResponse.statusCode}): '
        '$responseBody',
      );
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    var text = (json['text'] as String? ?? '').trim();

    // Lightweight post-transcription repetition filter: collapse 3+
    // consecutive identical sentences which are a hallucination pattern.
    text = _collapseRepetitions(text);

    // Update prompt for next transcription (last ~200 chars).
    // If repetition was detected (text was shortened), clear the prompt
    // to prevent contaminating the next transcription.
    if (text.isNotEmpty) {
      _lastPrompt = text.length > 200
          ? text.substring(text.length - 200)
          : text;
      _lastPromptTime = DateTime.now();
    }

    return text;
  }

  /// Stops the whisper-server subprocess and frees GPU memory.
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

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  /// Centralized state transition with structured lifecycle logging.
  ///
  /// Every [SttServerState] change goes through this method so that
  /// transitions are traceable in logs and Sentry breadcrumbs.
  /// Automatically sets [SttStatus.startingSince] when entering the
  /// starting state and clears it on any other transition.
  void _transition(SttStatus next) {
    final prev = state.serverState;

    // Attach startingSince timestamp when entering starting state.
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

  /// Kills the process without touching state or timers.
  void _cleanupProcess() {
    final proc = _process;
    _process = null;
    _activeModel = null;

    if (proc != null) {
      try {
        proc.kill();
        // Give the process 2s to exit, then move on.
        proc.exitCode
            .timeout(const Duration(seconds: 2), onTimeout: () => -1)
            .then((_) {});
      } on ProcessException catch (e) {
        // Process already exited — this is fine.
        _log.debug('Kill whisper-server: $e');
      }
      guard.deletePid('whisper-server');
    }
  }

  /// Fast health check with a tight timeout (< 500 ms). Used on the warm path
  /// to verify the server is still alive without blocking the user.
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

  /// Resets the idle timer. Called after every [ensureRunning] and
  /// [transcribe] so the server stays alive while in active use.
  ///
  /// When [extendAfterTranscription] is true, adds a one-time +5 min burst
  /// (up to 2× base timeout) to keep the server warm for follow-up dictations.
  void _resetIdleTimer({bool extendAfterTranscription = false}) {
    // Don't reset the idle timer during an active recording — the timer is
    // paused by [notifyRecordingStarted] and will be restarted by
    // [notifyTranscriptionCompleted] or [notifyRecordingStopped].
    if (_isRecordingActive) return;

    _idleTimer?.cancel();
    _idleTimer = null;

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final baseMinutes = settings.sttIdleTimeoutMinutes;

    // 0 = keep-alive mode — never shut down automatically.
    if (baseMinutes <= 0) return;

    var timeoutMinutes = baseMinutes;

    // Burst extension: +5 min after transcription (once), hard max 2× base.
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

  /// Debounced pre-warm triggered when the user changes the STT model in
  /// settings. Waits 500 ms (in case the user is still browsing models),
  /// then starts the new model in the background.
  void _debouncedPrewarmOnModelChange(String newModelId) {
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = Timer(const Duration(milliseconds: 500), () async {
      _log.info('Model changed to $newModelId, starting debounced pre-warm');

      // Only pre-warm when model file is already downloaded.
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

      // Stop current server (different model) and start new one.
      if (_process != null) {
        stop();
      }
      try {
        await ensureRunning();
        _log.info('Pre-warm after model change complete');
      } on Exception catch (e) {
        _log.debug('Pre-warm after model change skipped: $e');
      }
    });
  }

  /// Sends a tiny silent WAV to force the GPU to allocate compute buffers
  /// (KV cache, attention scratch space). Without this, the first real
  /// inference pays a ~3-5× RTF penalty for lazy allocation.
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
      // Non-fatal — first real inference will be slightly slower.
    }
  }

  /// Runs a quick benchmark using the silent WAV to measure RTF.
  /// Stores results in settings for tier recommendations.
  Future<void> _runBenchmark(int port, String modelId) async {
    final tier = tierForModel(modelId);

    // Mark benchmarking as started
    state = state.copyWith(isBenchmarking: true, benchmarkingTier: tier);

    final sw = Stopwatch()..start();
    try {
      // Use a slightly longer silent sample for more accurate measurement
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

      final processingTimeMs = sw.elapsedMilliseconds;
      // Benchmark audio is 3 seconds (see _generateBenchmarkWav)
      const audioDurationMs = 3000;
      final rtf = processingTimeMs / audioDurationMs;

      _log.info(
        'Benchmark completed for $modelId: ${processingTimeMs}ms '
        '(RTF=$rtf)',
      );

      // Store benchmark result in settings via callback/provider update
      // This will be implemented in the settings provider
      _storeBenchmarkResult(modelId, rtf);
    } on Exception catch (e) {
      sw.stop();
      _log.debug('Benchmark failed: $e');
      // Non-fatal - benchmark is best-effort
    } finally {
      // Mark benchmarking as done
      state = state.copyWith(
        isBenchmarking: false,
        clearBenchmarkingTier: true,
      );
    }
  }

  /// Stores benchmark result. Called by _runBenchmark.
  Future<void> _storeBenchmarkResult(String modelId, double rtf) async {
    try {
      final tier = tierForModel(modelId);
      if (tier == null) return;

      final currentSettings = ref.read(settingsProvider).value;
      final currentRtfMap = Map<QualityTier, double>.from(
        currentSettings?.tierBenchmarkRtf ?? {},
      );
      currentRtfMap[tier] = rtf;

      // Generate hardware ID from GPU info
      final gpuInfo = await ref.read(hw.gpuInfoProvider.future);
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
      // Non-fatal - benchmark is best-effort
    }
  }

  /// Generates a 3-second silent WAV for benchmarking (48 k samples × 2 bytes + header).
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

    // RIFF header
    buffer[0] = 0x52; // R
    buffer[1] = 0x49; // I
    buffer[2] = 0x46; // F
    buffer[3] = 0x46; // F
    data.setUint32(4, headerSize + dataSize - 8, Endian.little);
    buffer[8] = 0x57; // W
    buffer[9] = 0x41; // A
    buffer[10] = 0x56; // V
    buffer[11] = 0x45; // E

    // fmt chunk
    buffer[12] = 0x66; // f
    buffer[13] = 0x6D; // m
    buffer[14] = 0x74; // t
    buffer[15] = 0x20; // ' '
    data.setUint32(16, 16, Endian.little); // chunk size
    data.setUint16(20, 1, Endian.little); // PCM format
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, numChannels * bytesPerSample, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    buffer[36] = 0x64; // d
    buffer[37] = 0x61; // a
    buffer[38] = 0x74; // t
    buffer[39] = 0x61; // a
    data.setUint32(40, dataSize, Endian.little);
    // Remaining bytes are already 0 (silence).

    return buffer;
  }

  /// Generates a minimal silent WAV (0.25 s, 16 kHz, mono, 16-bit PCM).
  ///
  /// 4 000 samples × 2 bytes = 8 000 data bytes + 44-byte header = 8 044 bytes.
  static Uint8List _generateSilentWav() {
    const sampleRate = 16000;
    const durationSamples = sampleRate ~/ 4; // 0.25 s
    const bitsPerSample = 16;
    const numChannels = 1;
    const bytesPerSample = bitsPerSample ~/ 8;
    const dataSize = durationSamples * numChannels * bytesPerSample;
    const headerSize = 44;

    final buffer = Uint8List(headerSize + dataSize);
    final data = ByteData.sublistView(buffer);

    // RIFF header
    buffer[0] = 0x52; // R
    buffer[1] = 0x49; // I
    buffer[2] = 0x46; // F
    buffer[3] = 0x46; // F
    data.setUint32(4, headerSize + dataSize - 8, Endian.little);
    buffer[8] = 0x57; // W
    buffer[9] = 0x41; // A
    buffer[10] = 0x56; // V
    buffer[11] = 0x45; // E

    // fmt chunk
    buffer[12] = 0x66; // f
    buffer[13] = 0x6D; // m
    buffer[14] = 0x74; // t
    buffer[15] = 0x20; // ' '
    data.setUint32(16, 16, Endian.little); // chunk size
    data.setUint16(20, 1, Endian.little); // PCM format
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, numChannels * bytesPerSample, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    buffer[36] = 0x64; // d
    buffer[37] = 0x61; // a
    buffer[38] = 0x74; // t
    buffer[39] = 0x61; // a
    data.setUint32(40, dataSize, Endian.little);
    // Remaining bytes are already 0 (silence).

    return buffer;
  }

  Future<void> _start({
    required String modelId,
    required String gpuAcceleration,
  }) async {
    _transition(const SttStatus(serverState: SttServerState.starting));

    // --- Resolve paths -------------------------------------------------------
    final serverPath = whisperServerPath();
    final modelPath = sttModelPath(modelId);

    if (modelPath == null) {
      _fail('Unknown STT model: $modelId');
      return;
    }

    // --- Validate files exist ------------------------------------------------
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
    // Guard against partial or corrupted model downloads: even a 0-byte file
    // passes the exists() check but causes whisper-server to exit with code 3.
    // The smallest valid quantised model (whisper-tiny q5_1) is ~37 MB.
    const minModelBytes = 10 * 1024 * 1024; // 10 MB safety floor
    final modelFileSize = await modelFile.length();
    if (modelFileSize < minModelBytes) {
      _log.error(
        'STT model file appears corrupted: $modelPath '
        '($modelFileSize bytes, expected >$minModelBytes).',
      );
      unawaited(
        modelFile.delete().catchError((Object e) {
          _log.warning('Failed to delete corrupt model file: $e');
          return modelFile;
        }),
      );
      _fail(
        'STT model file is incomplete or corrupted '
        '(${(modelFileSize / 1024).round()} KB). '
        'Please re-download the model in Settings.',
      );
      return;
    }

    // --- Find a free port ----------------------------------------------------
    final int port;
    try {
      final socket = await ServerSocket.bind('127.0.0.1', 0);
      port = socket.port;
      await socket.close();
    } on SocketException catch (e) {
      _fail('Cannot find free port: $e');
      return;
    }

    // --- Detect GPU for optimal configuration --------------------------------
    final gpu = await hw.detectGpu();
    _log.info(
      'GPU: ${gpu.name} (${gpu.vendor.name}, backend=${gpu.optimalBackend})',
    );

    // --- Proactive binary compatibility check --------------------------------
    // Verify the server binary matches the current GPU before attempting to
    // start it. This catches hardware changes (e.g., new GPU, driver update)
    // that would otherwise cause a DLL_NOT_FOUND crash at startup.
    if (!hw.isServerBinaryCompatible(sttDir(), gpu)) {
      _log.error(
        'Proactive check: server binary incompatible with current GPU. '
        'Deleting for re-download.',
      );
      await hw.deleteServerBinary(sttDir());
      _fail(
        'Incompatible whisper-server for your GPU (${gpu.name}). '
        'Please re-download the speech model in Settings.',
      );
      return;
    }

    // --- Build args (mirrors Go's sttServerArgs) -----------------------------
    final threads = _threadCount(gpuAcceleration);
    final args = _serverArgs(
      modelPath: modelPath,
      port: port,
      threads: threads,
      gpuMode: gpuAcceleration,
    );

    _log.info(
      'Starting whisper-server: model=$modelId threads=$threads '
      'gpu=$gpuAcceleration port=$port',
    );
    _log.info('Command: $serverPath ${args.join(' ')}');

    // --- Start process -------------------------------------------------------
    // On macOS, ensure quarantine attribute is removed (blocks execution).
    if (Platform.isMacOS) {
      await Process.run('xattr', ['-d', 'com.apple.quarantine', serverPath]);
    }

    final Process proc;
    try {
      proc = await _processRunner.start(serverPath, args);
    } on ProcessException catch (e) {
      _fail('Failed to start whisper-server: $e');
      return;
    }

    _process = proc;
    guard.writePid('whisper-server', proc.pid);

    final stderrLines = <String>[];
    var sawCudaOom = false;

    void rememberStderr(String line) {
      final normalized = line.trim();
      if (normalized.isEmpty) return;

      stderrLines.add(normalized);
      if (stderrLines.length > _maxStderrLines) {
        stderrLines.removeAt(0);
      }

      final lower = normalized.toLowerCase();
      if (_looksLikeCudaOom(lower)) {
        sawCudaOom = true;
      }

      if (lower.contains('error') || lower.contains('failed')) {
        _log.warning('whisper-server: $normalized');
      } else {
        _log.debug('whisper-server: $normalized');
      }
    }

    // Log subprocess output for diagnostics.
    // whisper-server writes ALL diagnostic info to stderr (model params,
    // device selection, system_info). These are informational, not errors.
    proc.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) => _log.debug('whisper-server: $line'));
    proc.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(rememberStderr);

    // Monitor for early exit (mirrors Go's waitCh).
    unawaited(
      proc.exitCode.then((code) {
        if (_process == proc) {
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

          // Windows STATUS_DLL_NOT_FOUND (0xC0000135) indicates a binary
          // variant mismatch — e.g. CUDA build on a system without NVIDIA.
          final isDllNotFound = Platform.isWindows && code == -1073741515;

          // Windows 0xC0000409 (STATUS_STACK_BUFFER_OVERRUN): fatal CUDA abort.
          // Occurs when a GPU feature unsupported by the hardware is invoked at
          // runtime — most commonly flash-attn on pre-Turing GPUs (sm_30/50/61).
          // Also triggered by VRAM exhaustion on cards with very limited memory.
          final isCudaFatalAbort = Platform.isWindows && code == -1073740791;

          // Exit code 3 from whisper-server = model file could not be loaded.
          // Possible causes: corrupted/partial download that passed exists()
          // check, or a file-format version mismatch with the bundled binary.
          final isModelLoadError = code == 3;

          if (isDllNotFound) {
            _log.error(
              'whisper-server crashed: missing DLL (exit code $code). '
              'Wrong binary variant for this GPU. '
              'Auto-deleting incompatible binary for re-download.',
            );
            // Delete the wrong binary so the next download fetches the
            // correct variant based on GPU detection.
            unawaited(hw.deleteServerBinary(sttDir()));
          } else if (isCudaFatalAbort) {
            if (!_gpuFallbackActive) {
              // First GPU fatal crash: silently activate CPU fallback.
              // The next ensureRunning() call will start the server on CPU.
              _gpuFallbackActive = true;
              _log.warning(
                'GPU fatal abort (code $code / 0xC0000409) on "${gpu.name}" '
                '— CPU fallback activated; next recording uses CPU backend.',
              );
              _process = null;
              _activeModel = null;
              // Transition to stopped so ensureRunning() restarts cleanly
              // on the next recording without showing an error.
              _transition(const SttStatus(serverState: SttServerState.stopped));
              return;
            }
            // CPU fallback was already active — this is a real failure.
            _log.error(
              'whisper-server GPU fatal abort (code $code / 0xC0000409) on '
              '"${gpu.name}" and CPU fallback also failed.',
            );
          } else if (isModelLoadError) {
            // exit code 3 = whisper_init_from_file failed; this is most
            // commonly caused by a partial/corrupted download.
            // Only auto-delete when the file is demonstrably undersized (<10MB)
            // to avoid removing a valid multi-GB model due to transient I/O
            // or permission errors.
            //
            // Mark the model as load-failed so ensureRunning() fails fast on
            // subsequent calls, preventing an infinite retry loop.
            _modelLoadFailedIds.add(modelId);
            final badPath = sttModelPath(modelId);
            if (badPath != null) {
              unawaited(() async {
                try {
                  final badFile = File(badPath);
                  if (await badFile.exists()) {
                    final sz = await badFile.length();
                    if (sz < 10 * 1024 * 1024) {
                      await badFile.delete();
                      _log.error(
                        'whisper-server failed to load model (code $code). '
                        'Corrupt file deleted for re-download.',
                      );
                      return;
                    }
                  }
                } catch (e) {
                  _log.warning('Could not inspect/delete bad model file: $e');
                }
                _log.error(
                  'whisper-server failed to load model (code $code). '
                  'Model file may be corrupted — please re-download.',
                );
              }());
            } else {
              _log.error(
                'whisper-server failed to load model (code $code). '
                'Model file may be corrupted — please re-download.',
              );
            }
          } else {
            _log.error('whisper-server exited unexpectedly (code $code)');
          }
          _process = null;
          _activeModel = null;
          _transition(
            SttStatus(
              serverState: SttServerState.error,
              errorMessage: isDllNotFound
                  ? 'Incompatible server binary for your GPU. '
                        'Please re-download the speech model in Settings.'
                  : isCudaFatalAbort
                  // CPU fallback was active but also crashed.
                  ? 'Speech engine failed on both GPU and CPU (code $code). '
                        'Please restart the app or re-download the model.'
                  : isModelLoadError
                  ? 'STT model file is corrupted. '
                        'Please re-download the model in Settings.'
                  : 'whisper-server exited before becoming ready (code $code)',
            ),
          );
        }
      }),
    );

    _transition(
      SttStatus(
        serverState: SttServerState.starting,
        port: port,
        modelId: modelId,
      ),
    );

    // --- Health poll ---------------------------------------------------------
    final coldStart = Stopwatch()..start();
    try {
      await _waitReady(port, proc);
    } on TimeoutException catch (e) {
      stop();
      _fail('whisper-server not ready: $e');
      return;
    } on _EarlyExitException catch (e) {
      _process = null;
      _activeModel = null;
      // Suppress the stale EarlyExitException ONLY for the GPU _start() that
      // was interrupted when the fallback activated (exit handler already
      // transitioned state to stopped). CPU _start() failures must not be
      // suppressed, so we gate on gpuAcceleration != 'disabled'.
      if (_gpuFallbackActive && gpuAcceleration != 'disabled') return;
      // If the onExit handler already transitioned to error state (e.g., code 3
      // model load failure), don't overwrite it with a generic fallback message.
      if (state.serverState == SttServerState.error) return;
      _fail(e.message);
      return;
    }
    coldStart.stop();

    _activeModel = modelId;
    _resetIdleTimer();

    _log.info(
      'STT cold start completed in ${coldStart.elapsedMilliseconds}ms '
      'on port $port (model=$modelId)',
    );

    // VRAM safety check: warn if the model is too large for the GPU.
    // The server is already started with this model; the warning helps
    // diagnose crashes. On next ensureRunning, a smaller model will be used.
    if (gpu.vramMB != null) {
      final requiredVram = hw.sttModelVramMB[_activeModel] ?? 0;
      if (requiredVram > gpu.vramMB!) {
        _log.warning(
          'Model "$_activeModel" requires ~${requiredVram}MB VRAM '
          'but GPU has ${gpu.vramMB}MB — risk of crash/inference failure.',
        );
      }
    }

    // GPU warmup: send a tiny silent WAV to pre-allocate compute buffers.
    // This moves the first-inference GPU allocation penalty from the user's
    // first recording into the hidden startup phase.
    await _warmupInference(port);

    // Run benchmark silently after warmup to measure actual performance.
    // This provides real RTF data for tier recommendations.
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

  /// Progressive-backoff health polling (mirrors Go's `waitReady`).
  ///
  /// Starts at 100 ms, multiplies by 1.5 each iteration, capped at 1 s.
  /// Total deadline: 180 s (large models may need 60 s+ to load into VRAM).
  Future<void> _waitReady(int port, Process proc) async {
    final healthUrl = Uri.parse('http://127.0.0.1:$port/health');
    final client = http.Client();
    final deadline = DateTime.now().add(const Duration(seconds: 180));
    var interval = const Duration(milliseconds: 100);
    const maxInterval = Duration(seconds: 1);
    var iteration = 0;

    try {
      while (DateTime.now().isBefore(deadline)) {
        // Check if process exited early.
        if (_process != proc) {
          throw _EarlyExitException(
            'whisper-server exited before becoming ready',
          );
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

        // Progressive backoff: ×1.5 capped at 1 s.
        final nextMs = (interval.inMilliseconds * 1.5).round();
        interval = Duration(
          milliseconds: math.min(nextMs, maxInterval.inMilliseconds),
        );
      }
    } finally {
      client.close();
    }

    throw TimeoutException('whisper-server did not become ready within 180 s');
  }

  /// Builds the whisper-server CLI args (mirrors Go's `sttServerArgs`).
  List<String> _serverArgs({
    required String modelPath,
    required int port,
    required int threads,
    required String gpuMode,
  }) {
    final args = <String>[
      '--model', modelPath,
      '--host', '127.0.0.1',
      '--port', '$port',
      '--threads', '$threads',
      '--no-timestamps',
      // Reject high-entropy (uncertain) and low-probability segments to
      // suppress whisper hallucinations on short or silent audio.
      '--entropy-thold', '2.6',
      '--logprob-thold', '-1.0',
    ];

    // Benchmark: baseline_t0_explicit (no VAD) is most reliable for short
    // dictations. VAD is disabled by default in whisper-server, so no flag
    // needed. The --no-vad flag is not supported by all server builds.

    final useGpu = _shouldUseGpu(gpuMode);
    if (!useGpu) {
      args.add('--no-gpu');
    } else {
      // Only enable flash-attn for NVIDIA CUDA — Vulkan support is
      // build-dependent and not guaranteed for our bundled binary.
      final gpu = hw.cachedGpuInfo;
      if (gpu != null && gpu.supportsFlashAttn) {
        args.add('--flash-attn');
      }
    }

    return args;
  }

  /// Calculates optimal thread count (mirrors Go's `OptimalThreads`).
  ///
  /// Uses 75% of available cores, clamped between 2 and 8 for GPU mode,
  /// or 2 and 12 for CPU-only mode (matches Go inference.STTThreadsGPU /
  /// inference.STTThreadsCPUOnly).
  int _threadCount(String gpuMode) {
    final cores = Platform.numberOfProcessors;
    if (_shouldUseGpu(gpuMode)) {
      // GPU handles the heavy encoder; CPU threads assist with decoding.
      final n = (cores * 3) ~/ 4;
      return n.clamp(2, 8);
    }
    // CPU-only: use more threads, keep one free for UI/audio.
    return (cores - 1).clamp(2, 12);
  }

  /// Whether GPU should be used for inference.
  ///
  /// `auto` is treated as GPU-enabled — the whisper-server binary
  /// handles actual backend selection (CUDA / Vulkan / CPU).
  bool _shouldUseGpu(String gpuMode) {
    return gpuMode != 'disabled';
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

    _log.error(
      'whisper-server hit CUDA OOM for model=$failedModelId '
      'gpu=${gpu.name} stderr=${stderrLines.join(' | ')} '
      'errorCode=$_cudaOomErrorCode',
    );

    _transition(
      const SttStatus(
        serverState: SttServerState.error,
        errorMessage: _cudaOomErrorCode,
      ),
    );
  }

  /// Collapses 3+ consecutive identical sentences — a common whisper
  /// hallucination pattern on short or silent audio. O(n) string processing,
  /// typically <1ms on typical transcript lengths.
  String _collapseRepetitions(String text) {
    if (text.length < 20) return text; // too short to contain repetitions

    // Split on sentence-ending punctuation while keeping the delimiter.
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

    // Detect runs of 3+ identical sentences and collapse to one.
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
      // Clear prompt to prevent hallucination propagation.
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

/// Thrown internally when the subprocess exits before health-check succeeds.
class _EarlyExitException implements Exception {
  _EarlyExitException(this.message);
  final String message;

  @override
  String toString() => 'EarlyExitException: $message';
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global STT service provider — manages the whisper-server subprocess.
final sttServiceProvider = NotifierProvider<SttServiceNotifier, SttStatus>(
  SttServiceNotifier.new,
);

/// Overrideable [ProcessRunner] for the whisper-server subprocess.
/// Tests replace this with a fake to avoid spawning real processes.
final processRunnerProvider = Provider<ProcessRunner>(
  (_) => const SystemProcessRunner(),
);

/// Overrideable [http.Client] for STT HTTP calls.
/// Tests replace this with a mock client.
final sttHttpClientProvider = Provider<http.Client>((_) => http.Client());

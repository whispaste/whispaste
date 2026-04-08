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
import 'path_service.dart';

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
  });

  final SttServerState serverState;
  final int port;
  final String modelId;
  final String? errorMessage;

  bool get isReady => serverState == SttServerState.ready;

  String get endpoint => 'http://127.0.0.1:$port';

  SttStatus copyWith({
    SttServerState? serverState,
    int? port,
    String? modelId,
    String? errorMessage,
  }) {
    return SttStatus(
      serverState: serverState ?? this.serverState,
      port: port ?? this.port,
      modelId: modelId ?? this.modelId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() =>
      'SttStatus($serverState, port=$port, model=$modelId)';
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

  Process? _process;
  String? _activeModel;
  Timer? _idleTimer;

  /// Last successful transcription (~200 chars). Passed as `prompt` to
  /// subsequent inference calls for faster decoder convergence and improved
  /// language consistency.
  String? _lastPrompt;

  /// How long the server stays alive after the last transcription before being
  /// killed to free GPU/VRAM.
  static const _idleTimeout = Duration(minutes: 5);

  /// Guards against concurrent [ensureRunning] calls (e.g. rapid
  /// toggle-recording). If a startup is already in flight, subsequent callers
  /// await the same future instead of spawning a second process.
  Completer<void>? _startCompleter;

  /// Reusable HTTP client with connection pooling (mirrors Go's
  /// `sttInferenceClient`). Localhost — no compression needed.
  final http.Client _httpClient = http.Client();

  @override
  SttStatus build() {
    ref.onDispose(() {
      _idleTimer?.cancel();
      _idleTimer = null;
      _cleanupProcess();
      _lastPrompt = null;
      _httpClient.close();
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

    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
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
        _log.debug(
          'STT server already running (warm) on port ${state.port}',
        );
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
    // Gate concurrent callers through a single Completer.
    if (state.serverState != SttServerState.stopped) {
      stop();
    }

    _startCompleter = Completer<void>();
    try {
      await _start(modelId: modelId, gpuAcceleration: settings.gpuAcceleration);
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
  Future<String> transcribeBytes(
    List<int> wavBytes, {
    String? language,
  }) async {
    if (!state.isReady) {
      throw StateError('STT server is not running');
    }

    _resetIdleTimer();

    final lang = language ?? 'auto';

    _log.info(
      'STT inference: port=${state.port} wavBytes=${wavBytes.length} lang=$lang',
    );
    final stopwatch = Stopwatch()..start();

    // Build multipart request (mirrors Go's Transcribe).
    final uri = Uri.parse('${state.endpoint}/inference');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        wavBytes,
        filename: 'audio.wav',
      ))
      ..fields['response_format'] = 'json'
      ..fields['temperature'] = '0.0';

    if (lang.isNotEmpty && lang != 'auto') {
      request.fields['language'] = lang;
    }

    // Prompt conditioning: pass last transcript for faster decoder
    // convergence and consistent language detection.
    if (_lastPrompt != null && _lastPrompt!.isNotEmpty) {
      request.fields['prompt'] = _lastPrompt!;
    }

    final streamedResponse = await _httpClient.send(request).timeout(
      const Duration(seconds: 300),
      onTimeout: () => throw TimeoutException(
        'STT inference timed out after 300s',
        const Duration(seconds: 300),
      ),
    );
    final responseBody =
        await streamedResponse.stream.bytesToString();

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
    final text = (json['text'] as String? ?? '').trim();

    // Update prompt for next transcription (last ~200 chars).
    if (text.isNotEmpty) {
      _lastPrompt =
          text.length > 200 ? text.substring(text.length - 200) : text;
    }

    return text;
  }

  /// Stops the whisper-server subprocess and frees GPU memory.
  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;

    _cleanupProcess();
    _lastPrompt = null;

    state = const SttStatus();
    _log.info('Local STT stopped');
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

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
    }
  }

  /// Fast health check with a tight timeout (< 500 ms). Used on the warm path
  /// to verify the server is still alive without blocking the user.
  Future<bool> _quickHealthCheck(int port) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$port/health');
      final resp = await http.get(uri).timeout(
        const Duration(milliseconds: 500),
      );
      return resp.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  /// Resets the idle timer. Called after every [ensureRunning] and
  /// [transcribe] so the server stays alive while in active use.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      _log.info('STT server idle for ${_idleTimeout.inMinutes} min, '
          'shutting down to free GPU memory');
      stop();
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
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          silentWav,
          filename: 'warmup.wav',
        ))
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
        28, sampleRate * numChannels * bytesPerSample, Endian.little);
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
    state = const SttStatus(serverState: SttServerState.starting);

    // --- Resolve paths -------------------------------------------------------
    final serverPath = whisperServerPath();
    final modelPath = sttModelPath(modelId);

    if (modelPath == null) {
      _fail('Unknown STT model: $modelId');
      return;
    }

    // --- Validate files exist ------------------------------------------------
    if (!File(serverPath).existsSync()) {
      _fail(
        'whisper-server executable not found at $serverPath. '
        'Download the local transcription runtime first.',
      );
      return;
    }
    if (!File(modelPath).existsSync()) {
      _fail(
        'STT model file not found at $modelPath. '
        'Download the model first.',
      );
      return;
    }

    // --- Find a free port ----------------------------------------------------
    final int port;
    try {
      final socket =
          await ServerSocket.bind('127.0.0.1', 0);
      port = socket.port;
      await socket.close();
    } on SocketException catch (e) {
      _fail('Cannot find free port: $e');
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
      'Starting whisper-server: threads=$threads gpu=$gpuAcceleration port=$port',
    );
    _log.info('Command: $serverPath ${args.join(' ')}');

    // --- Start process -------------------------------------------------------
    final Process proc;
    try {
      proc = await Process.start(
        serverPath,
        args,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      _fail('Failed to start whisper-server: $e');
      return;
    }

    _process = proc;

    // Log subprocess output for diagnostics.
    // whisper-server writes ALL diagnostic info to stderr (model params,
    // device selection, system_info). These are informational, not errors.
    proc.stdout.transform(const SystemEncoding().decoder).listen(
      (line) => _log.debug('whisper-server: $line'),
    );
    proc.stderr.transform(const SystemEncoding().decoder).listen((line) {
      // Actual errors contain "error" or "failed" — everything else is
      // diagnostic info that whisper.cpp sends to stderr by convention.
      final lower = line.toLowerCase();
      if (lower.contains('error') || lower.contains('failed')) {
        _log.warning('whisper-server: $line');
      } else {
        _log.debug('whisper-server: $line');
      }
    });

    // Monitor for early exit (mirrors Go's waitCh).
    unawaited(
      proc.exitCode.then((code) {
        if (_process == proc) {
          _log.error('whisper-server exited unexpectedly (code $code)');
          _process = null;
          _activeModel = null;
          state = SttStatus(
            serverState: SttServerState.error,
            errorMessage:
                'whisper-server exited before becoming ready (code $code)',
          );
        }
      }),
    );

    state = SttStatus(
      serverState: SttServerState.starting,
      port: port,
      modelId: modelId,
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
      // Process already gone — stop() would fail, just reset state.
      _process = null;
      _activeModel = null;
      _fail(e.message);
      return;
    }
    coldStart.stop();

    _activeModel = modelId;
    _resetIdleTimer();

    _log.info(
      'STT cold start completed in ${coldStart.elapsedMilliseconds}ms '
      'on port $port',
    );

    // GPU warmup: send a tiny silent WAV to pre-allocate compute buffers.
    // This moves the first-inference GPU allocation penalty from the user's
    // first recording into the hidden startup phase.
    await _warmupInference(port);

    state = SttStatus(
      serverState: SttServerState.ready,
      port: port,
      modelId: modelId,
    );
  }

  /// Progressive-backoff health polling (mirrors Go's `waitReady`).
  ///
  /// Starts at 100 ms, multiplies by 1.5 each iteration, capped at 1 s.
  /// Total deadline: 180 s (large models may need 60 s+ to load into VRAM).
  Future<void> _waitReady(int port, Process proc) async {
    final healthUrl = Uri.parse('http://127.0.0.1:$port/health');
    final client = http.Client();
    final deadline =
        DateTime.now().add(const Duration(seconds: 180));
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
            _log.info(
              'STT server not reachable yet (${iteration + 1}s)',
            );
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

    throw TimeoutException(
      'whisper-server did not become ready within 180 s',
    );
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
    ];

    final useGpu = _shouldUseGpu(gpuMode);
    if (!useGpu) {
      args.add('--no-gpu');
    } else {
      // whisper-server uses --flash-attn as a boolean flag (no value).
      // Unlike llama-server which accepts `--flash-attn auto`.
      args.add('--flash-attn');
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

  void _fail(String message) {
    _log.error('STT error: $message');
    state = SttStatus(
      serverState: SttServerState.error,
      errorMessage: message,
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
final sttServiceProvider =
    NotifierProvider<SttServiceNotifier, SttStatus>(
  SttServiceNotifier.new,
);

/// Local whisper-server subprocess manager.
///
/// Manages the full lifecycle of the whisper-server HTTP process:
/// find free port → start subprocess → health-poll → transcribe → stop.
/// Mirrors the Go `LocalSTT` from `stt.go` as closely as possible.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/settings_provider.dart';
import 'config_service.dart';

// ---------------------------------------------------------------------------
// STT service state
// ---------------------------------------------------------------------------

/// Lifecycle state of the whisper-server subprocess.
enum SttServerState { stopped, starting, ready, error }

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

/// Manages the local whisper-server subprocess.
///
/// Exposes [SttStatus] as state and provides [ensureRunning] / [transcribe] /
/// [stop] for the recording orchestrator.
class SttServiceNotifier extends Notifier<SttStatus> {
  Process? _process;

  /// Reusable HTTP client with connection pooling (mirrors Go's
  /// `sttInferenceClient`). Localhost — no compression needed.
  final http.Client _httpClient = http.Client();

  @override
  SttStatus build() {
    ref.onDispose(() {
      stop();
      _httpClient.close();
    });
    return const SttStatus();
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Ensures the server is running with the configured model.
  ///
  /// If already running with the same model, returns immediately (warm path).
  /// If the model changed or the server is stopped, (re)starts it.
  Future<void> ensureRunning() async {
    final config = ref.read(effectiveConfigProvider);

    final modelId = config.localModelId;

    // Warm path — already running with the same model.
    if (state.isReady && state.modelId == modelId && _process != null) {
      dev.log(
        'STT server already running (warm) on port ${state.port}',
        name: 'SttService',
      );
      return;
    }

    // Model changed — stop first.
    if (state.serverState != SttServerState.stopped) {
      dev.log('STT model changed, restarting', name: 'SttService');
      stop();
    }

    await _start(config);
  }

  /// Transcribes a WAV file and returns the text.
  ///
  /// Throws [StateError] if the server is not ready.
  /// Throws [HttpException] on non-200 responses.
  Future<String> transcribe(String wavFilePath, {String? language}) async {
    if (!state.isReady) {
      throw StateError('STT server is not running');
    }

    final file = File(wavFilePath);
    if (!file.existsSync()) {
      throw ArgumentError('WAV file not found: $wavFilePath');
    }

    final wavBytes = await file.readAsBytes();
    final lang = language ?? 'auto';

    dev.log(
      'STT inference: port=${state.port} wavBytes=${wavBytes.length} lang=$lang',
      name: 'SttService',
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

    final streamedResponse = await _httpClient.send(request);
    final responseBody =
        await streamedResponse.stream.bytesToString();

    stopwatch.stop();
    dev.log(
      'STT inference response: status=${streamedResponse.statusCode} '
      'duration=${stopwatch.elapsedMilliseconds}ms bodyLen=${responseBody.length}',
      name: 'SttService',
    );

    if (streamedResponse.statusCode != 200) {
      throw HttpException(
        'Inference failed (HTTP ${streamedResponse.statusCode}): '
        '$responseBody',
      );
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    final text = (json['text'] as String? ?? '').trim();
    return text;
  }

  /// Stops the whisper-server subprocess.
  void stop() {
    final proc = _process;
    _process = null;

    if (proc != null) {
      try {
        proc.kill();
      } on ProcessException catch (e) {
        // Process already exited — this is fine.
        dev.log(
          'Kill whisper-server: $e',
          name: 'SttService',
        );
      }
    }

    state = const SttStatus();
    dev.log('Local STT stopped', name: 'SttService');
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  Future<void> _start(WhisPasteConfig config) async {
    state = const SttStatus(serverState: SttServerState.starting);

    // --- Resolve paths -------------------------------------------------------
    final serverPath = whisperServerPath();
    final modelPath = sttModelPath(config.localModelId);

    if (modelPath == null) {
      _fail('Unknown STT model: ${config.localModelId}');
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
    final gpuMode = config.gpuAcceleration;
    final threads = _threadCount(gpuMode);
    final args = _serverArgs(
      modelPath: modelPath,
      port: port,
      threads: threads,
      gpuMode: gpuMode,
    );

    dev.log(
      'Starting whisper-server: threads=$threads gpu=$gpuMode port=$port',
      name: 'SttService',
    );
    dev.log(
      'Command: $serverPath ${args.join(' ')}',
      name: 'SttService',
    );

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

    // Monitor for early exit (mirrors Go's waitCh).
    unawaited(
      proc.exitCode.then((code) {
        if (_process == proc) {
          dev.log(
            'whisper-server exited unexpectedly (code $code)',
            name: 'SttService',
          );
          _process = null;
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
      modelId: config.localModelId,
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
      _fail(e.message);
      return;
    }
    coldStart.stop();

    dev.log(
      'STT cold start completed in ${coldStart.elapsedMilliseconds}ms '
      'on port $port',
      name: 'SttService',
    );

    state = SttStatus(
      serverState: SttServerState.ready,
      port: port,
      modelId: config.localModelId,
    );
  }

  /// Progressive-backoff health polling (mirrors Go's `waitReady`).
  ///
  /// Starts at 100 ms, multiplies by 1.5 each iteration, capped at 1 s.
  /// Total deadline: 120 s.
  Future<void> _waitReady(int port, Process proc) async {
    final healthUrl = Uri.parse('http://127.0.0.1:$port/health');
    final client = http.Client();
    final deadline =
        DateTime.now().add(const Duration(seconds: 120));
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
            dev.log(
              'STT server loading model... '
              '(${iteration + 1}s, status=${resp.statusCode})',
              name: 'SttService',
            );
          }
        } on Exception {
          if (iteration % 10 == 9) {
            dev.log(
              'STT server not reachable yet (${iteration + 1}s)',
              name: 'SttService',
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
      'whisper-server did not become ready within 120 s',
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
      args.add('--flash-attn');
    }

    return args;
  }

  /// Calculates optimal thread count (mirrors Go's `sttThreadCount`).
  ///
  /// GPU mode: half the cores (GPU handles the heavy encoder work).
  /// CPU-only: all cores minus one (keep one for the UI thread).
  int _threadCount(String gpuMode) {
    final cores = Platform.numberOfProcessors;
    if (_shouldUseGpu(gpuMode)) {
      return math.max(1, cores ~/ 2);
    }
    return math.max(1, cores - 1);
  }

  /// Whether GPU should be used for inference.
  ///
  /// `auto` queries the Go FFI bridge for a recommendation.
  /// For now, we treat `auto` as GPU-enabled since the Go bridge
  /// handles the actual backend selection when starting the server.
  bool _shouldUseGpu(String gpuMode) {
    return gpuMode != 'disabled';
  }

  void _fail(String message) {
    dev.log('STT error: $message', name: 'SttService');
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

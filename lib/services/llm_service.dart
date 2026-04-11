/// Local llama-server subprocess manager.
///
/// Manages the full lifecycle of the llama-server HTTP process:
/// find free port → start subprocess → health-poll → chat completion → stop.
///
/// Mirrors the STT service architecture ([SttServiceNotifier]) but uses
/// the OpenAI-compatible `/v1/chat/completions` endpoint for text generation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'hardware_info_service.dart' as hw;
import 'llm_prompts.dart' as prompts;
import 'path_service.dart';
import 'subprocess_guard.dart' as guard;

// ---------------------------------------------------------------------------
// LLM server state
// ---------------------------------------------------------------------------

/// Server lifecycle states for the LLM subprocess.
enum LlmServerState { stopped, starting, ready, error }

/// Immutable snapshot of the LLM service.
class LlmStatus {
  const LlmStatus({
    this.serverState = LlmServerState.stopped,
    this.port = 0,
    this.modelId = '',
    this.errorMessage,
    this.startingSince,
  });

  final LlmServerState serverState;
  final int port;
  final String modelId;
  final String? errorMessage;

  /// When the server entered the [LlmServerState.starting] state.
  final DateTime? startingSince;

  bool get isReady => serverState == LlmServerState.ready;

  String get endpoint => 'http://127.0.0.1:$port';

  @override
  String toString() =>
      'LlmStatus($serverState, port=$port, model=$modelId)';
}

// ---------------------------------------------------------------------------
// LLM service notifier
// ---------------------------------------------------------------------------

/// Manages the local llama-server subprocess with keep-alive pooling.
///
/// Exposes [LlmStatus] as state and provides [ensureRunning] / [complete] /
/// [stop] for the post-processing service.
///
/// **Keep-alive strategy**: The server process stays alive between
/// completions. An idle timer kills it after the configured timeout to
/// free GPU memory. The default LLM idle timeout is 5 min.
class LlmServiceNotifier extends Notifier<LlmStatus> {
  static final _log = AppLogger('LlmService');

  Process? _process;
  Timer? _idleTimer;

  /// Guards against concurrent [ensureRunning] calls.
  Completer<void>? _startCompleter;

  /// Reusable HTTP client for /v1/chat/completions calls.
  final http.Client _httpClient = http.Client();

  @override
  LlmStatus build() {
    ref.onDispose(() {
      _idleTimer?.cancel();
      _idleTimer = null;
      _cleanupProcess();
      _httpClient.close();
    });

    return const LlmStatus();
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Ensures the llama-server is running with the configured LLM model.
  ///
  /// Thread-safe: concurrent callers share a single in-flight startup.
  Future<void> ensureRunning() async {
    if (_startCompleter != null) {
      return _startCompleter!.future;
    }

    const modelId = 'qwen3-1.7b';

    // ── Warm path — server already running ────────────────────────────────
    if (state.isReady && _process != null) {
      if (await _quickHealthCheck(state.port)) {
        _resetIdleTimer();
        _log.debug('LLM server already running (warm) on port ${state.port}');
        return;
      }
      _log.warning('LLM server health check failed, restarting');
      _cleanupProcess();
    }

    if (_startCompleter != null) {
      return _startCompleter!.future;
    }

    // ── Cold path — start a new server ────────────────────────────────────
    if (state.serverState != LlmServerState.stopped) {
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

  /// Sends a chat completion request to the running llama-server.
  ///
  /// Returns the generated text. Throws if the server is not ready.
  Future<String> complete(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    if (!state.isReady) {
      throw StateError('LLM server is not running');
    }

    _resetIdleTimer();

    final systemPrompt = prompts.systemPrompt(preset, targetLang: targetLang);
    final temperature = prompts.temperatureFor(preset);

    _log.info(
      'LLM completion: port=${state.port} preset=${preset.name} '
      'textLen=${text.length}',
    );
    final stopwatch = Stopwatch()..start();

    final body = jsonEncode({
      'model': state.modelId,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': text},
      ],
      'temperature': temperature,
      'max_tokens': 2048,
      'stream': false,
    });

    final uri = Uri.parse('${state.endpoint}/v1/chat/completions');
    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw TimeoutException(
            'LLM completion timed out after 120s',
            const Duration(seconds: 120),
          ),
        );

    stopwatch.stop();
    _log.info(
      'LLM completion response: status=${response.statusCode} '
      'duration=${stopwatch.elapsedMilliseconds}ms',
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'LLM completion failed (HTTP ${response.statusCode}): '
        '${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('LLM returned no choices');
    }

    final message =
        (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>;
    var result = (message['content'] as String? ?? '').trim();

    // Strip any <think>...</think> blocks that leaked through despite
    // --reasoning-budget 0 and /no_think in the system prompt.
    result = _stripThinkingTags(result);

    return result;
  }

  /// Suggests tags for the given text using the LLM.
  Future<List<String>> suggestTags(String text) async {
    if (!state.isReady) {
      throw StateError('LLM server is not running');
    }

    _resetIdleTimer();

    final body = jsonEncode({
      'model': state.modelId,
      'messages': [
        {'role': 'system', 'content': prompts.tagSuggestionPrompt},
        {'role': 'user', 'content': text},
      ],
      'temperature': prompts.suggestionTemperature,
      'max_tokens': 256,
      'stream': false,
    });

    final uri = Uri.parse('${state.endpoint}/v1/chat/completions');
    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw HttpException(
        'Tag suggestion failed (HTTP ${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) return [];

    final message =
        (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>;
    var raw = (message['content'] as String? ?? '').trim();
    raw = _stripThinkingTags(raw);

    return raw
        .split(',')
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty && t.length <= 30)
        .take(5)
        .toList();
  }

  /// Suggests a title for the given text using the LLM.
  Future<String> suggestTitle(String text) async {
    if (!state.isReady) {
      throw StateError('LLM server is not running');
    }

    _resetIdleTimer();

    final body = jsonEncode({
      'model': state.modelId,
      'messages': [
        {'role': 'system', 'content': prompts.titleSuggestionPrompt},
        {'role': 'user', 'content': text},
      ],
      'temperature': prompts.suggestionTemperature,
      'max_tokens': 64,
      'stream': false,
    });

    final uri = Uri.parse('${state.endpoint}/v1/chat/completions');
    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw HttpException(
        'Title suggestion failed (HTTP ${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) return '';

    final message =
        (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>;
    var result = (message['content'] as String? ?? '').trim();
    result = _stripThinkingTags(result);

    // Strip surrounding quotes if the model wrapped the title.
    if (result.length >= 2 &&
        ((result.startsWith('"') && result.endsWith('"')) ||
            (result.startsWith("'") && result.endsWith("'")))) {
      result = result.substring(1, result.length - 1);
    }

    return result;
  }

  /// Stops the llama-server subprocess and frees GPU memory.
  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;

    _cleanupProcess();

    _transition(const LlmStatus());
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  /// Centralized state transition with lifecycle logging.
  void _transition(LlmStatus next) {
    final prev = state.serverState;

    if (next.serverState == LlmServerState.starting &&
        next.startingSince == null) {
      next = LlmStatus(
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

    _log.info('LLM lifecycle: $prev → ${next.serverState}$extra');
  }

  /// Kills the process without touching state or timers.
  void _cleanupProcess() {
    final proc = _process;
    _process = null;

    if (proc != null) {
      try {
        proc.kill();
        proc.exitCode
            .timeout(const Duration(seconds: 2), onTimeout: () => -1)
            .then((_) {});
      } on ProcessException catch (e) {
        _log.debug('Kill llama-server: $e');
      }
      guard.deletePid('llama-server');
    }
  }

  /// Fast health check (< 500 ms).
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

  /// Resets the idle timer. Called after every operation.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;

    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    // Reuse STT idle timeout setting for LLM. Default 5 min.
    final baseMinutes = settings.sttIdleTimeoutMinutes;

    if (baseMinutes <= 0) return; // 0 = keep-alive

    _idleTimer = Timer(Duration(minutes: baseMinutes), () {
      _log.info('LLM server idle for $baseMinutes min, shutting down');
      stop();
    });
  }

  Future<void> _start({required String modelId}) async {
    _transition(const LlmStatus(serverState: LlmServerState.starting));

    // --- Resolve paths -------------------------------------------------------
    final serverPath = llamaServerPath();
    final modelPath = llmModelPath(modelId);

    if (modelPath == null) {
      _fail('Unknown LLM model: $modelId');
      return;
    }

    // --- Validate files exist ------------------------------------------------
    if (!await File(serverPath).exists()) {
      _fail(
        'llama-server executable not found at $serverPath. '
        'Download the local LLM runtime first.',
      );
      return;
    }
    if (!await File(modelPath).exists()) {
      _fail(
        'LLM model file not found at $modelPath. '
        'Download the model first.',
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
    _log.info('GPU: ${gpu.name} (${gpu.vendor.name}, '
        'backend=${gpu.optimalBackend})');

    // --- Binary compatibility check ------------------------------------------
    if (!hw.isServerBinaryCompatible(llmDir(), gpu)) {
      _log.error(
        'Proactive check: llama-server binary incompatible with current GPU.',
      );
      await hw.deleteServerBinary(llmDir());
      _fail(
        'Incompatible llama-server for your GPU (${gpu.name}). '
        'Please re-download in Settings.',
      );
      return;
    }

    // --- Build args ----------------------------------------------------------
    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    final gpuMode = settings.gpuAcceleration;
    final threads = _threadCount(gpuMode);

    final args = <String>[
      '--model', modelPath,
      '--host', '127.0.0.1',
      '--port', '$port',
      '--threads', '$threads',
      '--ctx-size', '4096',
      '--reasoning-budget', '0',
    ];

    // GPU layer offloading.
    if (gpuMode != 'disabled') {
      args.addAll(['-ngl', '99']); // Offload all layers to GPU.
    } else {
      args.addAll(['-ngl', '0']);
    }

    _log.info(
      'Starting llama-server: model=$modelId threads=$threads '
      'gpu=$gpuMode port=$port',
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
      _fail('Failed to start llama-server: $e');
      return;
    }

    _process = proc;
    guard.writePid('llama-server', proc.pid);

    // Log subprocess output.
    proc.stdout.transform(const SystemEncoding().decoder).listen(
      (line) => _log.debug('llama-server: $line'),
    );
    proc.stderr.transform(const SystemEncoding().decoder).listen((line) {
      final lower = line.toLowerCase();
      if (lower.contains('error') || lower.contains('failed')) {
        _log.warning('llama-server: $line');
      } else {
        _log.debug('llama-server: $line');
      }
    });

    // Monitor for early exit.
    unawaited(
      proc.exitCode.then((code) {
        if (_process == proc) {
          final isDllNotFound = Platform.isWindows && code == -1073741515;
          if (isDllNotFound) {
            _log.error(
              'llama-server crashed: missing DLL (exit code $code). '
              'Auto-deleting incompatible binary.',
            );
            unawaited(hw.deleteServerBinary(llmDir()));
          } else {
            _log.error('llama-server exited unexpectedly (code $code)');
          }
          _process = null;
          _transition(LlmStatus(
            serverState: LlmServerState.error,
            errorMessage: isDllNotFound
                ? 'Incompatible server binary for your GPU. '
                    'Please re-download in Settings.'
                : 'llama-server exited before becoming ready (code $code)',
          ));
        }
      }),
    );

    _transition(LlmStatus(
      serverState: LlmServerState.starting,
      port: port,
      modelId: modelId,
    ));

    // --- Health poll ---------------------------------------------------------
    final coldStart = Stopwatch()..start();
    try {
      await _waitReady(port, proc);
    } on TimeoutException catch (e) {
      stop();
      _fail('llama-server not ready: $e');
      return;
    } on _EarlyExitException catch (e) {
      _process = null;
      _fail(e.message);
      return;
    }
    coldStart.stop();

    _resetIdleTimer();

    _log.info(
      'LLM cold start completed in ${coldStart.elapsedMilliseconds}ms '
      'on port $port (model=$modelId)',
    );

    _transition(LlmStatus(
      serverState: LlmServerState.ready,
      port: port,
      modelId: modelId,
    ));
  }

  /// Progressive-backoff health polling.
  ///
  /// Starts at 100 ms, ×1.5 per iteration, capped at 1 s.
  /// Total deadline: 180 s (LLM models may need time to load into VRAM).
  Future<void> _waitReady(int port, Process proc) async {
    final healthUrl = Uri.parse('http://127.0.0.1:$port/health');
    final client = http.Client();
    final deadline = DateTime.now().add(const Duration(seconds: 180));
    var interval = const Duration(milliseconds: 100);
    const maxInterval = Duration(seconds: 1);
    var iteration = 0;

    try {
      while (DateTime.now().isBefore(deadline)) {
        if (_process != proc) {
          throw _EarlyExitException(
            'llama-server exited before becoming ready',
          );
        }

        try {
          final resp = await client
              .get(healthUrl)
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode == 200) return;

          if (iteration % 10 == 9) {
            _log.info(
              'LLM server loading model… '
              '(${iteration + 1}s, status=${resp.statusCode})',
            );
          }
        } on Exception {
          if (iteration % 10 == 9) {
            _log.info('LLM server not reachable yet (${iteration + 1}s)');
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
      client.close();
    }

    throw TimeoutException(
      'llama-server did not become ready within 180 s',
    );
  }

  /// Calculates optimal thread count.
  ///
  /// For GPU mode: 75% of cores capped at 12 (LLM needs more CPU assistance
  /// than whisper for token generation). For CPU-only: cores − 1, capped at 12.
  int _threadCount(String gpuMode) {
    final cores = Platform.numberOfProcessors;
    if (gpuMode != 'disabled') {
      final n = (cores * 3) ~/ 4;
      return n.clamp(2, 12);
    }
    return (cores - 1).clamp(2, 12);
  }

  /// Strips `<think>...</think>` blocks from model output.
  ///
  /// Despite `--reasoning-budget 0` and `/no_think` in system prompts,
  /// Qwen3 may occasionally emit thinking tags. This is a safety net.
  static String _stripThinkingTags(String text) {
    return text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  }

  void _fail(String message) {
    _log.error('LLM error: $message');
    _transition(LlmStatus(
      serverState: LlmServerState.error,
      errorMessage: message,
    ));
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

/// Global LLM service provider — manages the llama-server subprocess.
final llmServiceProvider =
    NotifierProvider<LlmServiceNotifier, LlmStatus>(
  LlmServiceNotifier.new,
);

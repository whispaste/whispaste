/// In-process Parakeet (sherpa_onnx) engine — runs entirely inside a
/// long-lived background [Isolate] so ONNX Runtime inference (which is
/// synchronous/blocking) never stalls the UI isolate.
///
/// Unlike whisper.cpp's HTTP-subprocess architecture (a separate OS process
/// speaking `POST /inference`), sherpa_onnx runs in-process via FFI — there is
/// no server binary, no port, no health-poll. The worker [Isolate] is spawned
/// once (on [ensureRunning]/[prewarm]) and kept warm for the app session; the
/// ~650 MB encoder is loaded exactly once, not per transcription.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../core/logging/app_logger.dart';
import '../audio/pcm_wav_codec.dart';
import '../stt/isolate_shutdown_helper.dart';
import '../stt/stt_benchmark.dart';
import 'parakeet_model_registry.dart';

final _log = AppLogger('ParakeetEngine');

// ---------------------------------------------------------------------------
// Isolate protocol — plain data classes only (no closures) so they survive
// the isolate message-passing boundary.
// ---------------------------------------------------------------------------

class _InitRequest {
  const _InitRequest({
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    required this.numThreads,
  });
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final int numThreads;
}

class _InitResult {
  const _InitResult({required this.ok, this.error});
  final bool ok;
  final String? error;
}

class _TranscribeRequest {
  const _TranscribeRequest({
    required this.requestId,
    required this.samples,
    required this.sampleRate,
  });
  final int requestId;
  final Float32List samples;
  final int sampleRate;
}

class _TranscribeResult {
  const _TranscribeResult({required this.requestId, this.text, this.error});
  final int requestId;
  final String? text;
  final String? error;
}

class _ShutdownRequest {
  const _ShutdownRequest();
}

/// Acknowledges an [_ShutdownRequest] once the native recognizer is actually
/// freed — see [ParakeetEngineNotifier.stop] for why this matters
/// (FLUTTER_WHISPASTE-BC-class native-teardown-vs-process-exit race).
class _ShutdownAck {
  const _ShutdownAck();
}

/// Isolate entry point. Must be a top-level/static function (Dart isolate
/// requirement) — receives the main isolate's [SendPort] and spawns its own
/// [ReceivePort], sending its own [SendPort] back as the first message so the
/// main isolate can address it.
void _parakeetIsolateMain(SendPort mainSendPort) {
  final workerPort = ReceivePort();
  mainSendPort.send(workerPort.sendPort);

  sherpa_onnx.OfflineRecognizer? recognizer;

  workerPort.listen((dynamic message) {
    switch (message) {
      case final _InitRequest req:
        try {
          sherpa_onnx.initBindings();
          final config = sherpa_onnx.OfflineRecognizerConfig(
            model: sherpa_onnx.OfflineModelConfig(
              transducer: sherpa_onnx.OfflineTransducerModelConfig(
                encoder: req.encoderPath,
                decoder: req.decoderPath,
                joiner: req.joinerPath,
              ),
              tokens: req.tokensPath,
              numThreads: req.numThreads,
              provider: 'cpu',
              // Per sherpa_onnx's own doc comment on OfflineModelConfig:
              // "For NeMo Parakeet-style transducer models, set modelType to
              // nemo_transducer, matching the repository examples."
              modelType: 'nemo_transducer',
              debug: false,
            ),
          );
          recognizer = sherpa_onnx.OfflineRecognizer(config);
          mainSendPort.send(const _InitResult(ok: true));
        } catch (e) {
          mainSendPort.send(_InitResult(ok: false, error: '$e'));
        }

      case final _TranscribeRequest req:
        final r = recognizer;
        if (r == null) {
          mainSendPort.send(
            _TranscribeResult(
              requestId: req.requestId,
              error: 'not_initialized',
            ),
          );
          break;
        }
        final stream = r.createStream();
        try {
          stream.acceptWaveform(
            samples: req.samples,
            sampleRate: req.sampleRate,
          );
          r.decode(stream);
          final result = r.getResult(stream);
          mainSendPort.send(
            _TranscribeResult(requestId: req.requestId, text: result.text),
          );
        } catch (e) {
          mainSendPort.send(
            _TranscribeResult(requestId: req.requestId, error: '$e'),
          );
        } finally {
          // Must run even on error — otherwise the native stream object
          // leaks for the isolate's lifetime (found by cross-review).
          stream.free();
        }

      case _ShutdownRequest():
        recognizer?.free();
        workerPort.close();
        // Isolate.exit's finalMessage is delivered atomically as the
        // isolate terminates — the only way to guarantee the main isolate
        // learns the native recognizer is freed before this isolate (and
        // the thread the ONNX Runtime calls ran on) disappears. A plain
        // mainSendPort.send() here would race the exit with no such
        // guarantee.
        Isolate.exit(mainSendPort, const _ShutdownAck());
    }
  });
}

// ---------------------------------------------------------------------------
// Main-isolate side — the Riverpod-visible engine state.
// ---------------------------------------------------------------------------

enum ParakeetEngineState { stopped, starting, ready, error }

class ParakeetStatus {
  const ParakeetStatus({
    this.state = ParakeetEngineState.stopped,
    this.errorMessage,
    this.benchmarkRtf,
  });
  final ParakeetEngineState state;
  final String? errorMessage;

  /// Real-time factor from the last [ParakeetEngineNotifier.runBenchmark]
  /// call (processing_time_ms / audio_duration_ms) — directly comparable to
  /// whisper's `tierBenchmarkRtf`. `null` until a benchmark has run.
  final double? benchmarkRtf;

  bool get isReady => state == ParakeetEngineState.ready;

  ParakeetStatus copyWith({
    ParakeetEngineState? state,
    String? errorMessage,
    double? benchmarkRtf,
  }) => ParakeetStatus(
    state: state ?? this.state,
    errorMessage: errorMessage,
    benchmarkRtf: benchmarkRtf ?? this.benchmarkRtf,
  );
}

/// Manages the worker isolate lifecycle and exposes a simple
/// request/response [transcribe] call to the rest of the app.
class ParakeetEngineNotifier extends Notifier<ParakeetStatus> {
  Isolate? _isolate;
  SendPort? _workerPort;
  StreamSubscription<dynamic>? _sub;
  Completer<_InitResult>? _initCompleter;
  Completer<void>? _shutdownCompleter;
  final Map<int, Completer<_TranscribeResult>> _pending = {};
  int _nextRequestId = 0;

  @override
  ParakeetStatus build() {
    ref.onDispose(_shutdown);
    return const ParakeetStatus();
  }

  /// Starts the worker isolate and loads the model, if not already running.
  /// Throws a [StateError] on failure (mirrors [SttServerStateNotifier]'s
  /// contract so [LocalSttTranscriber]-style adapters can catch uniformly).
  Future<void> ensureRunning() async {
    if (state.isReady) return;
    if (!parakeetModelFilesExistSync()) {
      state = state.copyWith(
        state: ParakeetEngineState.error,
        errorMessage: 'parakeet_model_not_found',
      );
      throw StateError('parakeet_model_not_found');
    }

    state = state.copyWith(
      state: ParakeetEngineState.starting,
      errorMessage: null,
    );

    try {
      if (_isolate == null) {
        final mainReceivePort = ReceivePort();
        final isolate = await Isolate.spawn(
          _parakeetIsolateMain,
          mainReceivePort.sendPort,
        );

        final workerPortCompleter = Completer<SendPort>();
        _sub = mainReceivePort.listen((dynamic message) {
          if (message is SendPort && !workerPortCompleter.isCompleted) {
            workerPortCompleter.complete(message);
            return;
          }
          _handleWorkerMessage(message);
        });
        try {
          _workerPort = await workerPortCompleter.future.timeout(
            const Duration(seconds: 10),
          );
          // Only commit `_isolate` once the worker has actually answered —
          // otherwise a subsequent `ensureRunning()` call would see a
          // non-null `_isolate` with a still-null `_workerPort` and crash on
          // the null-check below instead of retrying the spawn cleanly.
          _isolate = isolate;
        } catch (e) {
          _sub?.cancel();
          _sub = null;
          isolate.kill(priority: Isolate.immediate);
          rethrow;
        }
      }

      _initCompleter = Completer<_InitResult>();
      _workerPort!.send(
        _InitRequest(
          encoderPath: parakeetModelFilePath('encoder.int8.onnx'),
          decoderPath: parakeetModelFilePath('decoder.int8.onnx'),
          joinerPath: parakeetModelFilePath('joiner.int8.onnx'),
          tokensPath: parakeetModelFilePath('tokens.txt'),
          numThreads: _threadCount(),
        ),
      );
      final initResult = await _initCompleter!.future.timeout(
        const Duration(seconds: 60),
      );
      if (!initResult.ok) {
        state = state.copyWith(
          state: ParakeetEngineState.error,
          errorMessage: initResult.error ?? 'parakeet_init_failed',
        );
        throw StateError(initResult.error ?? 'parakeet_init_failed');
      }

      state = state.copyWith(
        state: ParakeetEngineState.ready,
        errorMessage: null,
      );
    } on TimeoutException {
      state = state.copyWith(
        state: ParakeetEngineState.error,
        errorMessage: 'parakeet_start_timeout',
      );
      throw StateError('parakeet_start_timeout');
    }
  }

  /// Best-effort warm-up — same contract as
  /// [SttServerStateNotifier.prewarm]: failures are swallowed by the caller.
  Future<void> prewarm() async {
    if (state.isReady || state.state == ParakeetEngineState.starting) return;
    await ensureRunning();
  }

  /// Measures the real-time factor (RTF = processing_time_ms /
  /// audio_duration_ms) against a 3 s silent WAV — the same benchmark input
  /// whisper's [SttBenchmark] uses, so the two engines' RTF numbers are
  /// directly comparable. Non-fatal: logs and leaves [ParakeetStatus.benchmarkRtf]
  /// unchanged on failure.
  Future<void> runBenchmark() async {
    try {
      await ensureRunning();
      final benchmarkWav = SttBenchmark.generateBenchmarkWav();
      final sw = Stopwatch()..start();
      await transcribeWavBytes(benchmarkWav);
      sw.stop();
      const audioDurationMs = 3000;
      final rtf = sw.elapsedMilliseconds / audioDurationMs;
      state = state.copyWith(benchmarkRtf: rtf);
      _log.info('Parakeet benchmark: RTF=${rtf.toStringAsFixed(2)}x');
    } on Exception catch (e) {
      _log.debug('Parakeet benchmark failed: $e');
    }
  }

  /// Transcribes raw WAV bytes (WhisPaste's own 16 kHz mono 16-bit PCM
  /// format — see `wav_file_writer.dart`) to text.
  Future<String> transcribeWavBytes(List<int> wavBytes) async {
    if (!state.isReady) {
      throw StateError(state.errorMessage ?? 'parakeet_not_ready');
    }
    final samples = _pcm16WavBytesToFloat32(wavBytes);
    if (samples.isEmpty) return '';

    final requestId = _nextRequestId++;
    final completer = Completer<_TranscribeResult>();
    _pending[requestId] = completer;
    _workerPort!.send(
      _TranscribeRequest(
        requestId: requestId,
        samples: samples,
        sampleRate: 16000,
      ),
    );

    final result = await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(requestId);
        throw StateError('parakeet_transcribe_timeout');
      },
    );
    if (result.error != null) {
      throw StateError(result.error!);
    }
    return result.text ?? '';
  }

  /// Stops the worker isolate. Waits (bounded) for the worker to free its
  /// native recognizer and exit gracefully before falling back to a hard
  /// kill — an unconditional `Isolate.kill(priority: immediate)` right after
  /// signalling shutdown (the previous behaviour) could preempt the worker
  /// before its native ONNX Runtime resources were ever freed, since killing
  /// a Dart isolate does not free native memory that isolate's FFI calls
  /// allocated (same class of bug as FLUTTER_WHISPASTE-BC on the whisper
  /// engine — reproduced there via ggml_metal_rsets_free's teardown assert).
  Future<void> stop() async {
    await _shutdown();
    state = const ParakeetStatus();
  }

  void _handleWorkerMessage(dynamic message) {
    switch (message) {
      case final _InitResult r:
        _initCompleter?.complete(r);
      case final _TranscribeResult r:
        _pending.remove(r.requestId)?.complete(r);
      case _ShutdownAck():
        _shutdownCompleter?.complete();
    }
  }

  Future<void> _shutdown() async {
    final isolate = _isolate;
    if (isolate == null) return;

    final completer = Completer<void>();
    _shutdownCompleter = completer;
    try {
      _workerPort?.send(const _ShutdownRequest());
    } catch (e) {
      _log.warning('Failed to signal worker shutdown: $e');
    }
    await awaitGracefulShutdown(
      completer: completer,
      timeout: const Duration(seconds: 10),
      log: _log,
      timeoutMessage:
          'Worker shutdown did not complete within 10s — force-killing '
          '(native resources may leak)',
      onTimeout: () => isolate.kill(priority: Isolate.immediate),
    );
    _sub?.cancel();
    _sub = null;
    _isolate = null;
    _workerPort = null;
  }

  /// CPU thread count — no GPU backend for Parakeet yet (see plan risk #1),
  /// so this is a simpler heuristic than whisper's GPU/CPU split.
  int _threadCount() {
    final cores = Platform.numberOfProcessors;
    return (cores - 1).clamp(2, 8);
  }
}

final parakeetEngineProvider =
    NotifierProvider<ParakeetEngineNotifier, ParakeetStatus>(
      ParakeetEngineNotifier.new,
    );

// ---------------------------------------------------------------------------
// WAV → Float32 PCM decoding
// ---------------------------------------------------------------------------

/// Decodes WhisPaste's canonical 44-byte-header, 16 kHz mono, 16-bit PCM WAV
/// bytes (see `wav_file_writer.dart`) into normalized `[-1, 1]` float samples
/// for `sherpa_onnx`'s `OfflineStream.acceptWaveform`. Delegates to the shared
/// codec so there is a single WAV-decode implementation across on-device
/// engines (whisper + Parakeet).
Float32List _pcm16WavBytesToFloat32(List<int> wavBytes) =>
    pcm16WavBytesToFloat32(wavBytes);

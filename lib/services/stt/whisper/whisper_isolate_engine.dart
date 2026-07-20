/// [WhisperEngine] wrapper that runs the real [WhisperFfiEngine] inside a
/// long-lived background [Isolate], mirroring the proven Parakeet worker
/// pattern (`parakeet_engine_notifier.dart`).
///
/// `whisper_full`/`whisper_init_from_file_with_params` are synchronous and
/// blocking — running them on the calling isolate (as the original FFI
/// seam's doc comment flagged as a deferred "Issue 03" follow-up) stalls the
/// UI thread for the whole call. Moving them to a worker isolate keeps the
/// UI responsive during model load/transcription, same rationale as Parakeet.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../hardware_info_service.dart';
import 'whisper_engine.dart';
import 'whisper_ffi_engine.dart';

final _log = AppLogger('WhisperIsolateEngine');

// ---------------------------------------------------------------------------
// Isolate protocol — plain data classes only (no closures) so they survive
// the isolate message-passing boundary.
// ---------------------------------------------------------------------------

class _EngineConfig {
  const _EngineConfig({this.libraryPath, required this.backend});
  final String? libraryPath;
  final WhisperBackend backend;
}

class _LoadRequest {
  const _LoadRequest({required this.config, required this.modelPath});
  final _EngineConfig config;
  final String modelPath;
}

class _LoadResult {
  const _LoadResult({required this.ok, this.error});
  final bool ok;
  final String? error;
}

class _TranscribeRequest {
  const _TranscribeRequest({
    required this.requestId,
    required this.wavBytes,
    this.language,
    this.prompt,
  });
  final int requestId;
  final Uint8List wavBytes;
  final String? language;
  final String? prompt;
}

class _TranscribeResult {
  const _TranscribeResult({
    required this.requestId,
    this.text,
    this.error,
    this.failureKind,
  });
  final int requestId;
  final String? text;
  final String? error;

  /// Name of the [WhisperFailureKind] the worker raised, or `null` for a
  /// plain (non-[WhisperEngineException]) error — reconstructed on the main
  /// isolate so callers keep seeing a real [WhisperEngineException].
  final String? failureKind;
}

class _UnloadRequest {
  const _UnloadRequest();
}

class _ShutdownRequest {
  const _ShutdownRequest();
}

/// Isolate entry point. Must be a top-level/static function (Dart isolate
/// requirement) — receives the main isolate's [SendPort] and spawns its own
/// [ReceivePort], sending its own [SendPort] back as the first message so the
/// main isolate can address it.
void _whisperIsolateMain(SendPort mainSendPort) {
  final workerPort = ReceivePort();
  mainSendPort.send(workerPort.sendPort);

  WhisperFfiEngine? engine;

  Future<void> handleMessage(dynamic message) async {
    switch (message) {
      case final _LoadRequest req:
        try {
          engine ??= WhisperFfiEngine(
            libraryPath: req.config.libraryPath,
            backend: req.config.backend,
          );
          await engine!.load(modelPath: req.modelPath);
          mainSendPort.send(const _LoadResult(ok: true));
        } catch (e) {
          mainSendPort.send(_LoadResult(ok: false, error: '$e'));
        }

      case final _TranscribeRequest req:
        final e = engine;
        if (e == null) {
          mainSendPort.send(
            _TranscribeResult(
              requestId: req.requestId,
              error: 'whisper_engine_not_loaded',
            ),
          );
          return;
        }
        try {
          final text = await e.transcribe(
            req.wavBytes,
            language: req.language,
            prompt: req.prompt,
          );
          mainSendPort.send(
            _TranscribeResult(requestId: req.requestId, text: text),
          );
        } on WhisperEngineException catch (ex) {
          mainSendPort.send(
            _TranscribeResult(
              requestId: req.requestId,
              error: ex.message,
              failureKind: ex.kind.name,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            _TranscribeResult(requestId: req.requestId, error: '$e'),
          );
        }

      case _UnloadRequest():
        await engine?.unload();

      case _ShutdownRequest():
        await engine?.unload();
        workerPort.close();
        Isolate.exit();
    }
  }

  // whisper_full/whisper_init are NOT thread-safe for the same context (see
  // WhisperFfiEngine's own doc comment), so messages must be handled strictly
  // one at a time. `ReceivePort.listen` does not await an async callback
  // before dispatching the next queued message — without this chain, a
  // `_ShutdownRequest` arriving while a `_TranscribeRequest` is still
  // in-flight could tear the isolate down mid-call (`Isolate.exit()`),
  // leaving the caller's completer on the main isolate unresolved forever.
  var processing = Future<void>.value();
  workerPort.listen((dynamic message) {
    processing = processing.then((_) => handleMessage(message));
  });
}

// ---------------------------------------------------------------------------
// Main-isolate side — proxies the [WhisperEngine] contract across the
// isolate boundary, spawning the worker lazily on first [load].
// ---------------------------------------------------------------------------

/// [WhisperEngine] that delegates to a [WhisperFfiEngine] running inside a
/// dedicated worker isolate. See file doc comment for why.
class WhisperIsolateEngine implements WhisperEngine {
  WhisperIsolateEngine({String? libraryPath, WhisperBackend? backend})
    : _config = _EngineConfig(
        libraryPath: libraryPath,
        backend: backend ?? WhisperBackend.cpu,
      );

  final _EngineConfig _config;

  Isolate? _isolate;
  SendPort? _workerPort;
  StreamSubscription<dynamic>? _sub;
  Completer<_LoadResult>? _loadCompleter;
  final Map<int, Completer<_TranscribeResult>> _pending = {};
  int _nextRequestId = 0;

  bool _isLoaded = false;
  String? _errorMessage;

  @override
  WhisperEngineStatus get status => WhisperEngineStatus(
    isLoaded: _isLoaded,
    backend: _config.backend,
    errorMessage: _errorMessage,
  );

  @override
  Future<void> load({required String modelPath}) async {
    if (_isLoaded) return;

    if (_isolate == null) {
      final mainReceivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        _whisperIsolateMain,
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
        // otherwise a subsequent `load()` call would see a non-null
        // `_isolate` with a still-null `_workerPort` and crash on the
        // null-check below instead of retrying the spawn cleanly.
        _isolate = isolate;
      } catch (e) {
        _sub?.cancel();
        _sub = null;
        isolate.kill(priority: Isolate.immediate);
        rethrow;
      }
    }

    _loadCompleter = Completer<_LoadResult>();
    _workerPort!.send(_LoadRequest(config: _config, modelPath: modelPath));
    final result = await _loadCompleter!.future.timeout(
      const Duration(seconds: 60),
    );
    if (!result.ok) {
      _errorMessage = result.error;
      throw StateError(result.error ?? 'whisper_isolate_load_failed');
    }
    _isLoaded = true;
    _errorMessage = null;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
  }) async {
    if (!_isLoaded || _workerPort == null) {
      throw StateError('whisper_engine_not_loaded');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<_TranscribeResult>();
    _pending[requestId] = completer;
    _workerPort!.send(
      _TranscribeRequest(
        requestId: requestId,
        wavBytes: wavBytes is Uint8List
            ? wavBytes
            : Uint8List.fromList(wavBytes),
        language: language,
        prompt: prompt,
      ),
    );

    final result = await completer.future;
    if (result.error != null) {
      final kindName = result.failureKind;
      if (kindName != null) {
        final kind = WhisperFailureKind.values.byName(kindName);
        throw WhisperEngineException(kind, result.error!);
      }
      throw StateError(result.error!);
    }
    return result.text ?? '';
  }

  @override
  Future<void> unload() async {
    if (_isolate == null) return;
    try {
      _workerPort?.send(const _UnloadRequest());
    } catch (e) {
      _log.warning('Failed to signal worker unload: $e');
    }
    _isLoaded = false;
  }

  /// Fully tears down the worker isolate. Not part of the [WhisperEngine]
  /// contract — called from provider disposal, mirroring
  /// [ParakeetEngineNotifier]'s `stop()`/`_shutdownSync()`.
  void shutdown() {
    if (_isolate == null) return;
    try {
      _workerPort?.send(const _ShutdownRequest());
    } catch (e) {
      _log.warning('Failed to signal worker shutdown: $e');
    }
    _sub?.cancel();
    _sub = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _isLoaded = false;
  }

  void _handleWorkerMessage(dynamic message) {
    switch (message) {
      case final _LoadResult r:
        _loadCompleter?.complete(r);
      case final _TranscribeResult r:
        _pending.remove(r.requestId)?.complete(r);
    }
  }
}

/// Overrideable [WhisperEngine] for the on-device whisper path.
///
/// Defaults to a [WhisperIsolateEngine] (worker isolate, see file doc
/// comment) wrapping the real [WhisperFfiEngine], configured with the compute
/// backend derived from hardware detection ([gpuInfoProvider]): NVIDIA→CUDA,
/// Apple→Metal, AMD/Intel→Vulkan, and CPU whenever no compatible GPU is
/// detected (or while detection is still in flight). Tests override it with
/// a fake.
final whisperEngineProvider = Provider<WhisperEngine>((ref) {
  final gpu = ref.watch(gpuInfoProvider).value;
  final backend = whisperBackendFromName(gpu?.optimalBackend);
  final engine = WhisperIsolateEngine(backend: backend);
  ref.onDispose(engine.shutdown);
  return engine;
});

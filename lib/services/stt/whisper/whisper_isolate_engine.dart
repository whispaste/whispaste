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

import '../../../core/config/settings_enums.dart' show GpuAcceleration;
import '../../../core/config/settings_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../hardware_info_service.dart';
import '../isolate_shutdown_helper.dart';
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
  const _LoadRequest({
    required this.config,
    required this.modelPath,
    this.vadModelPath,
  });
  final _EngineConfig config;
  final String modelPath;
  final String? vadModelPath;
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
    this.vadEnabled = false,
  });
  final int requestId;
  final Uint8List wavBytes;
  final String? language;
  final String? prompt;
  final bool vadEnabled;
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

/// Acknowledges an [_UnloadRequest] once the native context is actually
/// freed — see [WhisperIsolateEngine.unload] for why this matters.
class _UnloadAck {
  const _UnloadAck();
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
          await engine!.load(
            modelPath: req.modelPath,
            vadModelPath: req.vadModelPath,
          );
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
            vadEnabled: req.vadEnabled,
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
        mainSendPort.send(const _UnloadAck());

      case _ShutdownRequest():
        await engine?.unload();
        workerPort.close();
        // Isolate.exit's finalMessage is delivered atomically as the isolate
        // terminates — the only way to guarantee the main isolate is told
        // the native context is freed before this isolate (and the thread
        // whisper_full/whisper_init ran on) disappears. A plain
        // mainSendPort.send() here would race the exit with no such
        // guarantee (FLUTTER_WHISPASTE-BC).
        Isolate.exit(mainSendPort, const _UnloadAck());
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
  Completer<void>? _unloadCompleter;
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
  Future<void> load({required String modelPath, String? vadModelPath}) async {
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
    _workerPort!.send(
      _LoadRequest(
        config: _config,
        modelPath: modelPath,
        vadModelPath: vadModelPath,
      ),
    );
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
    bool vadEnabled = false,
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
        vadEnabled: vadEnabled,
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
    if (_isolate == null || _workerPort == null) {
      _isLoaded = false;
      return;
    }
    // _whisperIsolateMain processes messages strictly one at a time (see its
    // `processing` chain), so if a _LoadRequest or _TranscribeRequest (the
    // post-load warmup/benchmark calls in SttServerStateNotifier._start also
    // go through this same queue) is still in flight, the _UnloadAck for the
    // request sent below cannot arrive until that synchronous, blocking
    // native FFI call returns — which can take many seconds (cold-start
    // warmup + benchmark). Waiting for it here would peg the app at
    // near-100% CPU for the whole gap for no benefit: the same message queue
    // still guarantees this _UnloadRequest is handled (and whisper_free()
    // runs) strictly before any request sent after it — including a
    // subsequent load() from a model switch (see the "reload for real" test
    // below) — so skipping the wait never risks a stale/leaked native
    // context. For the app-quit caller (`runGracefulEngineShutdown`) there's
    // a second reason it's safe: the whole OS process exits right after this
    // returns anyway, tearing down whatever native/Metal state the in-flight
    // call still holds — confirmed safe by repro (SIGTERM during
    // load/warmup, followed by exit(0) once the previous 10s timeout gave up
    // waiting, never aborted; this just reaches the same safe exit sooner
    // instead of burning CPU for the rest of the timeout).
    final loadCompleter = _loadCompleter;
    final workerBusy =
        (loadCompleter != null && !loadCompleter.isCompleted) ||
        _pending.isNotEmpty;
    // Waits for the worker's _UnloadAck (native whisper_free() actually
    // ran) instead of firing-and-forgetting — otherwise a caller that
    // proceeds immediately (e.g. app quit → windowManager.destroy()) can
    // race the isolate's own native cleanup: if the process starts tearing
    // down Metal/GGML before whisper_free() ran, ggml_metal_rsets_free's
    // "resources still allocated" assertion aborts the whole app
    // (FLUTTER_WHISPASTE-BC, reproduced live on macOS at quit time).
    final completer = Completer<void>();
    _unloadCompleter = completer;
    try {
      _workerPort!.send(const _UnloadRequest());
    } catch (e) {
      _log.warning('Failed to signal worker unload: $e');
      _isLoaded = false;
      return;
    }
    if (workerBusy) {
      _isLoaded = false;
      return;
    }
    // Clear immediately — NOT gated behind the ack awaited below. A caller
    // that fires `stop()` without awaiting it (the debounced model-switch
    // pre-warm in `SttServerStateNotifier`) can call `load()` again while
    // this unload is still in flight; `load()`'s `if (_isLoaded) return;`
    // guard must see `false` by then, or it short-circuits without ever
    // sending a new `_LoadRequest` — the worker still frees the *old*
    // context, the notifier believes the *new* model is ready, and the next
    // `transcribe()` throws `whisper_engine_not_loaded` (reproduced live:
    // switching STT models mid-session silently broke dictation until an
    // idle-unload or app restart). The worker's own message queue
    // (`_whisperIsolateMain`'s `processing` chain) still handles this
    // `_UnloadRequest` strictly before any `_LoadRequest` sent after it, so
    // the reload above is never dropped or reordered — only the awaited
    // Future here (for callers like app-quit that must know the native
    // context is actually freed, FLUTTER_WHISPASTE-BC) still waits on the ack.
    _isLoaded = false;
    await awaitGracefulShutdown(
      completer: completer,
      timeout: const Duration(seconds: 10),
      log: _log,
      timeoutMessage:
          'Worker unload did not acknowledge within 10s — proceeding anyway',
      onTimeout: () {},
    );
  }

  /// Fully tears down the worker isolate. Not part of the [WhisperEngine]
  /// contract — called from provider disposal, mirroring
  /// [ParakeetEngineNotifier]'s `stop()`/`_shutdownSync()`.
  ///
  /// Waits (bounded) for the worker to free its native context and exit
  /// gracefully — the same FLUTTER_WHISPASTE-BC race [unload] guards
  /// against, but for full isolate teardown: an unconditional
  /// `Isolate.kill(priority: immediate)` right after signalling shutdown
  /// (the previous behaviour) could preempt the worker before
  /// `whisper_free()` ever ran, since killing a Dart isolate does not free
  /// native memory/GPU resources that isolate's FFI calls allocated. Only
  /// falls back to a hard kill if the worker doesn't exit in time.
  Future<void> shutdown() async {
    final isolate = _isolate;
    if (isolate == null) return;

    final completer = Completer<void>();
    _unloadCompleter = completer;
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
    _isLoaded = false;
  }

  // Structurally similar to ParakeetEngineNotifier._handleWorkerMessage, but
  // switches over a distinct sealed message hierarchy for an independent
  // isolate worker; a shared dispatcher would couple the two STT engines.
  // loam-ignore: code-duplicates – see comment above
  void _handleWorkerMessage(dynamic message) {
    switch (message) {
      case final _LoadResult r:
        _loadCompleter?.complete(r);
      case final _TranscribeResult r:
        _pending.remove(r.requestId)?.complete(r);
      case _UnloadAck():
        _unloadCompleter?.complete();
    }
  }
}

/// Overrideable [WhisperEngine] for the on-device whisper path.
///
/// Defaults to a [WhisperIsolateEngine] (worker isolate, see file doc
/// comment) wrapping the real [WhisperFfiEngine], configured with the compute
/// backend derived from hardware detection ([gpuInfoProvider]): NVIDIA→CUDA,
/// Apple→Metal, AMD/Intel→Vulkan, and CPU whenever no compatible GPU is
/// detected (or while detection is still in flight — callers are expected to
/// await `gpuInfoProvider.future` once at startup, see `main.dart`, so this
/// provider is not read before detection has settled in practice). The
/// user's "Grafikbeschleunigung" setting (`settings.behavior.gpuAcceleration`)
/// overrides this: `disabled` ("Nur CPU") always forces [WhisperBackend.cpu],
/// `auto`/`enabled` use the detected backend. Tests override it with a fake.
final whisperEngineProvider = Provider<WhisperEngine>((ref) {
  final gpuPreference = ref.watch(
    settingsProvider.select((s) => s.value?.behavior.gpuAcceleration),
  );
  final backend = gpuPreference == GpuAcceleration.disabled.value
      ? WhisperBackend.cpu
      : whisperBackendFromName(
          ref.watch(gpuInfoProvider).value?.optimalBackend,
        );
  final engine = WhisperIsolateEngine(backend: backend);
  ref.onDispose(engine.shutdown);
  return engine;
});

/// Always-CPU [WhisperEngine], used by [SttServerStateNotifier] as a one-shot
/// load-time fallback when [whisperEngineProvider]'s (GPU-backed) engine's
/// model load hangs past its internal timeout (FLUTTER_WHISPASTE-80: a
/// GPU/driver cold-start — e.g. first-ever shader compile — that never
/// completes, distinct from a normal, merely slow load). Never selected by
/// hardware detection, so retrying against this engine cannot hit the same
/// class of GPU-init hang.
final whisperCpuFallbackEngineProvider = Provider<WhisperEngine>((ref) {
  final engine = WhisperIsolateEngine(backend: WhisperBackend.cpu);
  ref.onDispose(engine.shutdown);
  return engine;
});

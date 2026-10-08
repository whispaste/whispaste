/// Real in-process [SmartModeEngine] backed by a bundled `libllama` +
/// `libsmartmode_shim` via `dart:ffi` (llama.cpp b10150, Gemma-4-E2B-it).
/// Same bundling mechanism per platform as [WhisperFfiEngine] (macOS: Xcode
/// "[WP] Embed & Sign libllama" phase, `../Frameworks/` resolution,
/// `@loader_path`-relocatable dylibs, Apple Guideline 2.5.2
/// no-runtime-code-download constraint; Windows: DLLs staged next to
/// `whispaste.exe` under a dedicated `smart_mode\` subdirectory; Linux:
/// `lib/smart_mode/` of the Flutter bundle, see [smartModeLibraryPathFor]).
///
/// Hosted like `whisper_isolate_engine.dart`: every blocking native call
/// (model load, decode loop) runs in one long-lived worker isolate, so the
/// UI isolate never stalls. The ~2.9GB GGUF is loaded on the first [run] and
/// stays resident for subsequent calls until it has been idle for the STT
/// idle-unload window (`stt.idleTimeoutMinutes`, same "<= 0 = never"
/// semantics) — or, on low-RAM systems, is freed right after every call so
/// the Whisper model keeps priority (see [smartModeKeepsModelResident]).
/// [cancel] really aborts an in-flight generation via a native abort flag
/// polled per token by the shim.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/windows_dll_search_path.dart';
import '../hardware_info_service.dart' as hw;
import '../path_service.dart';
import '../stt/isolate_shutdown_helper.dart';
import '../stt/stt_idle_timer.dart';
import 'smart_mode_engine.dart';
import 'smart_mode_openai_engine.dart';

final _log = AppLogger('SmartModeFfi');

typedef _SmartModeLoadNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<Utf8> modelPath,
      ffi.Int32 nCtx,
      ffi.Int32 nGpuLayers,
    );
typedef _SmartModeLoadDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<Utf8> modelPath,
      int nCtx,
      int nGpuLayers,
    );
typedef _SmartModeGenerateNative =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void> session,
      ffi.Pointer<Utf8> systemPrompt,
      ffi.Pointer<Utf8> userText,
      ffi.Float temperature,
      ffi.Float topP,
      ffi.Int32 topK,
      ffi.Pointer<ffi.Int32> abortFlag,
    );
typedef _SmartModeGenerateDart =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void> session,
      ffi.Pointer<Utf8> systemPrompt,
      ffi.Pointer<Utf8> userText,
      double temperature,
      double topP,
      int topK,
      ffi.Pointer<ffi.Int32> abortFlag,
    );
typedef _SmartModeUnloadNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _SmartModeUnloadDart = void Function(ffi.Pointer<ffi.Void>);
typedef _SmartModeFreeResultNative =
    ffi.Void Function(ffi.Pointer<Utf8> result);
typedef _SmartModeFreeResultDart = void Function(ffi.Pointer<Utf8> result);

/// Test-only override for the directory [smartModeModelPath] resolves
/// against, mirroring [sttDirOverride]. Must stay null in production code.
String? smartModeModelDirOverride;

/// `models/smart_mode/<filename>` under [appDataDir] — a sibling of
/// [sttDir], not reusing it, since Smart-Mode-v2 models are a distinct asset
/// class (chat/instruct GGUF, not Whisper encoder-decoder GGML) with their
/// own licensing/attribution surface (Apache 2.0, see
/// `.scratch/smart-mode-v2/research-gemma-4-e2b-license-and-config.md`).
String smartModeModelPath({String filename = 'gemma-4-E2B-it-Q4_K_M.gguf'}) =>
    p.join(
      smartModeModelDirOverride ?? p.join(appDataDir(), 'models', 'smart_mode'),
      filename,
    );

/// Absolute path to the bundled `libsmartmode_shim` shared library, resolved
/// relative to [Platform.resolvedExecutable] exactly like
/// [whisperLibraryPathFor].
String defaultSmartModeLibraryPath() =>
    smartModeLibraryPathFor(Platform.resolvedExecutable);

/// Pure resolver behind [defaultSmartModeLibraryPath], split out for unit
/// tests exactly like [whisperLibraryPathFor]. Given the app [executablePath],
/// returns the bundled `libsmartmode_shim` path for [operatingSystem]
/// (defaults to the host's [Platform.operatingSystem]):
/// - macOS: `<App>.app/Contents/MacOS/<exe>` → `../Frameworks/libsmartmode_shim.dylib`
///   (embedded by the "[WP] Embed & Sign libllama" Xcode phase, see
///   `macos/embed_libllama.sh` — runs for every build).
/// - Windows: `smart_mode\smartmode_shim.dll` next to `whispaste.exe` — a
///   dedicated subdirectory, NOT the Flutter bundle root that
///   [whisperLibraryPathFor] uses. llama.cpp vendors its own copy of `ggml`,
///   independently pinned from whisper.cpp's and not ABI-compatible with it,
///   so Windows needs the same two measures as Linux: the separate directory
///   keeps the shim's backend scan to its own `ggml-cpu-*.dll`/
///   `ggml-vulkan.dll`, and the core ggml DLLs are renamed
///   (`ggml-llama.dll`, `ggml-base-llama.dll`, see `build-libllama-windows.ps1`)
///   because the Windows loader resolves static imports by module name
///   process-wide — an unrenamed `ggml.dll` bound to whichever engine loaded
///   first (error 127 for the shim after libwhisper).
/// - Linux (the fallback, like [whisperLibraryPathFor]):
///   `lib/smart_mode/libsmartmode_shim.so` next to the executable — a
///   subdirectory of the `lib/` that holds libwhisper, staged by
///   `scripts/build-libllama-linux.sh --bundle`. Linux needs BOTH measures:
///   the separate directory keeps ggml's backend scan
///   (`ggml_backend_load_all_from_path`, see `smart_mode_shim.cpp`) from
///   picking up libwhisper's `libggml-cpu.so`/`libggml-vulkan.so`, and the
///   core ggml libraries are renamed with a `-llama` suffix because the ELF
///   loader dedupes `DT_NEEDED` entries by SONAME process-wide — an unrenamed
///   `libggml.so.0` would silently bind to whichever engine loaded first.
String smartModeLibraryPathFor(
  String executablePath, {
  String? operatingSystem,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final execDir = p.dirname(executablePath);
  if (os == 'macos') {
    return p.normalize(
      p.join(execDir, '..', 'Frameworks', 'libsmartmode_shim.dylib'),
    );
  }
  if (os == 'windows') {
    return p.join(execDir, 'smart_mode', 'smartmode_shim.dll');
  }
  return p.join(execDir, 'lib', 'smart_mode', 'libsmartmode_shim.so');
}

/// Whether the local Smart Mode engine's native library is present in this
/// build, so the UI can disable the on-device option (with a hint) instead
/// of offering a choice that can only fail at load time.
///
/// Only Linux probes the file: there the library is staged by a separate
/// post-build step (`scripts/build-libllama-linux.sh --bundle`) that a plain
/// `flutter build linux`/`flutter run` skips. macOS embeds it in every build
/// (Xcode phase) and the Windows release job hard-fails without it, so both
/// report `true` without touching the disk — which also keeps widget tests
/// and store screenshots on those hosts rendering the real settings UI.
bool isSmartModeLocalEngineAvailable({
  String? operatingSystem,
  String? libraryPath,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  if (os == 'macos' || os == 'windows') return true;
  return File(
    libraryPath ?? smartModeLibraryPathFor(Platform.resolvedExecutable),
  ).existsSync();
}

/// [isSmartModeLocalEngineAvailable] for the running app — overridable in
/// tests. Not reactive: the bundle cannot change while the app runs.
final smartModeLocalEngineAvailableProvider = Provider<bool>(
  (ref) => isSmartModeLocalEngineAvailable(),
);

/// Below this much physical RAM, Smart Mode does not keep its model resident
/// between calls: the ~2.9GB GGUF is freed right after every [run], so on the
/// 8 GB class (the app's minimum, see `ram_gate_config.dart`) a loaded
/// Whisper model never has to share memory with an idle Smart-Mode model —
/// under memory pressure Smart Mode is always the one unloaded first.
const int kSmartModeResidentMinRamMB = 12 * 1024;

/// Whether [SmartModeFfiEngine] may keep its model loaded between calls on a
/// system with [ramMB] of physical RAM. Unknown RAM (`null`, detection
/// failed) fails open, mirroring the app's RAM preflight.
bool smartModeKeepsModelResident(int? ramMB) =>
    ramMB == null || ramMB >= kSmartModeResidentMinRamMB;

/// Thrown by [SmartModeFfiEngine.run] when [SmartModeFfiEngine.cancel]
/// aborted the generation.
class SmartModeAbortedException implements Exception {
  const SmartModeAbortedException();

  @override
  String toString() => 'SmartModeAbortedException: smart_mode_aborted';
}

/// The blocking native surface [SmartModeFfiEngine] drives inside its worker
/// isolate — production uses `libsmartmode_shim` via FFI, tests a fake.
/// Every method is synchronous and only ever called from the worker.
abstract class SmartModeNative {
  /// Loads the model at [modelPath]. Throws on failure.
  void load({required String modelPath});

  /// Generates one response on the loaded model. Must stop early once
  /// [abortFlag] holds a non-zero value (it is set from another isolate).
  String generate({
    required String systemPrompt,
    required String userText,
    required ffi.Pointer<ffi.Int32> abortFlag,
  });

  /// Frees the loaded model. No-op when nothing is loaded.
  void unload();
}

/// Creates the [SmartModeNative] inside the worker isolate. Must be sendable
/// to an isolate of the same group (a top-level function or a closure over
/// plain data).
typedef SmartModeNativeFactory = SmartModeNative Function();

/// Timing of the last [SmartModeFfiEngine.run], as reported by the worker.
class SmartModeRunStats {
  const SmartModeRunStats({
    required this.loadedModel,
    required this.loadTime,
    required this.generateTime,
  });

  /// `true` if this run had to load the model (cold), `false` if it reused
  /// the resident one (warm).
  final bool loadedModel;
  final Duration loadTime;
  final Duration generateTime;
}

/// [SmartModeNative] backed by the bundled `libsmartmode_shim`.
class _ShimNative implements SmartModeNative {
  _ShimNative(this._libraryPath);

  final String _libraryPath;

  _SmartModeLoadDart? _load;
  _SmartModeGenerateDart? _generate;
  _SmartModeUnloadDart? _unload;
  _SmartModeFreeResultDart? _freeResult;
  ffi.Pointer<ffi.Void> _session = ffi.nullptr;

  void _bind() {
    if (_load != null) return;
    final ffi.DynamicLibrary dylib;
    try {
      ensureWindowsDllSearchPath(_libraryPath);
      dylib = ffi.DynamicLibrary.open(_libraryPath);
    } catch (e) {
      throw StateError('smart_mode_library_load_failed: $e');
    }
    _generate = dylib
        .lookupFunction<_SmartModeGenerateNative, _SmartModeGenerateDart>(
          'smart_mode_generate',
        );
    _unload = dylib
        .lookupFunction<_SmartModeUnloadNative, _SmartModeUnloadDart>(
          'smart_mode_unload',
        );
    _freeResult = dylib
        .lookupFunction<_SmartModeFreeResultNative, _SmartModeFreeResultDart>(
          'smart_mode_free_result',
        );
    _load = dylib.lookupFunction<_SmartModeLoadNative, _SmartModeLoadDart>(
      'smart_mode_load',
    );
  }

  @override
  void load({required String modelPath}) {
    _bind();
    if (_session != ffi.nullptr) return;
    final modelPathC = modelPath.toNativeUtf8();
    try {
      _session = _load!(modelPathC, 2048, 99);
    } finally {
      malloc.free(modelPathC);
    }
    if (_session == ffi.nullptr) {
      throw StateError('smart_mode_load_failed');
    }
  }

  @override
  String generate({
    required String systemPrompt,
    required String userText,
    required ffi.Pointer<ffi.Int32> abortFlag,
  }) {
    if (_session == ffi.nullptr) throw StateError('smart_mode_not_loaded');
    final systemPromptC = systemPrompt.toNativeUtf8();
    final userTextC = userText.toNativeUtf8();
    try {
      // Config validated in the spike test (spike-test-results.md):
      // temperature 0.3 / top_p 0.95 / top_k 64, `enable_thinking: false`
      // (baked into the shim itself, not a parameter here — see
      // smart_mode_shim.cpp).
      final resultPtr = _generate!(
        _session,
        systemPromptC,
        userTextC,
        0.3,
        0.95,
        64,
        abortFlag,
      );
      if (resultPtr == ffi.nullptr) {
        throw StateError('smart_mode_run_failed');
      }
      final result = resultPtr.toDartString();
      _freeResult!(resultPtr);
      return result;
    } finally {
      malloc.free(systemPromptC);
      malloc.free(userTextC);
    }
  }

  @override
  void unload() {
    if (_session == ffi.nullptr) return;
    _unload!(_session);
    _session = ffi.nullptr;
  }
}

SmartModeNativeFactory _shimFactory(String libraryPath) =>
    () => _ShimNative(libraryPath);

// ---------------------------------------------------------------------------
// Isolate protocol — plain data only (plus the same-group-sendable native
// factory in [_WorkerInit]).
// ---------------------------------------------------------------------------

class _WorkerInit {
  const _WorkerInit(this.mainPort, this.nativeFactory);
  final SendPort mainPort;
  final SmartModeNativeFactory nativeFactory;
}

class _RunRequest {
  const _RunRequest({
    required this.requestId,
    required this.modelPath,
    required this.systemPrompt,
    required this.userText,
    required this.abortFlagAddress,
  });
  final int requestId;
  final String modelPath;
  final String systemPrompt;
  final String userText;

  /// Address of a main-isolate-owned `int32` the main isolate sets to 1 to
  /// abort this request (native memory is shared across isolates).
  final int abortFlagAddress;
}

class _RunResult {
  const _RunResult({
    required this.requestId,
    this.text,
    this.error,
    this.aborted = false,
    this.loadedModel = false,
    this.resident = false,
    this.loadMicros = 0,
    this.generateMicros = 0,
    this.forcedByShutdown = false,
  });
  final int requestId;
  final String? text;
  final String? error;
  final bool aborted;
  final bool loadedModel;
  final bool resident;
  final int loadMicros;
  final int generateMicros;

  /// Synthesized on the main isolate by [SmartModeFfiEngine.shutdown] for a
  /// run the worker never answered.
  final bool forcedByShutdown;
}

class _UnloadRequest {
  const _UnloadRequest();
}

class _UnloadAck {
  const _UnloadAck();
}

class _ShutdownRequest {
  const _ShutdownRequest();
}

/// Worker entry point. Every handler is synchronous (the native calls block),
/// so messages are processed strictly one at a time in arrival order — an
/// unload/shutdown can never tear the model down under a running generation.
void _smartModeIsolateMain(_WorkerInit init) {
  final mainPort = init.mainPort;
  final workerPort = ReceivePort();
  mainPort.send(workerPort.sendPort);

  SmartModeNative? native;
  String? loadedModelPath;

  void unloadModel() {
    native?.unload();
    loadedModelPath = null;
  }

  void handleRun(_RunRequest req) {
    final abortFlag = ffi.Pointer<ffi.Int32>.fromAddress(req.abortFlagAddress);
    if (abortFlag.value != 0) {
      mainPort.send(
        _RunResult(
          requestId: req.requestId,
          aborted: true,
          resident: loadedModelPath != null,
        ),
      );
      return;
    }

    var loadedModel = false;
    var loadMicros = 0;
    try {
      final n = native ??= init.nativeFactory();
      if (loadedModelPath != req.modelPath) {
        if (loadedModelPath != null) unloadModel();
        final sw = Stopwatch()..start();
        n.load(modelPath: req.modelPath);
        loadMicros = sw.elapsedMicroseconds;
        loadedModelPath = req.modelPath;
        loadedModel = true;
      }
    } catch (e) {
      loadedModelPath = null;
      mainPort.send(_RunResult(requestId: req.requestId, error: '$e'));
      return;
    }

    final sw = Stopwatch()..start();
    String? text;
    String? error;
    try {
      text = native!.generate(
        systemPrompt: req.systemPrompt,
        userText: req.userText,
        abortFlag: abortFlag,
      );
    } catch (e) {
      error = '$e';
    }
    mainPort.send(
      _RunResult(
        requestId: req.requestId,
        text: text,
        error: error,
        aborted: abortFlag.value != 0,
        loadedModel: loadedModel,
        resident: loadedModelPath != null,
        loadMicros: loadMicros,
        generateMicros: sw.elapsedMicroseconds,
      ),
    );
  }

  workerPort.listen((dynamic message) {
    switch (message) {
      case final _RunRequest req:
        handleRun(req);
      case _UnloadRequest():
        unloadModel();
        mainPort.send(const _UnloadAck());
      case _ShutdownRequest():
        unloadModel();
        workerPort.close();
        // Delivered atomically as the isolate terminates — the native model
        // is guaranteed freed before the main isolate is told so (same
        // FLUTTER_WHISPASTE-BC reasoning as whisper_isolate_engine.dart).
        Isolate.exit(mainPort, const _UnloadAck());
    }
  });
}

// ---------------------------------------------------------------------------
// Main-isolate side.
// ---------------------------------------------------------------------------

/// Local [SmartModeEngine] — see the file doc comment for the isolate,
/// residency and abort model.
class SmartModeFfiEngine implements SmartModeEngine {
  SmartModeFfiEngine({
    String? libraryPath,
    String? modelPath,
    SmartModeNativeFactory? nativeFactory,
    Duration Function()? idleTimeout,
    Future<int?> Function()? detectRamMB,
  }) : _modelPath = modelPath ?? smartModeModelPath(),
       _nativeFactory =
           nativeFactory ??
           _shimFactory(libraryPath ?? defaultSmartModeLibraryPath()),
       _idleTimeout = idleTimeout ?? (() => const Duration(minutes: 5)),
       _detectRamMB = detectRamMB ?? hw.detectRamMB;

  final String _modelPath;
  final SmartModeNativeFactory _nativeFactory;
  final Duration Function() _idleTimeout;
  final Future<int?> Function() _detectRamMB;

  Isolate? _isolate;
  SendPort? _workerPort;
  Future<SendPort>? _workerReady;
  StreamSubscription<dynamic>? _sub;

  final Map<int, Completer<_RunResult>> _pending = {};
  final Map<int, ffi.Pointer<ffi.Int32>> _abortFlags = {};
  final List<Completer<void>> _unloadWaiters = [];
  int _nextRequestId = 0;

  final SttIdleTimer _idleTimer = SttIdleTimer();
  Future<bool>? _keepsResident;
  bool _resident = false;
  int _modelLoadCount = 0;
  SmartModeRunStats? _lastRunStats;

  /// Whether the worker currently holds the model in memory.
  bool get isModelResident => _resident;

  /// How many times the worker had to (re)load the model.
  @visibleForTesting
  int get modelLoadCount => _modelLoadCount;

  /// Timing of the most recent completed [run].
  SmartModeRunStats? get lastRunStats => _lastRunStats;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    if (!File(_modelPath).existsSync()) {
      throw StateError('smart_mode_model_not_found: $_modelPath');
    }
    _idleTimer.cancel();

    // Registered before the first await, so a [cancel] issued right after
    // this call already covers this run.
    final requestId = _nextRequestId++;
    final abortFlag = calloc<ffi.Int32>();
    final completer = Completer<_RunResult>();
    _pending[requestId] = completer;
    _abortFlags[requestId] = abortFlag;

    final SendPort port;
    try {
      port = await _ensureWorker();
    } catch (_) {
      _pending.remove(requestId);
      _abortFlags.remove(requestId);
      calloc.free(abortFlag);
      rethrow;
    }
    port.send(
      _RunRequest(
        requestId: requestId,
        modelPath: _modelPath,
        systemPrompt: systemPrompt,
        userText: userText,
        abortFlagAddress: abortFlag.address,
      ),
    );

    final result = await completer.future;
    _pending.remove(requestId);
    _abortFlags.remove(requestId);
    // Only free the flag once the worker answered: an engine torn down by a
    // forced kill (see [shutdown]) may still have a native call reading it.
    if (!result.forcedByShutdown) calloc.free(abortFlag);

    _resident = result.resident;
    if (result.loadedModel) _modelLoadCount++;
    _lastRunStats = SmartModeRunStats(
      loadedModel: result.loadedModel,
      loadTime: Duration(microseconds: result.loadMicros),
      generateTime: Duration(microseconds: result.generateMicros),
    );
    if (result.error == null || result.aborted) {
      _log.info(
        result.loadedModel
            ? 'Smart Mode model loaded (cold) in '
                  '${result.loadMicros ~/ 1000} ms, generated in '
                  '${result.generateMicros ~/ 1000} ms'
            : 'Smart Mode reused resident model (warm), generated in '
                  '${result.generateMicros ~/ 1000} ms',
      );
    }

    await _afterRun();

    if (result.aborted) throw const SmartModeAbortedException();
    final error = result.error;
    if (error != null) {
      _log.warning('Smart Mode run failed: $error');
      throw StateError(error);
    }
    return result.text ?? '';
  }

  /// Arms the idle unload — or, on low-RAM systems, unloads right away.
  Future<void> _afterRun() async {
    if (_pending.isNotEmpty || !_resident) return;
    final keepResident = await (_keepsResident ??= _detectRamMB().then(
      smartModeKeepsModelResident,
      onError: (Object _) => true,
    ));
    if (_pending.isNotEmpty || !_resident) return;
    if (!keepResident) {
      _log.info('Low RAM — unloading Smart Mode model right after the run');
      await unload();
      return;
    }
    final timeout = _idleTimeout();
    if (timeout <= Duration.zero) return;
    _idleTimer.start(timeout, () {
      if (_pending.isNotEmpty) return;
      _log.info(
        'Smart Mode idle for ${timeout.inMinutes} min, unloading model to '
        'free memory',
      );
      unawaited(unload());
    });
  }

  @override
  Future<void> cancel() async {
    if (_abortFlags.isEmpty) return;
    _log.info('Aborting ${_abortFlags.length} in-flight Smart Mode run(s)');
    for (final flag in _abortFlags.values) {
      flag.value = 1;
    }
  }

  /// Frees the resident model (the worker isolate stays alive for reuse).
  /// Queued behind any in-flight run, never interrupting it.
  Future<void> unload() async {
    _idleTimer.cancel();
    final port = _workerPort;
    if (port == null) {
      _resident = false;
      return;
    }
    final completer = Completer<void>();
    _unloadWaiters.add(completer);
    port.send(const _UnloadRequest());
    await awaitGracefulShutdown(
      completer: completer,
      timeout: const Duration(seconds: 10),
      log: _log,
      timeoutMessage:
          'Smart Mode worker unload did not acknowledge within 10s — '
          'proceeding anyway',
      onTimeout: () => _unloadWaiters.remove(completer),
    );
  }

  /// Tears down the worker isolate, freeing the model first. In-flight runs
  /// are aborted. Called on provider disposal and app quit (the native
  /// Metal/GGML resources must be freed before the process exits, same as
  /// the Whisper engine — FLUTTER_WHISPASTE-BC).
  Future<void> shutdown() async {
    _idleTimer.cancel();
    final isolate = _isolate;
    if (isolate == null) return;
    await cancel();

    final completer = Completer<void>();
    _unloadWaiters.add(completer);
    try {
      _workerPort?.send(const _ShutdownRequest());
    } catch (e) {
      _log.warning('Failed to signal Smart Mode worker shutdown: $e');
    }
    await awaitGracefulShutdown(
      completer: completer,
      timeout: const Duration(seconds: 10),
      log: _log,
      timeoutMessage:
          'Smart Mode worker shutdown did not complete within 10s — '
          'force-killing (native resources may leak)',
      onTimeout: () => isolate.kill(priority: Isolate.immediate),
    );
    await _sub?.cancel();
    _sub = null;
    _isolate = null;
    _workerPort = null;
    _workerReady = null;
    _resident = false;
    for (final entry in _pending.entries.toList()) {
      if (entry.value.isCompleted) continue;
      entry.value.complete(
        _RunResult(requestId: entry.key, aborted: true, forcedByShutdown: true),
      );
    }
  }

  Future<SendPort> _ensureWorker() => _workerReady ??= _spawnWorker();

  Future<SendPort> _spawnWorker() async {
    final mainReceivePort = ReceivePort();
    final portCompleter = Completer<SendPort>();
    _sub = mainReceivePort.listen((dynamic message) {
      if (message is SendPort && !portCompleter.isCompleted) {
        portCompleter.complete(message);
        return;
      }
      _handleWorkerMessage(message);
    });
    try {
      _isolate = await Isolate.spawn(
        _smartModeIsolateMain,
        _WorkerInit(mainReceivePort.sendPort, _nativeFactory),
        debugName: 'smart_mode_worker',
      );
      final port = await portCompleter.future.timeout(
        const Duration(seconds: 10),
      );
      _workerPort = port;
      return port;
    } catch (e) {
      await _sub?.cancel();
      _sub = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _workerReady = null;
      rethrow;
    }
  }

  void _handleWorkerMessage(dynamic message) {
    switch (message) {
      case final _RunResult r:
        final completer = _pending[r.requestId];
        if (completer != null && !completer.isCompleted) completer.complete(r);
      case _UnloadAck():
        _resident = false;
        if (_unloadWaiters.isNotEmpty) {
          _unloadWaiters.removeAt(0).complete();
        }
    }
  }
}

/// Production [SmartModeEngine] — [RecordingOrchestrator] (ticket 02) and
/// [SmartModeRetroactiveService] read this via [Ref.read], never watch it.
/// Tests override this provider with a fake implementing [SmartModeEngine]
/// instead of constructing a real [SmartModeFfiEngine] (which would
/// `dlopen` a native library that doesn't exist in the test environment).
///
/// Selects local vs. cloud per [SmartModeSettings.provider] (ticket 06,
/// ADR 0010: strict either-or, never both). Watches only that one field: the
/// local engine is long-lived (resident model, worker isolate), so unrelated
/// settings changes must not rebuild — and thereby cold-restart — it. Its
/// idle-unload window follows the Whisper engine's
/// `stt.idleTimeoutMinutes`, read at arm time so changes apply without a rebuild.
final smartModeEngineProvider = Provider<SmartModeEngine>((ref) {
  final providerType = SmartModeProviderType.fromValue(
    ref.watch(settingsProvider.select((s) => s.value?.smartMode.provider)),
  );
  switch (providerType) {
    case SmartModeProviderType.local:
      final engine = SmartModeFfiEngine(
        idleTimeout: () => Duration(
          minutes: (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .stt
              .idleTimeoutMinutes,
        ),
      );
      ref.onDispose(engine.shutdown);
      return engine;
    case SmartModeProviderType.openAI:
      return SmartModeOpenAiEngine(ref: ref);
  }
});

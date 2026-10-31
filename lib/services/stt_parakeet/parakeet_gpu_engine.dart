/// GPU Parakeet engine: libparakeet (whisper.cpp v1.9.5) on the ggml backends,
/// run in a long-lived worker [Isolate].
///
/// The native calls are synchronous, so they stay off the UI isolate. The
/// worker owns the native context. It is the only place that calls into
/// libparakeet, because `parakeet_full` is not thread-safe per context.
///
/// Long recordings are split with the same 25 s chunker as the sherpa engine
/// (`parakeet_audio_chunker.dart`). Without it, memory grows steeply with
/// audio length. Cancellation runs through `abort_callback`: the caller sets a
/// native flag and ggml stops at its next graph boundary.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../stt/native_call_guard.dart';
import '../stt/whisper/ggml_backend_registry.dart';
import '../transcription/transcript_seam.dart';
import 'parakeet_audio_chunker.dart';
import 'parakeet_bindings.dart';

final _log = AppLogger('ParakeetGpu');

/// Thrown for every failure of the GPU engine. The notifier catches it and
/// falls back to sherpa-onnx, so the message is for logs, not for the user.
class ParakeetGpuException implements Exception {
  ParakeetGpuException(this.message);
  final String message;
  @override
  String toString() => 'ParakeetGpuException: $message';
}

// ---------------------------------------------------------------------------
// Isolate protocol: plain data only, safe across the isolate boundary.
// ---------------------------------------------------------------------------

class _Init {
  const _Init({
    required this.libraryPath,
    required this.modelPath,
    required this.threads,
    required this.abortFlagAddress,
  });
  final String libraryPath;
  final String modelPath;
  final int threads;
  final int abortFlagAddress;
}

class _InitReply {
  const _InitReply({this.error, this.device});
  final String? error;
  final String? device;
}

class _Transcribe {
  const _Transcribe({required this.id, required this.samples});
  final int id;
  final Float32List samples;
}

class _TranscribeReply {
  const _TranscribeReply({required this.id, this.text, this.error});
  final int id;
  final String? text;
  final String? error;
}

class _Shutdown {
  const _Shutdown();
}

class _ShutdownAck {
  const _ShutdownAck();
}

/// Abort callback, invoked by ggml between graph computations on the thread
/// running `parakeet_full`. That is the worker isolate's thread, so a
/// `Pointer.fromFunction` callback is valid here. The user-data pointer is the
/// native flag the main isolate sets on timeout.
bool _abortWhenFlagSet(ffi.Pointer<ffi.Void> userData) =>
    userData.cast<ffi.Int32>().value != 0;

/// Isolate entry point. Holds the native context for the isolate's lifetime.
void _gpuWorkerMain(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);

  ParakeetBindings? bindings;
  ffi.Pointer<ffi.Void>? ctx;
  ffi.Pointer<ffi.Int32>? abortFlag;
  var threads = 1;

  port.listen((dynamic message) {
    switch (message) {
      case final _Init req:
        try {
          final loaded = _loadNative(req);
          bindings = loaded.$1;
          ctx = loaded.$2;
          abortFlag = ffi.Pointer<ffi.Int32>.fromAddress(req.abortFlagAddress);
          threads = req.threads;
          mainPort.send(_InitReply(device: loaded.$3));
        } on Object catch (e) {
          mainPort.send(_InitReply(error: '$e'));
        }

      case final _Transcribe req:
        final b = bindings;
        final c = ctx;
        final flag = abortFlag;
        if (b == null || c == null || flag == null) {
          mainPort.send(
            _TranscribeReply(id: req.id, error: 'parakeet_gpu_not_initialized'),
          );
          break;
        }
        try {
          flag.value = 0; // a stale abort from an earlier timeout must not leak
          final text = _transcribeChunks(b, c, flag, req.samples, threads);
          mainPort.send(_TranscribeReply(id: req.id, text: text));
        } on Object catch (e) {
          mainPort.send(_TranscribeReply(id: req.id, error: '$e'));
        }

      case _Shutdown():
        final b = bindings;
        final c = ctx;
        if (b != null && c != null) b.free(c);
        ctx = null;
        mainPort.send(const _ShutdownAck());
        port.close();
    }
  });
}

/// Loads libparakeet, the ggml backend modules and the model. Returns the
/// bindings, the context and the name of the GPU device in use.
(ParakeetBindings, ffi.Pointer<ffi.Void>, String) _loadNative(_Init req) {
  if (!File(req.libraryPath).existsSync()) {
    throw ParakeetGpuException('library_missing');
  }
  final backendDir = p.dirname(req.libraryPath);
  final lib = ffi.DynamicLibrary.open(req.libraryPath);
  final bindings = ParakeetBindings(lib);

  // ggml's registry is process-wide and dedupes by backend name, so loading
  // the modules here is safe even when whisper already did it.
  final ggml = openGgmlLibrary(backendDir);
  if (ggml != null) loadGgmlBackendModules(ggml, backendDir);

  // GetProcAddress, unlike dlsym, does not search a DLL's imports, and the
  // per-device accessors live in ggml-base.dll, not ggml.dll.
  final basePath = p.join(backendDir, 'ggml-base.dll');
  final base = Platform.isWindows && File(basePath).existsSync()
      ? ffi.DynamicLibrary.open(basePath)
      : null;
  final device = _gpuDeviceName([?ggml, ?base], _ggmlRegistryIn(backendDir));
  if (device == null) throw ParakeetGpuException('no_gpu_device');

  final params = bindings.contextDefaultParams();
  params.use_gpu = true;
  params.gpu_device = 0;
  final ctx = bindings.initFromFile(req.modelPath, params);
  if (ctx == ffi.nullptr) throw ParakeetGpuException('init_failed');
  return (bindings, ctx, device);
}

/// Transcribes [samples] in chunks of at most 25 s. Returns the segments of
/// all chunks joined by single spaces, as the sherpa engine does.
String _transcribeChunks(
  ParakeetBindings b,
  ffi.Pointer<ffi.Void> ctx,
  ffi.Pointer<ffi.Int32> abortFlag,
  Float32List samples,
  int threads,
) {
  final texts = <String>[];
  final overlaps = <bool>[];
  // Empty input never reaches the native call: parakeet_full with zero samples
  // keeps the segments of the previous run, which would repeat its text.
  if (samples.isEmpty) return '';
  for (final chunk in splitForParakeet(samples, sampleRate: 16000)) {
    if (chunk.samples.isEmpty) continue;
    texts.add(_decodeChunk(b, ctx, abortFlag, chunk.samples, threads).trim());
    overlaps.add(chunk.overlapsPrevious);
  }
  return joinSeamTexts(texts, overlaps);
}

String _decodeChunk(
  ParakeetBindings b,
  ffi.Pointer<ffi.Void> ctx,
  ffi.Pointer<ffi.Int32> abortFlag,
  Float32List chunk,
  int threads,
) {
  final pcm = calloc<ffi.Float>(chunk.length);
  try {
    pcm.asTypedList(chunk.length).setAll(0, chunk);
    final params = b.fullDefaultParams();
    params.n_threads = threads;
    params.abort_callback =
        ffi.Pointer.fromFunction<ffi.Bool Function(ffi.Pointer<ffi.Void>)>(
          _abortWhenFlagSet,
          false,
        ).cast();
    params.abort_callback_user_data = abortFlag.cast();
    final rc = b.full(ctx, params, pcm, chunk.length);
    if (rc != 0) throw ParakeetGpuException('parakeet_full rc=$rc');
    final n = b.segmentCount(ctx);
    final buf = StringBuffer();
    for (var i = 0; i < n; i++) {
      buf.write(b.segmentText(ctx, i));
    }
    return buf.toString();
  } finally {
    calloc.free(pcm);
  }
}

ffi.DynamicLibrary? openGgmlLibrary(String dir) {
  for (final name in const [
    'libggml.0.dylib',
    'libggml.dylib',
    'libggml.so.0',
    'libggml.so',
    'ggml.dll',
  ]) {
    final path = p.join(dir, name);
    if (File(path).existsSync()) return ffi.DynamicLibrary.open(path);
  }
  return null;
}

/// The ggml registry calls for the libraries in [dir], through `wp_ffi_guard`.
GgmlBackendRegistry _ggmlRegistryIn(String dir) =>
    GgmlBackendRegistry(NativeCallGuard.nextTo(p.join(dir, 'libggml')));

/// Registers the ggml backend modules in [dir] through the guard. A backend
/// that throws is logged and leaves the GPU unregistered (CPU fallback).
void loadGgmlBackendModules(ffi.DynamicLibrary ggml, String dir) {
  final registry = _ggmlRegistryIn(dir);
  try {
    if (!registry.loadAllFromPath(ggml, dir)) registry.loadAll(ggml);
  } on NativeCallException catch (e) {
    _log.warning('ggml backend load threw natively: ${e.message}');
  }
}

/// Number of devices ggml has registered, or `null` when it cannot be asked
/// (no guard, or the call threw).
int? ggmlDeviceCount(ffi.DynamicLibrary ggml, String dir) {
  try {
    return _ggmlRegistryIn(dir).devCount(ggml);
  } on NativeCallException catch (e) {
    _log.warning('ggml device count threw natively: ${e.message}');
    return null;
  }
}

/// First GPU-class ggml device name, or `null` when only CPU is present.
/// `ggml_backend_dev_type`: 1 = GPU, 2 = IGPU (0 = CPU, 3 = ACCEL).
///
/// A split Windows bundle spreads the registry API over ggml.dll
/// (count/get) and ggml-base.dll (type/name); each symbol comes from the
/// first of [libs] that exports it.
String? _gpuDeviceName(
  List<ffi.DynamicLibrary> libs,
  GgmlBackendRegistry registry,
) {
  ffi.DynamicLibrary? providing(String symbol) {
    for (final lib in libs) {
      if (lib.providesSymbol(symbol)) return lib;
    }
    return null;
  }

  final countLib = providing('ggml_backend_dev_count');
  final getLib = providing('ggml_backend_dev_get');
  final typeLib = providing('ggml_backend_dev_type');
  final nameLib = providing('ggml_backend_dev_name');
  if (countLib == null ||
      getLib == null ||
      typeLib == null ||
      nameLib == null) {
    return null;
  }
  try {
    final count = registry.devCount(countLib) ?? 0;
    for (var i = 0; i < count; i++) {
      final dev = registry.devGet(getLib, i);
      if (dev == null) return null;
      final type = registry.devType(typeLib, dev);
      if (type == 1 || type == 2) return registry.devName(nameLib, dev);
    }
  } on NativeCallException catch (e) {
    _log.warning('ggml device enumeration threw natively: ${e.message}');
  }
  return null;
}

// ---------------------------------------------------------------------------
// Main-isolate handle
// ---------------------------------------------------------------------------

/// Long-lived GPU engine handle. Create with [open]; always [close] it.
class ParakeetGpuEngine {
  ParakeetGpuEngine._(this._isolate, this._replies, this._abortFlag);

  final Isolate _isolate;
  final ReceivePort _replies;
  final ffi.Pointer<ffi.Int32> _abortFlag;
  late final SendPort _port;

  /// Name of the GPU device libparakeet runs on, e.g. `MTL0`.
  late final String device;

  final Map<int, Completer<_TranscribeReply>> _pending = {};
  Completer<_InitReply>? _initCompleter;
  Completer<void>? _shutdownCompleter;
  int _nextId = 0;
  bool _closed = false;

  /// Test seam: an engine whose worker is the stand-in [port]. No isolate is
  /// spawned and no library is loaded; only [transcribe] and
  /// [hasNativeCallRunning] are meaningful on it.
  @visibleForTesting
  ParakeetGpuEngine.forTesting(SendPort port)
    : _isolate = Isolate.current,
      _replies = ReceivePort(),
      _abortFlag = calloc<ffi.Int32>(),
      _port = port,
      device = 'test';

  /// Spawns the worker and loads the library, backend modules and model.
  /// Throws [ParakeetGpuException] on any failure, and the worker is torn down.
  static Future<ParakeetGpuEngine> open({
    required String libraryPath,
    required String modelPath,
    required int threads,
  }) async {
    final abortFlag = calloc<ffi.Int32>();
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_gpuWorkerMain, replies.sendPort);
    final engine = ParakeetGpuEngine._(isolate, replies, abortFlag);
    final handshake = Completer<SendPort>();
    engine._initCompleter = Completer<_InitReply>();
    replies.listen((dynamic m) {
      if (m is SendPort) {
        if (!handshake.isCompleted) handshake.complete(m);
      } else {
        engine._onMessage(m);
      }
    });
    try {
      engine._port = await handshake.future.timeout(
        const Duration(seconds: 10),
      );
      engine._port.send(
        _Init(
          libraryPath: libraryPath,
          modelPath: modelPath,
          threads: threads,
          abortFlagAddress: abortFlag.address,
        ),
      );
      final reply = await engine._initCompleter!.future.timeout(
        const Duration(seconds: 120),
      );
      if (reply.error != null) throw ParakeetGpuException(reply.error!);
      engine.device = reply.device ?? 'unknown';
      return engine;
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      replies.close();
      calloc.free(abortFlag);
      rethrow;
    }
  }

  void _onMessage(dynamic m) {
    switch (m) {
      case final _InitReply r:
        final c = _initCompleter;
        if (c != null && !c.isCompleted) c.complete(r);
      case final _TranscribeReply r:
        // A reply for a request that already timed out is dropped here.
        final c = _pending.remove(r.id);
        if (c != null && !c.isCompleted) c.complete(r);
      case _ShutdownAck():
        final c = _shutdownCompleter;
        if (c != null && !c.isCompleted) c.complete();
    }
  }

  /// Transcribes 16 kHz mono float samples. On [timeout] the native abort flag
  /// is set; ggml then stops at its next graph boundary and the call throws.
  /// If the worker still has not answered [abortGrace] later (a hung driver,
  /// or no graph boundary reached), the call throws `transcribe_timeout`
  /// anyway, so a caller never waits forever on the GPU.
  Future<String> transcribe(
    Float32List samples, {
    required Duration timeout,
    Duration abortGrace = const Duration(seconds: 10),
  }) async {
    if (_closed) throw ParakeetGpuException('engine_closed');
    final id = _nextId++;
    final completer = Completer<_TranscribeReply>();
    _pending[id] = completer;
    _port.send(_Transcribe(id: id, samples: samples));
    final timer = Timer(timeout, () {
      _log.warning('GPU transcription exceeded $timeout — aborting');
      _abortFlag.value = 1;
    });
    try {
      final reply = await completer.future.timeout(
        timeout + abortGrace,
        onTimeout: () => throw ParakeetGpuException('transcribe_timeout'),
      );
      if (reply.error != null) throw ParakeetGpuException(reply.error!);
      return reply.text ?? '';
    } finally {
      // The entry stays until the worker answers (see [_onMessage]): a decode
      // that outlives its timeout is still running natively.
      timer.cancel();
    }
  }

  /// True while a native transcription is still in flight in the worker.
  bool get hasNativeCallRunning => _pending.isNotEmpty;

  /// Quit path: kills the worker now instead of waiting for its acknowledgement.
  /// A worker inside a native call is not interrupted by the kill; the caller
  /// must then end the process without static destructors (GS-117).
  void abandon() {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
  }

  /// Frees the native context and stops the worker. Idempotent. The abort
  /// flag is freed only after the worker acknowledged, because a worker still
  /// inside a native call could otherwise read freed memory.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final ack = Completer<void>();
    _shutdownCompleter = ack;
    _port.send(const _Shutdown());
    try {
      await ack.future.timeout(const Duration(seconds: 10));
      // The worker acks in order, so no decode is still in flight.
      _pending.clear();
      calloc.free(_abortFlag);
    } on TimeoutException {
      _log.warning('GPU worker did not acknowledge shutdown; killing it');
    }
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

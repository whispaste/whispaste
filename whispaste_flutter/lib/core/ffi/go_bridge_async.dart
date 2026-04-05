import 'dart:async';
import 'dart:isolate';

import 'go_bridge.dart';

/// Commands recognized by the background FFI worker.
enum _BridgeCommand {
  detectGPU,
  recommendBackend,
  recommendSTTAsset,
  recommendLLMAsset,
  getVersion,
  shutdown,
}

/// Request sent from main isolate → worker isolate.
class _Request {
  const _Request(this.id, this.command, {this.gpuMode});

  final int id;
  final _BridgeCommand command;
  final String? gpuMode;
}

/// Response sent from worker isolate → main isolate.
class _Response {
  const _Response(this.id, {this.value, this.error});

  final int id;
  final Object? value;
  final String? error;
}

/// Isolate-based async wrapper around [GoBridge].
///
/// Runs all FFI calls on a long-lived background isolate so the main
/// (UI) thread is never blocked by native calls. The isolate is spawned
/// lazily on the first request and reused for all subsequent calls.
///
/// Call [dispose] to terminate the isolate and release resources.
class AsyncGoBridge {
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _mainPort;
  StreamSubscription<dynamic>? _subscription;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _disposed = false;
  Completer<void>? _initLock;

  /// Whether the bridge has been disposed.
  bool get isDisposed => _disposed;

  /// Lazily spawn and connect to the background isolate.
  Future<void> _ensureIsolate() async {
    if (_disposed) {
      throw StateError('AsyncGoBridge has been disposed');
    }
    if (_workerPort != null) return;

    // Prevent duplicate init from concurrent callers.
    if (_initLock != null) {
      await _initLock!.future;
      return;
    }
    _initLock = Completer<void>();

    try {
      _mainPort = ReceivePort();
      _isolate = await Isolate.spawn(_workerEntry, _mainPort!.sendPort);

      final portCompleter = Completer<SendPort>();
      _subscription = _mainPort!.listen((message) {
        if (message is SendPort) {
          portCompleter.complete(message);
          return;
        }
        if (message is _Response) {
          final completer = _pending.remove(message.id);
          if (completer == null) return;
          if (message.error != null) {
            completer.completeError(Exception(message.error));
          } else {
            completer.complete(message.value);
          }
        }
      });

      _workerPort = await portCompleter.future;
      _initLock!.complete();
    } catch (e) {
      _initLock!.completeError(e);
      _initLock = null;
      _subscription?.cancel();
      _subscription = null;
      _mainPort?.close();
      _mainPort = null;
      rethrow;
    }
  }

  /// Send a [command] to the worker and return the typed result.
  Future<T> _send<T extends Object>(
    _BridgeCommand command, {
    String? gpuMode,
  }) async {
    await _ensureIsolate();
    if (_disposed) {
      throw StateError('AsyncGoBridge has been disposed');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _workerPort!.send(_Request(id, command, gpuMode: gpuMode));
    final result = await completer.future;
    return result as T;
  }

  // ---------------------------------------------------------------------------
  // Public API — mirrors [GoBridge] with Future-based returns.
  // ---------------------------------------------------------------------------

  /// Detect GPU hardware asynchronously.
  Future<GpuInfo> detectGPU() => _send<GpuInfo>(_BridgeCommand.detectGPU);

  /// Recommended inference backend: `cuda`, `vulkan`, or `cpu`.
  Future<String> recommendBackend() =>
      _send<String>(_BridgeCommand.recommendBackend);

  /// Recommended STT server download asset key.
  ///
  /// [gpuMode]: `auto`, `enabled`, or `disabled`.
  Future<String> recommendSTTAsset({String gpuMode = 'auto'}) =>
      _send<String>(_BridgeCommand.recommendSTTAsset, gpuMode: gpuMode);

  /// Recommended LLM server download asset key.
  ///
  /// [gpuMode]: `auto`, `enabled`, or `disabled`.
  Future<String> recommendLLMAsset({String gpuMode = 'auto'}) =>
      _send<String>(_BridgeCommand.recommendLLMAsset, gpuMode: gpuMode);

  /// Bridge version string.
  Future<String> getVersion() => _send<String>(_BridgeCommand.getVersion);

  /// Kill the background isolate and release all resources.
  ///
  /// After calling this, all pending futures complete with a [StateError]
  /// and further calls will throw.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _workerPort?.send(const _Request(-1, _BridgeCommand.shutdown));
    _subscription?.cancel();
    _subscription = null;
    _mainPort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _mainPort = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('AsyncGoBridge disposed'));
      }
    }
    _pending.clear();
  }
}

// ---------------------------------------------------------------------------
// Worker isolate — top-level so Isolate.spawn can reference it.
// ---------------------------------------------------------------------------

/// Entry point for the long-lived background isolate.
void _workerEntry(SendPort mainPort) {
  final workerPort = ReceivePort();
  mainPort.send(workerPort.sendPort);

  // Each isolate loads its own GoBridge instance (null if lib missing).
  final bridge = GoBridge.instance;

  late final StreamSubscription<dynamic> sub;
  sub = workerPort.listen((message) {
    if (message is _Request) {
      if (message.command == _BridgeCommand.shutdown) {
        sub.cancel();
        workerPort.close();
        return;
      }
      mainPort.send(_processRequest(bridge, message));
    }
  });
}

/// Execute a single FFI command and wrap the result in a [_Response].
_Response _processRequest(GoBridge? bridge, _Request request) {
  try {
    if (bridge == null) {
      return _Response(request.id, value: _fallback(request.command));
    }
    final Object value = switch (request.command) {
      _BridgeCommand.detectGPU => bridge.detectGPU(),
      _BridgeCommand.recommendBackend => bridge.recommendBackend(),
      _BridgeCommand.recommendSTTAsset =>
        bridge.recommendSTTAsset(gpuMode: request.gpuMode ?? 'auto'),
      _BridgeCommand.recommendLLMAsset =>
        bridge.recommendLLMAsset(gpuMode: request.gpuMode ?? 'auto'),
      _BridgeCommand.getVersion => bridge.getVersion(),
      _BridgeCommand.shutdown => '', // Unreachable — handled in listener.
    };
    return _Response(request.id, value: value);
  } catch (e) {
    return _Response(request.id, error: e.toString());
  }
}

/// Fallback values when [GoBridge] is unavailable (library not found).
Object _fallback(_BridgeCommand command) {
  return switch (command) {
    _BridgeCommand.detectGPU => GpuInfo.none,
    _BridgeCommand.recommendBackend => 'cpu',
    _BridgeCommand.recommendSTTAsset => '',
    _BridgeCommand.recommendLLMAsset => '',
    _BridgeCommand.getVersion => 'unknown',
    _BridgeCommand.shutdown => '', // Unreachable.
  };
}

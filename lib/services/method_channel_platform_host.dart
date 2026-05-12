import 'dart:async';

import 'package:flutter/services.dart';

/// Generic base class for native floating-surface platform controllers.
///
/// Owns the shared method-channel plumbing used by the four floating-surface
/// controllers (Windows + macOS × button + overlay):
///
/// - Disposed guard (`isDisposed`)
/// - MethodChannel registration / teardown
/// - Broadcast `StreamController<E>` for native → Dart events
/// - Standard `dispose()` sequence: guard → clear handler → 'destroy' → close
///
/// Subclasses must:
/// 1. Pass the channel name to `super(channelName)`.
/// 2. Implement [parseNativeEvent] to map each `MethodCall` to an event
///    (return `null` to silently ignore unknown calls).
/// 3. Call [invokeMethod] instead of accessing the channel directly for any
///    outgoing calls — it handles the disposed guard automatically.
///
/// Service-level state models ([FloatingButtonService],
/// [FloatingOverlayService]) are **not** affected; only the platform
/// plumbing layer is consolidated here.
abstract class MethodChannelPlatformHost<E> {
  MethodChannelPlatformHost(String channelName)
    : _channel = MethodChannel(channelName),
      _eventController = StreamController<E>.broadcast() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  final MethodChannel _channel;
  final StreamController<E> _eventController;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Stream of typed events emitted by the native side.
  Stream<E> get events => _eventController.stream;

  // ── Subclass contract ───────────────────────────────────────────────────

  /// Map a native [MethodCall] to a typed event, or return `null` to ignore.
  ///
  /// Called for every incoming method-channel call. If this returns a
  /// non-null value it is added to [events].
  E? parseNativeEvent(MethodCall call);

  // ── Platform communication ──────────────────────────────────────────────

  /// Invoke [method] on the native channel with optional [arguments].
  ///
  /// Does nothing if [isDisposed] is `true`.
  Future<void> invokeMethod(String method, [dynamic arguments]) async {
    if (_disposed) return;
    await _channel.invokeMethod<void>(method, arguments);
  }

  /// Invoke [method] and return the result as a `Map<K, V>`.
  ///
  /// Returns `null` if [isDisposed] is `true` or if the native side returns
  /// `null`.
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    dynamic arguments,
  ]) async {
    if (_disposed) return null;
    return _channel.invokeMapMethod<K, V>(method, arguments);
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Destroy the native window and release all resources.
  ///
  /// Idempotent — subsequent calls are no-ops.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('destroy');
    } on MissingPluginException {
      // Expected in test environments where no native handler is registered.
    }
    await _eventController.close();
  }

  // ── Internal ────────────────────────────────────────────────────────────

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (_disposed) return;
    final event = parseNativeEvent(call);
    if (event != null) {
      _eventController.add(event);
    }
  }
}

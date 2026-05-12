import 'dart:async';

import 'package:flutter/services.dart';

import 'floating_button_controller.dart';
import 'floating_button_events.dart';

/// macOS implementation of [FloatingButtonController].
///
/// Communicates with the Swift FloatingButtonHost via a single MethodChannel.
/// Events are received through the same channel (Swift calls invokeMethod).
class MacOSFloatingButtonController extends FloatingButtonController {
  static const _channel = MethodChannel('com.whispaste.floating_button');

  final _eventController = StreamController<FloatingButtonEvent>.broadcast();
  bool _disposed = false;

  MacOSFloatingButtonController() {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  @override
  Stream<FloatingButtonEvent> get events => _eventController.stream;

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) async {
    if (_disposed) return;
    await _channel.invokeMethod('show', {'x': x, 'y': y, 'size': size});
  }

  @override
  Future<void> hide() async {
    if (_disposed) return;
    await _channel.invokeMethod('hide');
  }

  @override
  Future<void> setState(FloatingButtonVisualState state) async {
    if (_disposed) return;
    await _channel.invokeMethod('setState', {'state': state.name});
  }

  @override
  Future<void> setTheme({required bool isDark}) async {
    if (_disposed) return;
    await _channel.invokeMethod('setTheme', {'isDark': isDark});
  }

  @override
  Future<void> setPosition(double x, double y) async {
    if (_disposed) return;
    await _channel.invokeMethod('setPosition', {'x': x, 'y': y});
  }

  @override
  Future<void> setSize(int size) async {
    if (_disposed) return;
    await _channel.invokeMethod('setSize', {'size': size});
  }

  @override
  Future<void> setOpacity(double opacity) async {
    if (_disposed) return;
    await _channel.invokeMethod('setOpacity', {'opacity': opacity});
  }

  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) async {
    if (_disposed) return;
    await _channel.invokeMethod('setContextMenuItems', {'items': items});
  }

  @override
  Future<({double x, double y})?> getPosition() async {
    if (_disposed) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getPosition',
    );
    if (result == null) return null;
    final x = (result['x'] as num?)?.toDouble();
    final y = (result['y'] as num?)?.toDouble();
    if (x == null || y == null) return null;
    return (x: x, y: y);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod('destroy');
    } on MissingPluginException {
      // Expected in test environment where no native handler is registered.
    }
    await _eventController.close();
  }

  // ── Native → Dart event handler ─────────────────────────────────────

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case 'onClicked':
        _eventController.add(const FloatingButtonClicked());
      case 'onSecondaryClicked':
        _eventController.add(const FloatingButtonSecondaryClicked());
      case 'onContextMenu':
        final args = call.arguments as Map?;
        final id = args?['id'] as String?;
        if (id != null) {
          _eventController.add(FloatingButtonContextMenuSelected(id));
        }
      case 'onDragEnded':
        final args = call.arguments as Map?;
        if (args != null) {
          final x = (args['x'] as num?)?.toDouble() ?? 0;
          final y = (args['y'] as num?)?.toDouble() ?? 0;
          _eventController.add(FloatingButtonDragEnded(x, y));
        }
    }
  }
}

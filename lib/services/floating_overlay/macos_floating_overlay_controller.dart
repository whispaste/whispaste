import 'dart:async';

import 'package:flutter/services.dart';

import 'floating_overlay_controller.dart';
import 'floating_overlay_events.dart';

/// macOS implementation of [FloatingOverlayController].
///
/// Communicates with the Swift FloatingOverlayHost via a single MethodChannel.
/// Events are received through the same channel (Swift calls invokeMethod).
class MacOSFloatingOverlayController extends FloatingOverlayController {
  static const _channel = MethodChannel('com.whispaste.floating_overlay');

  final _eventController = StreamController<FloatingOverlayEvent>.broadcast();
  bool _disposed = false;

  MacOSFloatingOverlayController() {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  @override
  Stream<FloatingOverlayEvent> get events => _eventController.stream;

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    if (_disposed) return;
    await _channel.invokeMethod('updateSnapshot', snapshot.toMap());
  }

  @override
  Future<void> setAudioLevel(double level) async {
    if (_disposed) return;
    await _channel.invokeMethod('setAudioLevel', {'level': level});
  }

  @override
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor) async {
    if (_disposed) return;
    await _channel.invokeMethod('setPosition', {
      'x': x,
      'y': y,
      'anchorMode': anchor.name,
    });
  }

  @override
  Future<void> setContextMenuItems(
    List<({String id, String label})> items,
  ) async {
    if (_disposed) return;
    await _channel.invokeMethod('setContextMenuItems', {
      'items': items
          .map((item) => {'id': item.id, 'label': item.label})
          .toList(),
    });
  }

  @override
  Future<void> setOpacity(double opacity) async {
    if (_disposed) return;
    await _channel.invokeMethod('setOpacity', {'opacity': opacity});
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
      case 'onDragEnded':
        final args = call.arguments as Map?;
        if (args != null) {
          final x = (args['x'] as num?)?.toDouble() ?? 0;
          final y = (args['y'] as num?)?.toDouble() ?? 0;
          final anchorMode = (args['anchorMode'] as String?) ?? 'topLeft';
          _eventController.add(OverlayDragEnded(x, y, anchorMode));
        }
      case 'onCloseClicked':
        _eventController.add(const OverlayCloseClicked());
      case 'onBodyClicked':
        _eventController.add(const OverlayBodyClicked());
      case 'onRetryClicked':
        _eventController.add(const OverlayRetryClicked());
      case 'onContextMenu':
        final args = call.arguments as Map?;
        final action = args?['action'] as String?;
        if (action != null) {
          _eventController.add(OverlayContextMenuAction(action));
        }
    }
  }
}

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hotkey_manager/hotkey_manager.dart';

/// A registrar that knows the system's own time of the hotkey event it is
/// delivering right now (issue #809).
abstract interface class HotKeyEventTimeSource {
  /// Native event time (monotonic boot clock) of the callback being delivered,
  /// or null outside a callback and without a stamp.
  Duration? get lastEventAt;
}

/// Carries the macOS Carbon event time to the hotkey handlers.
///
/// The native plugin sends a stamp (`type`, `identifier`, `atMs`) on its own
/// channel right before the package's event; both arrive in order. A handler
/// wrapped by [wrap] takes the matching stamp for its callback, so the gesture
/// detection sees the time of the system, not of the arrival on the UI thread
/// (same idea as the event-tap path, issue #787).
class HotKeyEventTimes implements HotKeyEventTimeSource {
  HotKeyEventTimes({MethodChannel? channel, bool? enabled})
    : _enabled = enabled ?? Platform.isMacOS,
      _channel = channel ?? const MethodChannel('whispaste/hotkey_event_time');

  final bool _enabled;
  final MethodChannel _channel;
  bool _listening = false;
  ({String type, String identifier, Duration at})? _pending;
  Duration? _current;

  @override
  Duration? get lastEventAt => _current;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'stamp') return;
    _pending = parseStamp(call.arguments);
  }

  /// The stamp a native `stamp` call carries, or null if malformed.
  @visibleForTesting
  static ({String type, String identifier, Duration at})? parseStamp(
    Object? arguments,
  ) {
    if (arguments is! Map) return null;
    final type = arguments['type'];
    final identifier = arguments['identifier'];
    final ms = arguments['atMs'];
    if (type is! String || identifier is! String || ms is! int || ms < 0) {
      return null;
    }
    return (type: type, identifier: identifier, at: Duration(milliseconds: ms));
  }

  /// Wraps [handler] so [lastEventAt] holds the event's stamp during the call.
  /// [type] is `onKeyDown` or `onKeyUp`.
  HotKeyHandler? wrap(String type, HotKeyHandler? handler) {
    if (handler == null || !_enabled) return handler;
    // Listens from the first registration on, not at construction: the
    // channel needs the binding, which a bare service in a test lacks.
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_onCall);
    }
    return (HotKey hotKey) {
      final p = _pending;
      _pending = null;
      _current =
          p != null && p.type == type && p.identifier == hotKey.identifier
          ? p.at
          : null;
      try {
        handler(hotKey);
      } finally {
        _current = null;
      }
    };
  }
}

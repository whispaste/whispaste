/// Keep-alive heartbeat for secondary floating windows.
///
/// Secondary windows (floating button, floating overlay) run in separate
/// Flutter engines. If the main window is closed, crashes, or hot-reloads,
/// these windows become orphaned. This mixin provides a periodic heartbeat
/// that pings the main window via the command channel. After [maxFailures]
/// consecutive failures the window self-terminates.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'multi_window_types.dart';

/// Mixin that adds heartbeat monitoring to a secondary window's [State].
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<_MyScreen> with WindowHeartbeat {
///   @override
///   void initState() {
///     super.initState();
///     startHeartbeat();
///   }
/// }
/// ```
mixin WindowHeartbeat {
  Timer? _heartbeatTimer;
  int _consecutiveFailures = 0;

  /// Ping interval — how often we check if the main window is alive.
  static const _interval = Duration(seconds: 3);

  /// Number of consecutive failures before self-terminating.
  /// 3 failures × 3s = 9s grace period (covers hot reload which takes ~1-3s).
  static const maxFailures = 3;

  /// Starts the periodic heartbeat. Call from [initState].
  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    _consecutiveFailures = 0;
    _heartbeatTimer = Timer.periodic(_interval, (_) => _ping());
  }

  /// Stops the heartbeat. Called automatically on self-terminate,
  /// but can also be called from [dispose].
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _ping() async {
    try {
      await commandChannel.invokeMethod('ping');
      // Success — reset failure counter.
      _consecutiveFailures = 0;
    } catch (e) {
      _consecutiveFailures++;
      debugPrint('Heartbeat: ping failed ($_consecutiveFailures/$maxFailures)');
      if (_consecutiveFailures >= maxFailures) {
        debugPrint('Heartbeat: main window unresponsive — self-terminating');
        stopHeartbeat();
        // Hard exit — the secondary window has no parent to report to.
        exit(0);
      }
    }
  }
}

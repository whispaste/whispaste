/// Keep-alive heartbeat for secondary floating windows.
///
/// Secondary windows (floating button, floating overlay) run in separate
/// Flutter engines within the **same OS process**. If the main window is
/// closed, crashes, or hot-reloads, these windows become orphaned. This
/// mixin provides a periodic heartbeat that pings the main window via
/// the command channel. After [maxFailures] consecutive failures the
/// window hides itself and goes inert.
///
/// **IMPORTANT**: We do NOT call `exit(0)` because that would terminate the
/// entire process, killing the main window too.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

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

  /// Number of consecutive failures before self-hiding.
  /// 10 failures × 3s = 30s grace period — covers hot reload and slow startup.
  static const maxFailures = 10;

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
        debugPrint('Heartbeat: main window unresponsive — hiding window');
        stopHeartbeat();
        // Hide instead of exit(0) — all windows share one OS process.
        try {
          await windowManager.hide();
        } catch (_) {}
      }
    }
  }
}

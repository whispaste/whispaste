/// Idle-shutdown timer for the whisper-server keep-alive pool.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

/// Manages a single countdown timer that fires [onElapse] after [timeout].
///
/// - [start] arms (or re-arms) the timer.
/// - [reset] re-arms to the same duration from scratch.
/// - [cancel] disarms without firing.
///
/// All methods are idempotent; calling [cancel] when no timer is running is a
/// no-op. This class has no Riverpod dependencies and is fully testable with
/// fake timers.
class SttIdleTimer {
  Timer? _timer;
  Duration? _lastTimeout;
  VoidCallback? _lastCallback;

  /// Arms the timer. If a timer is already running it is cancelled first.
  void start(Duration timeout, VoidCallback onElapse) {
    _timer?.cancel();
    _lastTimeout = timeout;
    _lastCallback = onElapse;
    _timer = Timer(timeout, () {
      _timer = null;
      onElapse();
    });
  }

  /// Re-arms the timer using the duration and callback from the last [start].
  ///
  /// No-op if [start] has never been called.
  void reset() {
    if (_lastTimeout == null || _lastCallback == null) return;
    start(_lastTimeout!, _lastCallback!);
  }

  /// Cancels the timer without firing the callback.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Whether the timer is currently counting down.
  bool get isActive => _timer?.isActive ?? false;
}

/// Decouples hotkey events from recording mode (Toggle vs Push-to-Talk).
///
/// In Push-to-Talk mode (pushToTalkEnabled + supportsKeyUp):
///   - keyDown → startRecording
///   - keyUp   → stopRecording  (only if held ≥ 100 ms; anti-glitch)
///
/// Otherwise (toggle mode or platform without keyUp support):
///   - keyDown → toggleRecording
///   - keyUp   → no-op
library;

import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/logging/app_logger.dart';

/// Handles hotkey keyDown / keyUp events and dispatches the appropriate
/// recording action based on the current mode.
class RecordingTriggerHandler {
  RecordingTriggerHandler({
    required this._startRecording,
    required this._stopRecording,
    required this._toggleRecording,
    required this._pushToTalkEnabled,
    required this._registrarSupportsKeyUp,
  });

  static final _log = AppLogger('RecordingTriggerHandler');

  /// Minimum hold duration for Push-to-Talk to trigger a stop on keyUp.
  static const _minHoldMs = 100;

  final Future<void> Function() _startRecording;
  final Future<void> Function() _stopRecording;
  final Future<void> Function() _toggleRecording;
  final bool Function() _pushToTalkEnabled;
  final bool Function() _registrarSupportsKeyUp;

  DateTime? _keyDownAt;

  /// Whether a Sentry breadcrumb for the first keyUp PTT event has been sent
  /// this session. Avoids emitting one breadcrumb per press.
  bool _keyUpBreadcrumbSent = false;

  /// Called when the global hotkey is pressed (key-down).
  void onKeyDown() {
    if (_pushToTalkEnabled() && _registrarSupportsKeyUp()) {
      _log.debug('PTT keyDown → startRecording');
      _keyDownAt = DateTime.now();
      _startRecording();
    } else {
      _log.debug('Toggle keyDown → toggleRecording');
      _keyDownAt = null;
      _toggleRecording();
    }
  }

  /// Called when the global hotkey is released (key-up).
  ///
  /// Only relevant in Push-to-Talk mode; ignored otherwise.
  void onKeyUp() {
    if (!_pushToTalkEnabled() || !_registrarSupportsKeyUp()) {
      return; // toggle mode — keyUp is a no-op
    }

    final pressedAt = _keyDownAt;
    _keyDownAt = null;

    if (pressedAt == null) return;

    final heldMs = DateTime.now().difference(pressedAt).inMilliseconds;
    if (heldMs < _minHoldMs) {
      _log.debug(
        'PTT keyUp ignored — held only ${heldMs}ms (< $_minHoldMs ms)',
      );
      return;
    }

    _log.debug('PTT keyUp → stopRecording (held ${heldMs}ms)');

    if (!_keyUpBreadcrumbSent) {
      _keyUpBreadcrumbSent = true;
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'push_to_talk_key_up_first',
          level: SentryLevel.info,
          // No PII — held duration only.
          data: {'held_ms': heldMs},
        ),
      );
    }

    _stopRecording();
  }
}

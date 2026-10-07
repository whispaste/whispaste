/// Decouples hotkey events from recording mode (Toggle vs Push-to-Talk).
///
/// In Push-to-Talk mode (pushToTalkEnabled + supportsKeyUp):
///   - keyDown → startRecording
///   - keyUp   → stopRecording  (only if held ≥ 100 ms; anti-glitch)
///
/// In Hold-or-Tap mode (pushToTalkEnabled + holdOrTapEnabled + supportsKeyUp):
///   - keyDown → toggleRecording (a short tap behaves exactly like Toggle)
///   - keyUp   → stopRecording, but only if this press started the recording
///               and the key was held ≥ [RecordingTriggerHandler.holdOrTapThreshold]
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
    bool Function()? holdOrTapEnabled,
    bool Function()? isRecording,
    DateTime Function()? clock,
  }) : _holdOrTapEnabled = holdOrTapEnabled ?? _never,
       _isRecording = isRecording ?? _never,
       _clock = clock ?? DateTime.now;

  static bool _never() => false;

  static final _log = AppLogger('RecordingTriggerHandler');

  /// Minimum hold duration for Push-to-Talk to trigger a stop on keyUp.
  static const _minHoldMs = 100;

  /// Hold-or-Tap: a press released before this duration is a tap (latches
  /// the recording like Toggle); held at least this long it is push-to-talk
  /// (release stops). Mirrors Handy's `HoldOrToggle` threshold.
  static const holdOrTapThreshold = Duration(milliseconds: 300);

  /// Hold-or-Tap: a key-down arriving while the key is still considered held
  /// is OS auto-repeat — unless the previous key-down is older than this, in
  /// which case the key-up was lost and the press is genuine. Same value as
  /// `HotkeyService._autoRepeatWindow`; this guard is defense in depth.
  static const _holdOrTapRepeatWindow = Duration(milliseconds: 1200);

  final Future<void> Function() _startRecording;
  final Future<void> Function() _stopRecording;
  final Future<void> Function() _toggleRecording;
  final bool Function() _pushToTalkEnabled;
  final bool Function() _registrarSupportsKeyUp;
  final bool Function() _holdOrTapEnabled;
  final bool Function() _isRecording;
  final DateTime Function() _clock;

  DateTime? _keyDownAt;

  /// Hold-or-Tap press state: whether the key is currently held, when the
  /// last key-down event (accepted or repeat) arrived, and whether the
  /// current press started the recording (only then may release stop it).
  bool _hybridKeyHeld = false;
  DateTime? _hybridLastKeyDownAt;
  bool _hybridPressStarted = false;

  bool get _holdOrTapActive =>
      _pushToTalkEnabled() && _holdOrTapEnabled() && _registrarSupportsKeyUp();

  /// Whether a Sentry breadcrumb for the first keyUp PTT event has been sent
  /// this session. Avoids emitting one breadcrumb per press.
  bool _keyUpBreadcrumbSent = false;

  /// Called when the global hotkey is pressed (key-down).
  void onKeyDown() {
    if (_holdOrTapActive) {
      _onHybridKeyDown();
      return;
    }
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
    if (_holdOrTapActive) {
      _onHybridKeyUp();
      return;
    }
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

  void _onHybridKeyDown() {
    final now = _clock();
    final last = _hybridLastKeyDownAt;
    _hybridLastKeyDownAt = now;
    if (_hybridKeyHeld &&
        last != null &&
        now.difference(last) < _holdOrTapRepeatWindow) {
      return; // OS auto-repeat of the press already being handled
    }
    _hybridKeyHeld = true;
    _keyDownAt = now;
    // Decide before toggling: a press that starts a recording may end it
    // on release (hold); a press that stops one never restarts it.
    _hybridPressStarted = !_isRecording();
    _log.debug('Hold-or-tap keyDown → toggleRecording');
    _toggleRecording();
  }

  void _onHybridKeyUp() {
    if (!_hybridKeyHeld) return;
    _hybridKeyHeld = false;
    final pressedAt = _keyDownAt;
    _keyDownAt = null;
    if (!_hybridPressStarted || pressedAt == null) return;
    _hybridPressStarted = false;

    final held = _clock().difference(pressedAt);
    if (held < holdOrTapThreshold) {
      _log.debug('Hold-or-tap: tap (${held.inMilliseconds}ms) → latched');
      return;
    }
    // Guard against a press the orchestrator ignored (e.g. still
    // transcribing) — there is nothing to stop then.
    if (!_isRecording()) return;
    _log.debug('Hold-or-tap: hold (${held.inMilliseconds}ms) → stop');
    _stopRecording();
  }
}

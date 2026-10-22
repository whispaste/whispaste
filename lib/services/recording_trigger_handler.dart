/// Decouples hotkey events from recording mode (Toggle vs Push-to-Talk).
///
/// In Push-to-Talk mode (pushToTalkEnabled + supportsKeyUp):
///   - keyDown → startRecording
///   - keyUp   → stopRecording  (only if held ≥ 100 ms; anti-glitch)
///
/// In Hold-or-Tap mode (pushToTalkEnabled + holdOrTapEnabled + supportsKeyUp):
///   - keyDown → toggleRecording (a short tap behaves exactly like Toggle)
///   - keyUp   → stopRecording, but only if this press started the recording
///               and the key was held ≥ the configured threshold (settings, default 250 ms)
///
/// Otherwise (toggle mode or platform without keyUp support):
///   - keyDown → toggleRecording
///   - keyUp   → no-op
library;

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/logging/app_logger.dart';
import 'hotkey_gesture_machine.dart';

/// Handles hotkey keyDown / keyUp events and dispatches the appropriate
/// recording action based on the current mode.
class RecordingTriggerHandler {
  RecordingTriggerHandler({
    required this._startRecording,
    required this._stopRecording,
    required this._toggleRecording,
    Future<void> Function()? cancelRecording,
    required this._pushToTalkEnabled,
    required this._registrarSupportsKeyUp,
    bool Function()? holdOrTapEnabled,
    int Function()? holdOrTapThresholdMs,
    bool Function()? doubleTapEnabled,
    bool Function()? doubleTapLatches,
    Future<void> Function()? onDoubleTap,
    bool Function()? isRecording,
    DateTime Function()? clock,
  }) : _holdOrTapEnabled = holdOrTapEnabled ?? _never,
       _cancelRecording = cancelRecording ?? _noop,
       _doubleTapEnabled = doubleTapEnabled ?? _never,
       _doubleTapLatches = doubleTapLatches ?? _never,
       _onDoubleTap = onDoubleTap ?? _noop,
       _holdOrTapThresholdMs = holdOrTapThresholdMs ?? _defaultThresholdMs,
       _isRecording = isRecording ?? _never,
       _clock = clock ?? DateTime.now;

  static bool _never() => false;

  static Future<void> _noop() async {}

  static int _defaultThresholdMs() => defaultHoldOrTapThresholdMs;

  static final _log = AppLogger('RecordingTriggerHandler');

  /// Minimum hold duration for Push-to-Talk to trigger a stop on keyUp.
  static const _minHoldMs = 100;

  /// Hold-or-Tap: a press released before this duration is a tap (latches
  /// the recording like Toggle); held at least this long it is push-to-talk
  /// (release stops). Hold-or-Tap always runs on one shared hotkey (toggle and
  /// push-to-talk are not separate keys in this mode), so the threshold is
  /// generous enough for slower presses. Hold-or-Tap has no double-tap path,
  /// so this window never overlaps [_doubleTapWindow].
  /// Default hold-or-tap threshold in ms (settings default: 250 ms).
  static const defaultHoldOrTapThresholdMs = 250;

  static const holdOrTapThreshold = Duration(
    milliseconds: defaultHoldOrTapThresholdMs,
  );

  /// Push-to-talk double tap: two taps (presses shorter than [_minHoldMs])
  /// within this window latch the recording hands-free.
  static const _doubleTapWindow = Duration(milliseconds: 400);

  final Future<void> Function() _startRecording;
  final Future<void> Function() _stopRecording;
  final Future<void> Function() _toggleRecording;
  final Future<void> Function() _cancelRecording;
  final bool Function() _pushToTalkEnabled;
  final bool Function() _registrarSupportsKeyUp;
  final bool Function() _holdOrTapEnabled;
  final bool Function() _doubleTapEnabled;
  final bool Function() _doubleTapLatches;
  final Future<void> Function() _onDoubleTap;
  final int Function() _holdOrTapThresholdMs;
  final bool Function() _isRecording;
  final DateTime Function() _clock;

  DateTime? _keyDownAt;

  /// Double-tap latch: when the last quick tap was released, and whether the
  /// recording is latched hands-free (release no longer stops it).
  DateTime? _lastQuickTapReleaseAt;
  bool _latched = false;

  /// Hold-or-Tap press state lives in [HotkeyGestureMachine] (gesture
  /// `auto`), rebuilt when the configured threshold changes.
  HotkeyGestureMachine? _hybridMachine;
  int _hybridMachineThresholdMs = -1;

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
      final now = _clock();
      if (_latched) {
        _latched = false;
        _keyDownAt = null;
        _log.debug('PTT keyDown while latched → stopRecording');
        _stopRecording();
        return;
      }
      if (_doubleTapEnabled() && _isDoubleTap(now)) {
        _lastQuickTapReleaseAt = null;
        _keyDownAt = null;
        if (_doubleTapLatches()) {
          _latched = true;
          _log.debug('PTT double tap → latched hands-free');
          return;
        }
        _log.debug('PTT double tap → discard first tap, run action');
        unawaited(_cancelRecording());
        unawaited(_onDoubleTap());
        return;
      }
      _log.debug('PTT keyDown → startRecording');
      _keyDownAt = now;
      _startRecording();
    } else if (_doubleTapEnabled()) {
      // Double tap only: the key has no tap of its own, so the first press
      // starts nothing and the second press within the window runs the action.
      final now = _clock();
      final lastRelease = _lastQuickTapReleaseAt;
      _keyDownAt = now;
      if (lastRelease != null &&
          now.difference(lastRelease) < _doubleTapWindow) {
        _lastQuickTapReleaseAt = null;
        _keyDownAt = null;
        if (_doubleTapLatches()) {
          _log.debug('Double tap only → hands-free recording');
          unawaited(_startRecording());
        } else {
          _log.debug('Double tap only → action');
          unawaited(_onDoubleTap());
        }
      }
    } else {
      _log.debug('Toggle keyDown → toggleRecording');
      _keyDownAt = null;
      _toggleRecording();
    }
  }

  /// A different key was pressed while the hotkey is held. For a modifier-only
  /// hotkey this makes the press no gesture (⌘+C stays ⌘+C): a recording the
  /// press started is cancelled, and the release that follows does nothing.
  void onOtherKey() {
    if (_holdOrTapActive) {
      _hybrid().otherKey(_clock());
      return;
    }
    if (!_pushToTalkEnabled() || !_registrarSupportsKeyUp()) return;
    if (_latched || _keyDownAt == null) return;
    _keyDownAt = null;
    _log.debug('PTT other key during press → cancelRecording');
    _cancelRecording();
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
      if (_doubleTapEnabled()) {
        // Double tap only: remember a quick tap so the next press can pair.
        final pressedAt = _keyDownAt;
        _keyDownAt = null;
        final releasedAt = _clock();
        _lastQuickTapReleaseAt =
            pressedAt != null &&
                releasedAt.difference(pressedAt).inMilliseconds < _minHoldMs
            ? releasedAt
            : null;
      }
      return; // toggle mode — keyUp is otherwise a no-op
    }

    if (_latched) return; // hands-free: releasing changes nothing

    final pressedAt = _keyDownAt;
    _keyDownAt = null;

    if (pressedAt == null) return;

    final releasedAt = _clock();
    final heldMs = releasedAt.difference(pressedAt).inMilliseconds;
    if (heldMs < _minHoldMs) {
      _log.debug(
        'PTT keyUp ignored — held only ${heldMs}ms (< $_minHoldMs ms)',
      );
      _lastQuickTapReleaseAt = releasedAt;
      return;
    }
    _lastQuickTapReleaseAt = null;

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

  /// Whether a press at [now] completes a double tap: the previous press was
  /// a quick tap released within [_doubleTapWindow], and a recording is
  /// running to latch.
  bool _isDoubleTap(DateTime now) {
    final lastRelease = _lastQuickTapReleaseAt;
    return lastRelease != null &&
        now.difference(lastRelease) < _doubleTapWindow &&
        _isRecording();
  }

  HotkeyGestureMachine _hybrid() {
    final ms = _holdOrTapThresholdMs();
    final current = _hybridMachine;
    if (current != null && ms == _hybridMachineThresholdMs) return current;
    _hybridMachineThresholdMs = ms;
    return _hybridMachine = HotkeyGestureMachine(
      gesture: HotkeyGesture.auto,
      holdThreshold: Duration(milliseconds: ms),
      onOutput: _onHybridOutput,
    );
  }

  void _onHybridKeyDown() {
    _hybrid().down(_clock(), isRecording: _isRecording());
  }

  void _onHybridKeyUp() {
    _hybrid().up(_clock());
  }

  void _onHybridOutput(GestureOutput output) {
    switch (output) {
      case GestureOutput.toggle:
        _log.debug('Hold-or-tap keyDown → toggleRecording');
        _toggleRecording();
      case GestureOutput.stop:
        // Guard against a press the orchestrator ignored (e.g. still
        // transcribing) — there is nothing to stop then.
        if (!_isRecording()) return;
        _log.debug('Hold-or-tap: hold → stop');
        _stopRecording();
      case GestureOutput.abort:
        _log.debug('Hold-or-tap: another key during press → cancelRecording');
        _cancelRecording();
      case GestureOutput.doubleTap:
        if (_doubleTapLatches()) {
          unawaited(_startRecording());
        } else {
          unawaited(_onDoubleTap());
        }
      case GestureOutput.start:
        // Not produced by the `auto` gesture on the Hold-or-Tap path.
        break;
    }
  }
}

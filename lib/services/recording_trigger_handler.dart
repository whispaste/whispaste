/// Decouples hotkey events from recording actions.
///
/// Every gesture is decided by [HotkeyGestureMachine], the single rule source.
/// This handler only maps the configured settings to one gesture and carries
/// out the machine's outputs:
///
///   - hold-or-tap on a key that reports key-up: `auto` (short press latches,
///     hold of at least the threshold is push-to-talk)
///   - push-to-talk on a key that reports key-up: `hold` (every release stops
///     the press's own recording); with double tap, `hold` + double tap
///   - double tap without push-to-talk: `doubleTap` (a double tap starts
///     hands-free, a single tap stops it)
///   - otherwise: `tap` (each press toggles)
///
/// Ownership: a press only stops a recording it started itself. A rejected or
/// foreign recording is never stopped by a release.
library;

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/logging/app_logger.dart';
import 'hotkey_gesture_machine.dart';

/// Handles hotkey keyDown / keyUp events and dispatches the recording actions
/// the gesture machine decides on.
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
  }) : _cancelRecording = cancelRecording ?? _noop,
       _holdOrTapEnabled = holdOrTapEnabled ?? _never,
       _holdOrTapThresholdMs = holdOrTapThresholdMs ?? _defaultThresholdMs,
       _doubleTapEnabled = doubleTapEnabled ?? _never,
       _doubleTapLatches = doubleTapLatches ?? _never,
       _onDoubleTap = onDoubleTap ?? _noop,
       _isRecording = isRecording ?? _never,
       _clock = clock ?? DateTime.now;

  static bool _never() => false;

  static Future<void> _noop() async {}

  static int _defaultThresholdMs() => defaultHoldOrTapThresholdMs;

  static final _log = AppLogger('RecordingTriggerHandler');

  /// Hold-with-double-tap and double-tap-only: a press shorter than this is a
  /// tap of a possible pair; a longer press is no tap.
  static const _minHoldMs = 100;

  /// Default hold-or-tap threshold in ms (settings default: 250 ms).
  static const defaultHoldOrTapThresholdMs = 250;

  static const holdOrTapThreshold = Duration(
    milliseconds: defaultHoldOrTapThresholdMs,
  );

  final Future<void> Function() _startRecording;
  final Future<void> Function() _stopRecording;
  final Future<void> Function() _toggleRecording;
  final Future<void> Function() _cancelRecording;
  final bool Function() _pushToTalkEnabled;
  final bool Function() _registrarSupportsKeyUp;
  final bool Function() _holdOrTapEnabled;
  final int Function() _holdOrTapThresholdMs;
  final bool Function() _doubleTapEnabled;
  final bool Function() _doubleTapLatches;
  final Future<void> Function() _onDoubleTap;
  final bool Function() _isRecording;
  final DateTime Function() _clock;

  /// One machine per gesture shape, reused across presses.
  final Map<String, HotkeyGestureMachine> _machines = {};

  /// Machine of the press whose key-up is still awaited.
  HotkeyGestureMachine? _activeMachine;

  /// Press start time, for the Sentry breadcrumb of the first push-to-talk
  /// release.
  DateTime? _pressDownAt;
  int _lastHeldMs = 0;
  bool _keyUpBreadcrumbSent = false;

  /// This handler's recording is the one running (only such a recording may
  /// be stopped by a release).
  bool _owned = false;

  /// Own start or toggle is still in progress (slow pre-check).
  bool _ownPending = false;

  /// A release that arrived during [_ownPending] and waits for it to finish.
  _PendingRelease _pendingRelease = _PendingRelease.none;

  /// Latched hands-free recording (release no longer stops it).
  bool _latched = false;

  /// Cancellation of the recording discarded by the first tap of a pair. The
  /// double-tap action waits for it (no race).
  Future<void>? _cancelInFlight;

  /// Called when the global hotkey is pressed (key-down).
  void onKeyDown() {
    final now = _clock();
    _forgetEndedRecording();
    _pressDownAt ??= now;

    final keyUpObservable = _registrarSupportsKeyUp();
    final machine = _select(
      pushToTalk: _pushToTalkEnabled() && keyUpObservable,
      keyUpObservable: keyUpObservable,
    );
    machine.down(now, isRecording: _isRecording());
    if (keyUpObservable) {
      _activeMachine = machine;
    } else {
      // Without key-up the press is over at once; a double tap then pairs by
      // press-to-press timing.
      machine.up(now);
    }
  }

  /// A different key was pressed while the hotkey is held. For a modifier-only
  /// hotkey this makes the press no gesture (⌘+C stays ⌘+C): a recording the
  /// press started is cancelled, and the release that follows does nothing.
  void onOtherKey() {
    final machine = _activeMachine;
    if (machine == null) return;
    if (machine.gesture != HotkeyGesture.hold &&
        machine.gesture != HotkeyGesture.auto) {
      return;
    }
    machine.otherKey(_clock());
  }

  /// Called when the global hotkey is released (key-up).
  void onKeyUp() {
    final now = _clock();
    final machine = _activeMachine;
    _activeMachine = null;
    final pressedAt = _pressDownAt;
    _pressDownAt = null;
    _lastHeldMs = pressedAt == null
        ? 0
        : now.difference(pressedAt).inMilliseconds;
    machine?.up(now);
  }

  /// Picks the gesture of the configured settings and returns its machine
  /// with the current threshold applied.
  HotkeyGestureMachine _select({
    required bool pushToTalk,
    required bool keyUpObservable,
  }) {
    if (pushToTalk && _holdOrTapEnabled()) {
      return _machine(HotkeyGesture.auto, doubleTap: false)
        ..holdThreshold = Duration(milliseconds: _holdOrTapThresholdMs());
    }
    if (pushToTalk) {
      return _machine(HotkeyGesture.hold, doubleTap: _doubleTapEnabled())
        ..holdThreshold = const Duration(milliseconds: _minHoldMs);
    }
    if (_doubleTapEnabled()) {
      return _machine(HotkeyGesture.doubleTap, doubleTap: false)
        ..holdThreshold = const Duration(milliseconds: _minHoldMs);
    }
    return _machine(HotkeyGesture.tap, doubleTap: false);
  }

  HotkeyGestureMachine _machine(
    HotkeyGesture gesture, {
    required bool doubleTap,
  }) {
    final key = '${gesture.name}-$doubleTap';
    return _machines.putIfAbsent(
      key,
      () => HotkeyGestureMachine(
        gesture: gesture,
        doubleTapEnabled: doubleTap,
        onOutput: (output) => _dispatch(output, gesture),
      ),
    );
  }

  void _dispatch(GestureOutput output, HotkeyGesture gesture) {
    switch (output) {
      case GestureOutput.start:
        unawaited(_start());
      case GestureOutput.toggle:
        unawaited(_toggle());
      case GestureOutput.stop:
        _sendBreadcrumbOnce(gesture);
        _release(_PendingRelease.stop);
      case GestureOutput.abort:
        _release(_PendingRelease.abort);
      case GestureOutput.doubleTap:
        unawaited(_doubleTapAction());
    }
  }

  /// Hold press: start, or stop a latched recording.
  Future<void> _start() async {
    if (_latched && _isRecording()) {
      _latched = false;
      _owned = false;
      _log.debug('Hold while latched → stopRecording');
      await _stopRecording();
      return;
    }
    _latched = false;
    _log.debug('Hold → startRecording');
    await _ownStart(_startRecording);
  }

  /// Tap press: toggle. A toggle while a recording runs stops it.
  Future<void> _toggle() async {
    if (_isRecording()) {
      _owned = false;
      _latched = false;
      _log.debug('Toggle while recording → stopRecording');
      await _toggleRecording();
      return;
    }
    _latched = false;
    _log.debug('Toggle → toggleRecording');
    await _ownStart(_toggleRecording);
  }

  /// Double tap: action, or a hands-free start.
  Future<void> _doubleTapAction() async {
    final cancel = _cancelInFlight;
    _cancelInFlight = null;
    if (cancel != null) await cancel;
    if (_doubleTapLatches()) {
      _log.debug('Double tap → hands-free recording');
      await _ownStart(_startRecording);
      _latched = _owned;
      return;
    }
    _log.debug('Double tap → action');
    await _onDoubleTap();
  }

  /// Runs a start or toggle that begins a recording and records whether this
  /// handler owns the result. A start that is refused stays unowned.
  Future<void> _ownStart(Future<void> Function() begin) async {
    if (_isRecording()) {
      // A recording is already running: the press does not own it.
      _owned = false;
      await begin();
      return;
    }
    final run = begin();
    if (_isRecording()) {
      _owned = true;
      await run;
      return;
    }
    _ownPending = true;
    _owned = false;
    await run;
    _ownPending = false;
    _owned = _isRecording();
    await _settlePendingRelease();
  }

  /// Applies a release that arrived while the own start was still running.
  Future<void> _settlePendingRelease() async {
    final pending = _pendingRelease;
    _pendingRelease = _PendingRelease.none;
    if (pending == _PendingRelease.none || !_owned || !_isRecording()) {
      _owned = false;
      return;
    }
    switch (pending) {
      case _PendingRelease.stop:
        await _stopOwned();
      case _PendingRelease.abort:
        _abortOwned();
      case _PendingRelease.none:
        break;
    }
  }

  /// A release: stop or discard the recording this press started. Foreign or
  /// refused recordings are never touched.
  void _release(_PendingRelease kind) {
    if (_ownPending) {
      _pendingRelease = kind;
      return;
    }
    if (!_owned) return;
    if (kind == _PendingRelease.stop) {
      unawaited(_stopOwned());
    } else {
      _abortOwned();
    }
  }

  Future<void> _stopOwned() async {
    _owned = false;
    _latched = false;
    if (!_isRecording()) return; // guard: nothing to stop
    _log.debug('Release → stopRecording');
    await _stopRecording();
  }

  void _abortOwned() {
    _owned = false;
    _latched = false;
    _log.debug('Release (short first tap) → cancelRecording');
    _cancelInFlight = _cancelRecording();
  }

  /// Forgets latch and ownership once the recording ended elsewhere.
  void _forgetEndedRecording() {
    if (_ownPending || _isRecording()) return;
    _latched = false;
    _owned = false;
  }

  void _sendBreadcrumbOnce(HotkeyGesture gesture) {
    if (gesture != HotkeyGesture.hold || _keyUpBreadcrumbSent) return;
    _keyUpBreadcrumbSent = true;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'push_to_talk_key_up_first',
        level: SentryLevel.info,
        // No PII — held duration only.
        data: {'held_ms': _lastHeldMs},
      ),
    );
  }
}

/// Release that is still waiting for the own start to finish.
enum _PendingRelease { none, stop, abort }

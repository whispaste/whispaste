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
///   - a single key with double tap but without push-to-talk: `doubleTap` (a
///     double tap starts hands-free, a single tap stops it), so a stray tap of
///     the key never starts a recording
///   - otherwise: `tap` (each press toggles; a combination in toggle mode
///     ignores the double-tap setting)
///
/// The same rules hold for a combination and for a single key: a single key
/// holds to dictate and double-taps to go hands-free (maintainer decision
/// 2026-10-30). A single key that is also used for typing and shortcuts
/// (left keys, Shift) starts after [holdStartDelay] instead of on key-down,
/// so ⌘C or a capital letter never flashes a recording.
///
/// Ownership: a press only stops a recording it started itself. A rejected or
/// foreign recording is never stopped by a release.
library;

import 'dart:async';

import 'package:clock/clock.dart' as wall;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/logging/app_logger.dart';
import 'hotkey_gesture_machine.dart';

/// Hold-with-double-tap and double-tap-only: a press shorter than this is a
/// tap of a possible pair; a longer press is no tap.
const _minHoldMs = 100;

/// Longest press that still counts as a tap (not a hold) on a key with a
/// double tap; the recording's start tone waits this long (#329).
const kShortTapMaxDuration = Duration(milliseconds: _minHoldMs);

/// The gesture the settings select for the dictation trigger, see the
/// library doc. [pushToTalk] is the hold mode in effect (key-up observable).
/// Shared with the onboarding key test, so the test judges a press exactly as
/// the recording does.
({HotkeyGesture gesture, bool doubleTap, Duration holdThreshold})
selectHotkeyGesture({
  required bool pushToTalk,
  required bool holdOrTap,
  required int holdOrTapThresholdMs,
  required bool doubleTap,
  required bool singleKey,
}) {
  const minHold = Duration(milliseconds: _minHoldMs);
  // A single key with its double tap never runs as tap-or-hold: hold plus
  // double tap (or the double tap alone) is what Settings shows (#1104).
  if (pushToTalk && holdOrTap && !(singleKey && doubleTap)) {
    return (
      gesture: HotkeyGesture.auto,
      doubleTap: false,
      holdThreshold: Duration(milliseconds: holdOrTapThresholdMs),
    );
  }
  if (pushToTalk) {
    return (
      gesture: HotkeyGesture.hold,
      doubleTap: doubleTap,
      holdThreshold: minHold,
    );
  }
  if (singleKey && doubleTap) {
    return (
      gesture: HotkeyGesture.doubleTap,
      doubleTap: false,
      holdThreshold: minHold,
    );
  }
  return (gesture: HotkeyGesture.tap, doubleTap: false, holdThreshold: minHold);
}

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
    bool Function()? singleKey,
    Duration Function()? holdStartDelay,
    Future<void> Function()? onDoubleTap,
    bool Function()? isRecording,
    String? Function()? recordingSessionId,
    this._onHandsFreeChanged,
    DateTime Function()? clock,
    Duration? Function()? nativeEventAt,
    Duration? Function()? nativePressed,
  }) : _nativeEventAt = nativeEventAt ?? _noStamp,
       _nativePressed = nativePressed ?? _noStamp,
       _cancelRecording = cancelRecording ?? _noop,
       _holdOrTapEnabled = holdOrTapEnabled ?? _never,
       _holdOrTapThresholdMs = holdOrTapThresholdMs ?? _defaultThresholdMs,
       _doubleTapEnabled = doubleTapEnabled ?? _never,
       _doubleTapLatches = doubleTapLatches ?? _never,
       _singleKey = singleKey ?? _never,
       _holdStartDelay = holdStartDelay ?? _noDelay,
       _onDoubleTap = onDoubleTap ?? _noop,
       _isRecording = isRecording ?? _never,
       _recordingSessionId = recordingSessionId ?? _noSession,
       _sessionWired = recordingSessionId != null,
       _clock = clock ?? _wallNow;

  /// The wall clock through `package:clock`: the real time in the app, the
  /// controlled time of a widget test (#1491).
  static DateTime _wallNow() => wall.clock.now();

  static bool _never() => false;

  static Duration? _noStamp() => null;

  static String? _noSession() => null;

  static Duration _noDelay() => Duration.zero;

  static Future<void> _noop() async {}

  static int _defaultThresholdMs() => defaultHoldOrTapThresholdMs;

  static final _log = AppLogger('RecordingTriggerHandler');

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

  /// Whether the trigger is one single key rather than a combination.
  final bool Function() _singleKey;

  /// How long a press must stay alone before it starts a recording. Zero
  /// starts on key-down (combinations, right keys, Fn).
  final Duration Function() _holdStartDelay;
  final Future<void> Function() _onDoubleTap;
  final bool Function() _isRecording;
  final String? Function() _recordingSessionId;

  /// Whether the caller reports recording sessions. Without it a release
  /// keeps its plain behaviour (no session identity to check against).
  final bool _sessionWired;
  final DateTime Function() _clock;

  /// Native event time and press length of the event being delivered (null
  /// without a stamp, e.g. the Wayland portal or an OS registrar).
  final Duration? Function() _nativeEventAt;
  final Duration? Function() _nativePressed;

  /// Smallest arrival-minus-native-time seen: the delivery with the least
  /// delay. Native stamps plus this offset sit on the Dart clock, so two
  /// stamped events keep their true distance however late they arrive.
  int? _nativeOffsetUs;

  /// Native time of the running press's key-down, or null when it had no
  /// stamp.
  Duration? _downNativeAt;

  /// The time of the event being delivered: its native stamp moved onto the
  /// Dart clock, or the arrival time without a stamp.
  DateTime _eventTime() {
    final arrival = _clock();
    final at = _nativeEventAt();
    if (at == null) return arrival;
    final candidate = arrival.microsecondsSinceEpoch - at.inMicroseconds;
    var offset = _nativeOffsetUs;
    // A restarted native clock or a wrong first guess: start over.
    if (offset == null ||
        candidate < offset ||
        candidate - offset > const Duration(seconds: 30).inMicroseconds) {
      offset = candidate;
    }
    _nativeOffsetUs = offset;
    return DateTime.fromMicrosecondsSinceEpoch(at.inMicroseconds + offset);
  }

  /// One machine per gesture shape, reused across presses.
  final Map<String, HotkeyGestureMachine> _machines = {};

  /// Machine of the press whose key-up is still awaited.
  HotkeyGestureMachine? _activeMachine;

  /// Press start time. The held time of a release and the debug log count
  /// from it. Only the timing here starts a new press after a gap of at least
  /// the machine's repeat window; the gesture itself is decided by
  /// [HotkeyGestureMachine].
  DateTime? _pressDownAt;

  /// Last key-down, auto-repeats included. Used only to find the start of a
  /// new press (see [_pressDownAt]), so a press whose key-up was lost does not
  /// inherit the start time of the previous one.
  DateTime? _lastKeyDownAt;

  /// Held time of the last release in milliseconds, as the push-to-talk
  /// breadcrumb reports it.
  int _lastHeldMs = 0;
  @visibleForTesting
  int get lastHeldMs => _lastHeldMs;

  bool _keyUpBreadcrumbSent = false;

  /// This handler's recording is the one running (only such a recording may
  /// be stopped by a release).
  bool _owned = false;

  /// Session id of the recording this handler owns. Ownership only carries
  /// over to a later press while that very session still runs.
  String? _ownedSession;

  /// Own starts or toggles still in progress (slow pre-check). Overlapping
  /// presses each count, so the last one to finish settles the release.
  int _pendingStarts = 0;

  /// A release that arrived during [_ownPending] and waits for it to finish.
  _PendingRelease _pendingRelease = _PendingRelease.none;

  /// Latched hands-free recording (release no longer stops it). Every change
  /// is reported to [_onHandsFreeChanged], so a page can teach the gesture.
  bool get _latched => _latchedValue;
  set _latched(bool value) {
    if (value == _latchedValue) return;
    _latchedValue = value;
    _onHandsFreeChanged?.call(value);
  }

  bool _latchedValue = false;
  final void Function(bool handsFree)? _onHandsFreeChanged;

  /// Start of a press that waits for [_holdStartDelay]; cancelled by another
  /// key, a release or an abort before it fires.
  Timer? _deferredStart;

  /// Cancellation of the recording discarded by the first tap of a pair. The
  /// double-tap action waits for it (no race).
  Future<void>? _cancelInFlight;

  /// The start that is still opening a recording (its release arrived early).
  /// A double tap waits for it: the discard of the first tap holds the stop
  /// lock until the capture finished starting, and a second start would run
  /// into "still busy" (#1104).
  Future<void>? _startFlow;

  /// Called when the global hotkey is pressed (key-down).
  void onKeyDown() {
    _downNativeAt = _nativeEventAt();
    final now = _eventTime();
    _forgetEndedRecording();

    final keyUpObservable = _registrarSupportsKeyUp();
    final machine = _select(
      pushToTalk: _pushToTalkEnabled() && keyUpObservable,
      keyUpObservable: keyUpObservable,
    );
    final lastDown = _lastKeyDownAt;
    _lastKeyDownAt = now;
    if (_pressDownAt == null ||
        lastDown == null ||
        now.difference(lastDown) >= machine.repeatWindow) {
      _pressDownAt = now;
    }
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
  /// press started is cancelled, the release that follows does nothing, and
  /// the press is no tap of a double tap. A start still waiting for the delay
  /// never happens.
  void onOtherKey() {
    // Timing only, no key data: when the press turned into a combination.
    // Info, not debug: this alone explains a recording that vanishes right
    // after the press without a logged release (#1107, case 00:35:57).
    _log.info('Other key during the hotkey press${_sincePress()}');
    _cancelDeferredStart();
    _activeMachine?.otherKey(_eventTime());
  }

  /// " +N ms after key-down" for the debug log, empty without a press.
  String _sincePress() {
    final at = _pressDownAt;
    if (at == null) return '';
    return ' +${_clock().difference(at).inMilliseconds} ms after key-down';
  }

  /// Called when the global hotkey is released (key-up).
  void onKeyUp() {
    final pressedAt = _pressDownAt;
    // The press length the host measured wins over arrival times: the release
    // sits exactly that long after the press, whenever either reaches Dart.
    // Two stamps give it directly, a stampless key-down (hotkey grab) gets it
    // from the host's `pressMs`.
    final upAt = _nativeEventAt();
    final downAt = _downNativeAt;
    _downNativeAt = null;
    final mapped = _eventTime();
    final Duration? held = downAt != null && upAt != null && upAt >= downAt
        ? upAt - downAt
        : downAt == null
        ? _nativePressed()
        : null;
    // A release stamped before its press is not usable: arrival time then.
    final twisted = downAt != null && upAt != null && upAt < downAt;
    final now = pressedAt != null && held != null
        ? pressedAt.add(held)
        : twisted
        ? _clock()
        : mapped;
    final machine = _activeMachine;
    _activeMachine = null;
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
    final shape = selectHotkeyGesture(
      pushToTalk: pushToTalk,
      holdOrTap: _holdOrTapEnabled(),
      holdOrTapThresholdMs: _holdOrTapThresholdMs(),
      doubleTap: _doubleTapEnabled(),
      singleKey: _singleKey(),
    );
    return _machine(shape.gesture, doubleTap: shape.doubleTap)
      ..holdThreshold = shape.holdThreshold;
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
        // Released before the delayed start: nothing was recorded.
        if (_cancelDeferredStart()) return;
        _sendBreadcrumbOnce(gesture);
        _release(_PendingRelease.stop);
      case GestureOutput.abort:
        _log.debug(
          'Gesture abort${_sincePress()}, pending starts: $_pendingStarts',
        );
        if (_cancelDeferredStart()) return;
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
    await _deferOrRun(() => _ownStart(_startRecording));
  }

  /// Runs [begin] now, or after [_holdStartDelay] unless the press ends or
  /// another key comes first.
  Future<void> _deferOrRun(Future<void> Function() begin) async {
    final delay = _holdStartDelay();
    if (delay <= Duration.zero) return begin();
    _deferredStart?.cancel();
    _deferredStart = Timer(delay, () {
      _deferredStart = null;
      unawaited(begin());
    });
  }

  /// Cancels a delayed start that has not fired. Returns whether one was
  /// pending.
  bool _cancelDeferredStart() {
    final pending = _deferredStart;
    if (pending == null) return false;
    pending.cancel();
    _deferredStart = null;
    return true;
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
    await _deferOrRun(() => _ownStart(_toggleRecording));
  }

  /// Double tap: action, or a hands-free start.
  Future<void> _doubleTapAction() async {
    final cancel = _cancelInFlight;
    _cancelInFlight = null;
    if (cancel != null) await cancel;
    // The first tap's start may still be opening the capture: let it settle
    // (and its pending discard run) before the hands-free start follows.
    final flow = _startFlow;
    if (flow != null && _pendingStarts > 0) await flow;
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
  Future<void> _ownStart(Future<void> Function() begin) {
    final flow = _ownStartFlow(begin);
    _startFlow = flow.then<void>((_) {}, onError: (Object _) {});
    return flow;
  }

  Future<void> _ownStartFlow(Future<void> Function() begin) async {
    if (_isRecording()) {
      // A recording is already running. The press keeps it only if this
      // handler started that very session (its key-up was lost); a foreign
      // recording is never owned.
      if (!_ownsRunningRecording()) _owned = false;
      await begin();
      return;
    }
    final run = begin();
    if (_isRecording()) {
      _adoptRunningRecording();
      await run;
      return;
    }
    _pendingStarts++;
    _owned = false;
    try {
      await run;
    } catch (_) {
      // A failed start leaves nothing to stop. A release that arrived during
      // it belongs to that start and must not leak into the next press and
      // stop that recording.
      _pendingStarts--;
      _pendingRelease = _PendingRelease.none;
      rethrow;
    }
    _pendingStarts--;
    if (_isRecording()) _adoptRunningRecording();
    // An overlapping start still runs: the release waits for the last one.
    if (_pendingStarts > 0) return;
    _owned = _isRecording();
    await _settlePendingRelease();
  }

  void _adoptRunningRecording() {
    _owned = true;
    _ownedSession = _recordingSessionId();
  }

  /// True only for the session this handler started, and only while it runs.
  /// Without a session id (not wired) ownership never carries over.
  bool _ownsRunningRecording() {
    final session = _ownedSession;
    return _owned && session != null && session == _recordingSessionId();
  }

  /// Whether a release may act on the ownership: with session reporting only
  /// while the own session still runs, without it as before.
  bool _releaseMayAct() => _sessionWired ? _ownsRunningRecording() : _owned;

  /// Applies a release that arrived while the own start was still running.
  Future<void> _settlePendingRelease() async {
    final pending = _pendingRelease;
    _pendingRelease = _PendingRelease.none;
    // No pending release: the press keeps ownership of the recording it started.
    if (pending == _PendingRelease.none) return;
    if (!_releaseMayAct() || !_isRecording()) {
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
    if (_pendingStarts > 0) {
      _pendingRelease = kind;
      // An abort must reach the start while its preflight still runs, or a
      // key combination (Win+E) would still start or show an error (#331).
      // The pending abort stays for a start that got past the preflight.
      if (kind == _PendingRelease.abort) _cancelPendingStart();
      return;
    }
    if (!_owned) return;
    if (!_releaseMayAct()) {
      // The own recording ended (e.g. silence auto-stop) or another session
      // runs now: the release stops nothing and forgets the stale ownership.
      _owned = false;
      return;
    }
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

  void _cancelPendingStart() {
    _log.debug('Abort while the start runs → cancelRecording');
    _cancelInFlight = _cancelRecording().catchError((
      Object error,
      StackTrace stack,
    ) {
      _log.error('cancelRecording of a pending start failed', error, stack);
    });
  }

  void _abortOwned() {
    _owned = false;
    _latched = false;
    _log.debug('Release (short first tap) → cancelRecording');
    // Nobody awaits the cancel unless a double tap follows, so a failure is
    // logged here instead of surfacing as an uncaught zone error.
    _cancelInFlight = _cancelRecording().catchError((
      Object error,
      StackTrace stack,
    ) {
      _log.error(
        'cancelRecording of a discarded first tap failed',
        error,
        stack,
      );
    });
  }

  /// Forgets latch and ownership once the recording ended elsewhere.
  void _forgetEndedRecording() {
    if (_pendingStarts > 0 || _isRecording()) return;
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

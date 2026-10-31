/// The key test of the onboarding hotkey page (Onboarding v6, screen 5).
///
/// During onboarding the recording ignores the dictation hotkey, so the page
/// plays the presses through the same [HotkeyGestureMachine] the recording
/// uses ([selectHotkeyGesture]) and keeps a pretend recording. The page then
/// says what a real press would have done: started, stopped, or gone
/// hands-free. The proof that counts for Next is a full start and stop.
library;

import '../../services/hotkey_gesture_machine.dart';
import '../../services/recording_trigger_handler.dart';

/// What the key test shows.
enum HotkeyPracticePhase {
  /// Nothing pressed yet, or the last try left nothing running.
  ready,

  /// A hold runs: dictation would run until the key is let go.
  held,

  /// A press started a toggle recording; the next press stops it.
  toggledOn,

  /// A double tap started hands-free dictation; one press ends it.
  handsFree,

  /// A hold mode press was too short to dictate anything, and no second tap
  /// followed: "hold it a little longer".
  tooShort,

  /// Start and stop were recognised (hold or toggle).
  done,

  /// Hands-free start and stop were recognised.
  doneHandsFree,
}

/// Feeds key presses through the configured gesture and tracks the result.
/// The clock is the caller's, so tests stay deterministic.
class HotkeyPractice {
  HotkeyPractice({
    required bool pushToTalk,
    required bool holdOrTap,
    required int holdOrTapThresholdMs,
    required bool doubleTap,
    required bool singleKey,
  }) : _holdMode = pushToTalk && !holdOrTap {
    final shape = selectHotkeyGesture(
      pushToTalk: pushToTalk,
      holdOrTap: holdOrTap,
      holdOrTapThresholdMs: holdOrTapThresholdMs,
      doubleTap: doubleTap,
      singleKey: singleKey,
    );
    _machine = HotkeyGestureMachine(
      gesture: shape.gesture,
      doubleTapEnabled: shape.doubleTap,
      holdThreshold: shape.holdThreshold,
      onOutput: _onOutput,
    );
    _doubleTapPossible =
        shape.doubleTap || shape.gesture == HotkeyGesture.doubleTap;
  }

  /// A hold shorter than this dictates nothing useful, so the test asks for
  /// a longer one instead of counting it.
  static const minUsefulHold = Duration(milliseconds: 250);

  late final HotkeyGestureMachine _machine;
  final bool _holdMode;
  late final bool _doubleTapPossible;

  bool _recording = false;
  bool _latched = false;
  DateTime? _downAt;

  /// Release of a short tap that may still become a double tap.
  DateTime? _pendingTapAt;

  HotkeyPracticePhase _phase = HotkeyPracticePhase.ready;
  HotkeyPracticePhase get phase => _phase;

  /// A full start and stop was seen at least once.
  bool get proven => _proven;
  bool _proven = false;

  /// Whether the pretend recording runs (the scene's pill lights).
  bool get recording => _recording;

  void down(DateTime now) {
    _downAt = now;
    _pendingTapAt = null;
    _machine.down(now, isRecording: _recording);
  }

  void up(DateTime now) {
    final downAt = _downAt;
    _downAt = null;
    final wasRecording = _recording;
    final provenBefore = _proven;
    _machine.up(now);
    // Hold mode without double tap: a flick starts and stops at once, which
    // proves nothing about dictating.
    if (_holdMode &&
        !_doubleTapPossible &&
        wasRecording &&
        !_recording &&
        downAt != null &&
        now.difference(downAt) < minUsefulHold &&
        _phase == HotkeyPracticePhase.done) {
      _phase = HotkeyPracticePhase.tooShort;
      _proven = provenBefore;
    }
    if (_doubleTapPossible && _phase == HotkeyPracticePhase.ready) {
      _pendingTapAt = now;
    }
  }

  /// Another key joined the press (a single key used in a shortcut).
  void otherKey(DateTime now) {
    _pendingTapAt = null;
    _machine.otherKey(now);
  }

  /// Call when the double-tap window may have passed: a lone short tap then
  /// turns into the "hold longer" hint. Returns whether the phase changed.
  bool settle(DateTime now) {
    final tapAt = _pendingTapAt;
    if (tapAt == null || now.difference(tapAt) < _machine.doubleTapWindow) {
      return false;
    }
    _pendingTapAt = null;
    if (_phase != HotkeyPracticePhase.ready || !_holdMode) return false;
    _phase = HotkeyPracticePhase.tooShort;
    return true;
  }

  /// How long after a release [settle] is worth calling.
  Duration get doubleTapWindow => _machine.doubleTapWindow;

  void _onOutput(GestureOutput output) {
    switch (output) {
      case GestureOutput.start:
        if (_latched && _recording) {
          _finish(handsFree: true);
        } else {
          _recording = true;
          _phase = HotkeyPracticePhase.held;
        }
      case GestureOutput.stop:
        if (_recording && !_latched) _finish(handsFree: false);
      case GestureOutput.abort:
        // A tap of a possible pair, or a shortcut: nothing was dictated. The
        // short press that just ended hands-free is no such tap.
        if (!_latched && _recording) {
          _recording = false;
          _phase = HotkeyPracticePhase.ready;
        }
      case GestureOutput.toggle:
        if (_recording) {
          _finish(handsFree: _latched);
        } else {
          _recording = true;
          _phase = HotkeyPracticePhase.toggledOn;
        }
      case GestureOutput.doubleTap:
        _recording = true;
        _latched = true;
        _phase = HotkeyPracticePhase.handsFree;
    }
  }

  void _finish({required bool handsFree}) {
    _recording = false;
    _latched = false;
    _proven = true;
    _phase = handsFree
        ? HotkeyPracticePhase.doneHandsFree
        : HotkeyPracticePhase.done;
  }
}

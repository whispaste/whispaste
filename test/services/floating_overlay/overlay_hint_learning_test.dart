import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/floating_overlay/overlay_hint_learning.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 9);
  const hotkey = 'ctrl+shift+D';
  const esc = 'escape';

  KeyHintVisibility decide(
    OverlayHintLearningState s, {
    bool always = false,
    String stopKey = hotkey,
    String cancelKey = esc,
    DateTime? now,
  }) => OverlayHintLearning.decide(
    s,
    always: always,
    stopKey: stopKey,
    cancelKey: cancelKey,
    now: now ?? t0,
  );

  OverlayHintLearningState hotkeyStops(
    int n, {
    OverlayHintLearningState start = OverlayHintLearningState.initial,
    String stopKey = hotkey,
  }) {
    var s = start;
    for (var i = 0; i < n; i++) {
      s = OverlayHintLearning.recordHotkeyStop(s, stopKey: stopKey);
      s = OverlayHintLearning.recordCompleted(s, cancelKey: esc, now: t0);
    }
    return s;
  }

  group('stop hint', () {
    test('shows until the hotkey stopped $stopsToLearn dictations', () {
      expect(decide(OverlayHintLearningState.initial).showStop, isTrue);
      expect(decide(hotkeyStops(stopsToLearn - 1)).showStop, isTrue);
      expect(decide(hotkeyStops(stopsToLearn)).showStop, isFalse);
    });

    test('stops by click or auto-stop do not teach the hotkey', () {
      var s = OverlayHintLearningState.initial;
      for (var i = 0; i < 40; i++) {
        s = OverlayHintLearning.recordCompleted(s, cancelKey: esc, now: t0);
      }
      expect(decide(s).showStop, isTrue);
    });

    test('a changed hotkey is learned anew', () {
      final learned = hotkeyStops(stopsToLearn);
      expect(decide(learned, stopKey: 'alt+Space').showStop, isTrue);
      final relearn = OverlayHintLearning.recordHotkeyStop(
        learned,
        stopKey: 'alt+Space',
      );
      expect(relearn.stopsByHotkey, 1);
    });

    test('the stop counter does not touch the cancel hint', () {
      expect(decide(hotkeyStops(stopsToLearn)).showCancel, isTrue);
    });
  });

  group('cancel hint', () {
    test('goes away after $cancelsToLearn cancels by key', () {
      var s = OverlayHintLearningState.initial;
      for (var i = 0; i < cancelsToLearn - 1; i++) {
        s = OverlayHintLearning.recordCancel(
          s,
          byKey: true,
          cancelKey: esc,
          now: t0,
        );
      }
      expect(decide(s).showCancel, isTrue);
      s = OverlayHintLearning.recordCancel(
        s,
        byKey: true,
        cancelKey: esc,
        now: t0,
      );
      expect(decide(s).showCancel, isFalse);
      expect(decide(s).showStop, isTrue);
    });

    test('a cancel by click does not count as a key cancel', () {
      var s = OverlayHintLearningState.initial;
      for (var i = 0; i < 10; i++) {
        s = OverlayHintLearning.recordCancel(
          s,
          byKey: false,
          cancelKey: esc,
          now: t0,
        );
      }
      expect(decide(s).showCancel, isTrue);
    });

    test('retires after $dictationsToRetireCancel finished dictations', () {
      var s = OverlayHintLearningState.initial;
      for (var i = 0; i < dictationsToRetireCancel - 1; i++) {
        s = OverlayHintLearning.recordCompleted(s, cancelKey: esc, now: t0);
      }
      expect(decide(s).showCancel, isTrue);
      s = OverlayHintLearning.recordCompleted(s, cancelKey: esc, now: t0);
      expect(decide(s).showCancel, isFalse);
    });

    test('a changed cancel key is learned anew', () {
      var s = OverlayHintLearningState.initial;
      for (var i = 0; i < cancelsToLearn; i++) {
        s = OverlayHintLearning.recordCancel(
          s,
          byKey: true,
          cancelKey: esc,
          now: t0,
        );
      }
      expect(decide(s, cancelKey: 'f12').showCancel, isTrue);
      s = OverlayHintLearning.recordCompleted(s, cancelKey: 'f12', now: t0);
      expect(s.cancelsByKey, 0);
      expect(s.completed, 1);
    });
  });

  group('return after a break', () {
    test('both hints come back after $returnGap for '
        '$refreshDictations dictations', () {
      var s = hotkeyStops(stopsToLearn);
      for (var i = 0; i < dictationsToRetireCancel; i++) {
        s = OverlayHintLearning.recordCompleted(s, cancelKey: esc, now: t0);
      }
      expect(decide(s), (showStop: false, showCancel: false));

      var now = t0.add(returnGap + const Duration(days: 1));
      expect(decide(s, now: now), (showStop: true, showCancel: true));
      for (var i = 0; i < refreshDictations; i++) {
        s = OverlayHintLearning.recordCompleted(s, cancelKey: esc, now: now);
        now = now.add(const Duration(minutes: 5));
      }
      expect(decide(s, now: now), (showStop: false, showCancel: false));
    });

    test('a short break changes nothing', () {
      final s = hotkeyStops(stopsToLearn);
      final now = t0.add(const Duration(days: 29));
      expect(decide(s, now: now).showStop, isFalse);
    });
  });

  test('"always show" keeps both hints', () {
    var s = hotkeyStops(stopsToLearn);
    for (var i = 0; i < dictationsToRetireCancel; i++) {
      s = OverlayHintLearning.recordCompleted(s, cancelKey: esc, now: t0);
    }
    expect(decide(s, always: true), (showStop: true, showCancel: true));
  });

  test('the hotkey identity follows the active trigger', () {
    expect(
      stopKeyIdentity(const HotkeySettings()),
      isNot(stopKeyIdentity(const HotkeySettings(hotkeyKey: 'F'))),
    );
    expect(
      stopKeyIdentity(const HotkeySettings(hotkeyDoubleTapKey: 'rightAlt')),
      isNot(stopKeyIdentity(const HotkeySettings(hotkeyDoubleTapKey: 'fn'))),
    );
  });

  test('missing or broken stored values read as a fresh start', () async {
    SharedPreferences.setMockInitialValues({
      'overlay_hints_stops_by_hotkey': 'x',
      'overlay_hints_completed': -4,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(readHintLearning(prefs), OverlayHintLearningState.initial);
  });
}

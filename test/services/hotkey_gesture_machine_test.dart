/// Unit tests for [HotkeyGestureMachine] — pure Dart, no platform code.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/hotkey_gesture_machine.dart';

void main() {
  late List<GestureOutput> out;
  late DateTime t;

  setUp(() {
    out = [];
    t = DateTime(2026, 10, 21, 12);
  });

  HotkeyGestureMachine make(
    HotkeyGesture gesture, {
    Duration holdThreshold = const Duration(milliseconds: 250),
    Duration doubleTapWindow = const Duration(milliseconds: 400),
    bool doubleTapEnabled = false,
  }) => HotkeyGestureMachine(
    gesture: gesture,
    holdThreshold: holdThreshold,
    doubleTapWindow: doubleTapWindow,
    doubleTapEnabled: doubleTapEnabled,
    onOutput: out.add,
  );

  void at(int ms) =>
      t = DateTime(2026, 10, 21, 12).add(Duration(milliseconds: ms));

  group('hold (Halten = push-to-talk)', () {
    test('down starts synchronously, up stops', () {
      final m = make(HotkeyGesture.hold);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.start], reason: 'start must not wait for up');
      at(900);
      m.up(t);
      expect(out, [GestureOutput.start, GestureOutput.stop]);
    });

    test('OS auto-repeat downs while held are ignored', () {
      final m = make(HotkeyGesture.hold);
      m.down(t, isRecording: false);
      at(30);
      m.down(t, isRecording: false);
      at(60);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.start]);
    });
  });

  group('tap (Tippen = Freihand-Toggle)', () {
    test('each press toggles immediately, release emits nothing', () {
      final m = make(HotkeyGesture.tap);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.toggle]);
      at(50);
      m.up(t);
      expect(out, [GestureOutput.toggle]);
      at(2000);
      m.down(t, isRecording: true);
      expect(out, [GestureOutput.toggle, GestureOutput.toggle]);
    });
  });

  group('auto (Automatisch = Hybrid)', () {
    test('press starts recording without delay', () {
      final m = make(HotkeyGesture.auto);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.toggle]);
    });

    test('short tap latches: release does not stop', () {
      final m = make(HotkeyGesture.auto);
      m.down(t, isRecording: false);
      at(249);
      m.up(t);
      expect(out, [GestureOutput.toggle]);
    });

    test('hold at threshold or longer stops on release', () {
      final m = make(HotkeyGesture.auto);
      m.down(t, isRecording: false);
      at(250);
      m.up(t);
      expect(out, [GestureOutput.toggle, GestureOutput.stop]);
    });

    test('custom threshold is honoured', () {
      final m = make(
        HotkeyGesture.auto,
        holdThreshold: const Duration(milliseconds: 600),
      );
      m.down(t, isRecording: false);
      at(400);
      m.up(t);
      expect(out, [GestureOutput.toggle]);
    });

    test(
      'a press that stops a running recording never emits stop on release',
      () {
        final m = make(HotkeyGesture.auto);
        m.down(t, isRecording: true);
        at(800);
        m.up(t);
        expect(out, [GestureOutput.toggle]);
      },
    );

    test('a second short tap while latched stops the recording', () {
      final m = make(HotkeyGesture.auto);
      m.down(t, isRecording: false);
      at(100);
      m.up(t);
      at(3000);
      m.down(t, isRecording: true);
      expect(out, [GestureOutput.toggle, GestureOutput.toggle]);
    });
  });

  group('doubleTap (Doppeltippen)', () {
    test('two short taps inside the window emit doubleTap on second down', () {
      final m = make(HotkeyGesture.doubleTap);
      m.down(t, isRecording: false);
      at(80);
      m.up(t);
      expect(out, isEmpty, reason: 'a single tap is never an action');
      at(250);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.doubleTap]);
    });

    test('second down exactly at the window end is a new first tap', () {
      final m = make(HotkeyGesture.doubleTap);
      m.down(t, isRecording: false);
      at(80);
      m.up(t);
      at(480);
      m.down(t, isRecording: false);
      expect(out, isEmpty);
    });

    test('a long press breaks the sequence', () {
      final m = make(HotkeyGesture.doubleTap);
      m.down(t, isRecording: false);
      at(300);
      m.up(t);
      at(350);
      m.down(t, isRecording: false);
      expect(out, isEmpty);
    });

    test('after a doubleTap a third quick tap starts no new pair', () {
      final m = make(HotkeyGesture.doubleTap);
      m.down(t, isRecording: false);
      at(50);
      m.up(t);
      at(150);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.doubleTap]);
      at(200);
      m.up(t);
      at(300);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.doubleTap]);
    });
  });

  group('hold plus double tap on the same key', () {
    test('a short release discards the started recording silently', () {
      final m = make(HotkeyGesture.hold, doubleTapEnabled: true);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.start]);
      at(120);
      m.up(t);
      expect(out, [GestureOutput.start, GestureOutput.abort]);
    });

    test('a long hold still stops normally', () {
      final m = make(HotkeyGesture.hold, doubleTapEnabled: true);
      m.down(t, isRecording: false);
      at(900);
      m.up(t);
      expect(out, [GestureOutput.start, GestureOutput.stop]);
    });

    test(
      'a second press inside the window runs the action, without starting',
      () {
        final m = make(HotkeyGesture.hold, doubleTapEnabled: true);
        m.down(t, isRecording: false);
        at(120);
        m.up(t);
        at(200);
        m.down(t, isRecording: true);
        expect(out, [
          GestureOutput.start,
          GestureOutput.abort,
          GestureOutput.doubleTap,
        ]);
        at(260);
        m.up(t);
        expect(out, [
          GestureOutput.start,
          GestureOutput.abort,
          GestureOutput.doubleTap,
        ], reason: 'releasing the second tap must not stop anything');
      },
    );

    test('a press after the window starts again instead of doubling', () {
      final m = make(HotkeyGesture.hold, doubleTapEnabled: true);
      m.down(t, isRecording: false);
      at(120);
      m.up(t);
      at(600);
      m.down(t, isRecording: false);
      expect(out, [
        GestureOutput.start,
        GestureOutput.abort,
        GestureOutput.start,
      ]);
    });

    test(
      'a long hold before a quick press does not count as the first tap',
      () {
        final m = make(HotkeyGesture.hold, doubleTapEnabled: true);
        m.down(t, isRecording: false);
        at(900);
        m.up(t);
        at(1000);
        m.down(t, isRecording: false);
        expect(out, [
          GestureOutput.start,
          GestureOutput.stop,
          GestureOutput.start,
        ]);
      },
    );

    test('a completed double tap does not chain into a third press', () {
      final m = make(HotkeyGesture.hold, doubleTapEnabled: true);
      m.down(t, isRecording: false);
      at(100);
      m.up(t);
      at(200);
      m.down(t, isRecording: true);
      at(260);
      m.up(t);
      at(300);
      m.down(t, isRecording: false);
      expect(out.last, GestureOutput.start);
    });

    test('double tap is refused on tap and auto keys', () {
      expect(
        () => make(HotkeyGesture.tap, doubleTapEnabled: true),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => make(HotkeyGesture.auto, doubleTapEnabled: true),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a double-tap-only key starts nothing on the first press', () {
      final m = make(HotkeyGesture.doubleTap);
      m.down(t, isRecording: false);
      expect(out, isEmpty);
    });
  });

  group('modifier-only abort ("andere Taste dazwischen")', () {
    test('other key while a recording-starting press is held aborts it', () {
      final m = make(HotkeyGesture.hold);
      m.down(t, isRecording: false);
      at(40);
      m.otherKey(t);
      expect(out, [GestureOutput.start, GestureOutput.abort]);
      at(300);
      m.up(t);
      expect(out, [
        GestureOutput.start,
        GestureOutput.abort,
      ], reason: 'release after an abort must not emit stop');
    });

    test('other key during a stopping press emits nothing', () {
      final m = make(HotkeyGesture.auto);
      m.down(t, isRecording: true);
      at(40);
      m.otherKey(t);
      expect(out, [GestureOutput.toggle]);
    });

    test('other key without a held press is ignored', () {
      final m = make(HotkeyGesture.hold);
      m.otherKey(t);
      expect(out, isEmpty);
    });
  });

  group('lost key-up recovery', () {
    test('down after the repeat window counts as a new press', () {
      final m = make(HotkeyGesture.hold);
      m.down(t, isRecording: false);
      at(1500);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.start, GestureOutput.start]);
    });
  });

  group('HK-A1 boundaries and rules', () {
    test('plain hold: every release stops, at 0, 99 and 100 ms', () {
      for (final ms in [0, 99, 100]) {
        out.clear();
        final m = make(HotkeyGesture.hold);
        at(0);
        m.down(t, isRecording: false);
        at(ms);
        m.up(t);
        expect(out, [GestureOutput.start, GestureOutput.stop], reason: '$ms');
      }
    });

    test(
      'hold + double tap: short release (< 100 ms) aborts, 100 ms stops',
      () {
        for (final ms in [0, 99]) {
          out.clear();
          final m = make(
            HotkeyGesture.hold,
            doubleTapEnabled: true,
            holdThreshold: const Duration(milliseconds: 100),
          );
          at(0);
          m.down(t, isRecording: false);
          at(ms);
          m.up(t);
          expect(out, [
            GestureOutput.start,
            GestureOutput.abort,
          ], reason: '$ms');
        }
        out.clear();
        final m = make(
          HotkeyGesture.hold,
          doubleTapEnabled: true,
          holdThreshold: const Duration(milliseconds: 100),
        );
        at(0);
        m.down(t, isRecording: false);
        at(100);
        m.up(t);
        expect(out, [GestureOutput.start, GestureOutput.stop]);
      },
    );

    test('hold + double tap: 249 / 250 / 251 ms are holds (stop)', () {
      for (final ms in [249, 250, 251]) {
        out.clear();
        final m = make(
          HotkeyGesture.hold,
          doubleTapEnabled: true,
          holdThreshold: const Duration(milliseconds: 100),
        );
        at(0);
        m.down(t, isRecording: false);
        at(ms);
        m.up(t);
        expect(out, [GestureOutput.start, GestureOutput.stop], reason: '$ms');
      }
    });

    test('double tap window: 399 ms pairs, 400 and 401 ms do not', () {
      for (final gap in [399, 400, 401]) {
        out.clear();
        final m = make(HotkeyGesture.doubleTap);
        m.down(t, isRecording: false);
        at(80);
        m.up(t);
        at(80 + gap);
        m.down(t, isRecording: false);
        expect(
          out,
          gap == 399 ? [GestureOutput.doubleTap] : isEmpty,
          reason: 'gap $gap',
        );
      }
    });

    test('double-tap key: a tap while recording stops it, no pair', () {
      final m = make(HotkeyGesture.doubleTap);
      m.down(t, isRecording: true);
      expect(out, [GestureOutput.toggle]);
      at(50);
      m.up(t);
      at(120);
      m.down(t, isRecording: false);
      expect(out, [GestureOutput.toggle], reason: 'stop press cannot pair');
    });
  });
}

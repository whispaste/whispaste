/// Unit tests for [HotkeyPractice] — the key test of the onboarding hotkey
/// page judges presses with the recording's own gesture rules.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/onboarding/hotkey_practice.dart';

void main() {
  final t0 = DateTime(2026, 10, 30, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  HotkeyPractice make({
    bool pushToTalk = true,
    bool holdOrTap = false,
    bool doubleTap = true,
    bool singleKey = false,
  }) => HotkeyPractice(
    pushToTalk: pushToTalk,
    holdOrTap: holdOrTap,
    holdOrTapThresholdMs: 300,
    doubleTap: doubleTap,
    singleKey: singleKey,
  );

  group('hold mode', () {
    test('hold and release proves the key', () {
      final p = make(doubleTap: false);
      p.down(at(0));
      expect(p.phase, HotkeyPracticePhase.held);
      expect(p.recording, isTrue);
      p.up(at(900));
      expect(p.phase, HotkeyPracticePhase.done);
      expect(p.proven, isTrue);
      expect(p.recording, isFalse);
    });

    test('a flick without double tap asks for a longer hold', () {
      final p = make(doubleTap: false);
      p.down(at(0));
      p.up(at(60));
      expect(p.phase, HotkeyPracticePhase.tooShort);
      expect(p.proven, isFalse);
    });

    test('a lone short tap turns into the hint only after the double-tap '
        'window', () {
      final p = make();
      p.down(at(0));
      p.up(at(50));
      expect(p.phase, HotkeyPracticePhase.ready);
      expect(p.settle(at(100)), isFalse);
      expect(p.phase, HotkeyPracticePhase.ready);
      expect(p.settle(at(50).add(p.doubleTapWindow)), isTrue);
      expect(p.phase, HotkeyPracticePhase.tooShort);
      expect(p.proven, isFalse);
    });

    test('double tap goes hands-free and one press ends it', () {
      final p = make();
      p.down(at(0));
      p.up(at(50));
      p.down(at(150));
      expect(p.phase, HotkeyPracticePhase.handsFree);
      expect(p.recording, isTrue);
      p.up(at(200));
      expect(p.phase, HotkeyPracticePhase.handsFree);
      expect(p.settle(at(2000)), isFalse);
      p.down(at(3000));
      expect(p.phase, HotkeyPracticePhase.doneHandsFree);
      expect(p.proven, isTrue);
      p.up(at(3050));
      expect(p.phase, HotkeyPracticePhase.doneHandsFree);
      expect(p.recording, isFalse);
    });

    test('another key during the hold drops the try', () {
      final p = make();
      p.down(at(0));
      p.otherKey(at(100));
      expect(p.phase, HotkeyPracticePhase.ready);
      expect(p.recording, isFalse);
      p.up(at(400));
      expect(p.proven, isFalse);
    });
  });

  group('press to start and stop', () {
    test('the first press starts, the second stops', () {
      final p = make(pushToTalk: false, doubleTap: false);
      p.down(at(0));
      p.up(at(80));
      expect(p.phase, HotkeyPracticePhase.toggledOn);
      expect(p.proven, isFalse);
      p.down(at(1500));
      p.up(at(1580));
      expect(p.phase, HotkeyPracticePhase.done);
      expect(p.proven, isTrue);
    });

    test('a single key with double tap only reacts to the pair', () {
      final p = make(pushToTalk: false, singleKey: true);
      p.down(at(0));
      p.up(at(50));
      expect(p.phase, HotkeyPracticePhase.ready);
      p.down(at(150));
      p.up(at(200));
      expect(p.phase, HotkeyPracticePhase.handsFree);
      p.down(at(2000));
      p.up(at(2050));
      expect(p.phase, HotkeyPracticePhase.doneHandsFree);
      expect(p.proven, isTrue);
    });
  });
}

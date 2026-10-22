/// Unit tests for [RecordingTriggerHandler] — Push-to-Talk vs Toggle mode.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _Counters {
  int start = 0;
  int stop = 0;
  int toggle = 0;
  bool recording = false;

  void reset() {
    start = 0;
    stop = 0;
    toggle = 0;
  }
}

RecordingTriggerHandler _make({
  required _Counters counters,
  required bool pushToTalk,
  required bool supportsKeyUp,
}) {
  return RecordingTriggerHandler(
    startRecording: () async {
      counters.start++;
      counters.recording = true;
    },
    stopRecording: () async {
      counters.stop++;
      counters.recording = false;
    },
    toggleRecording: () async {
      counters.toggle++;
      counters.recording = !counters.recording;
    },
    pushToTalkEnabled: () => pushToTalk,
    registrarSupportsKeyUp: () => supportsKeyUp,
    // The handler only stops recordings it started, so it needs the state.
    isRecording: () => counters.recording,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Sentry requires a binding before breadcrumb calls.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingTriggerHandler — toggle mode (pushToTalk=false)', () {
    test('T1: onKeyDown calls toggleRecording, onKeyUp is a no-op', () async {
      final c = _Counters();
      final handler = _make(
        counters: c,
        pushToTalk: false,
        supportsKeyUp: true,
      );

      handler.onKeyDown();
      expect(c.toggle, equals(1));
      expect(c.start, equals(0));
      expect(c.stop, equals(0));

      handler.onKeyUp();
      expect(c.toggle, equals(1)); // unchanged
      expect(c.stop, equals(0));
    });
  });

  group(
    'RecordingTriggerHandler — PTT mode (pushToTalk=true, supportsKeyUp=true)',
    () {
      test('T2: hold ≥ 100 ms → startRecording then stopRecording', () async {
        final c = _Counters();
        // Use a real 110 ms delay to exceed the 100 ms anti-glitch threshold.
        final handler = _make(
          counters: c,
          pushToTalk: true,
          supportsKeyUp: true,
        );

        handler.onKeyDown();
        expect(c.start, equals(1));
        expect(c.stop, equals(0));

        // Wait > 100 ms so the anti-glitch guard allows stopRecording.
        await Future<void>.delayed(const Duration(milliseconds: 110));

        handler.onKeyUp();
        expect(c.stop, equals(1));
        expect(c.toggle, equals(0));
      });

      test(
        'T3 (Befund 2): hold < 100 ms → start, and the release still stops',
        () async {
          final c = _Counters();
          final handler = _make(
            counters: c,
            pushToTalk: true,
            supportsKeyUp: true,
          );

          handler.onKeyDown();
          expect(c.start, equals(1));

          // Do NOT wait — keyUp fires immediately (< 100 ms).
          handler.onKeyUp();
          expect(c.stop, equals(1), reason: 'every release ends the press');
          expect(c.toggle, equals(0));
        },
      );
    },
  );

  group(
    'RecordingTriggerHandler — PTT mode but platform has no keyUp support',
    () {
      test(
        'T4: pushToTalk=true && supportsKeyUp=false → falls back to toggle behavior',
        () {
          final c = _Counters();
          final handler = _make(
            counters: c,
            pushToTalk: true,
            supportsKeyUp: false,
          );

          handler.onKeyDown();
          expect(c.toggle, equals(1));
          expect(c.start, equals(0));

          handler.onKeyUp();
          expect(c.stop, equals(0));
          expect(c.toggle, equals(1)); // unchanged after keyUp
        },
      );
    },
  );

  group('RecordingTriggerHandler — hold-or-tap mode (hybrid)', () {
    const threshold = RecordingTriggerHandler.holdOrTapThreshold;

    test('threshold defaults to 250 ms (settings can change it)', () {
      expect(threshold, const Duration(milliseconds: 250));
    });

    test('H4: a press of 200 ms (below the 250 ms default) still latches', () {
      final h = _Hybrid();
      h.handler.onKeyDown();
      h.advance(const Duration(milliseconds: 200));
      h.handler.onKeyUp();
      expect(h.stop, 0, reason: 'short press stays latched below 250 ms');
      expect(h.recording, isTrue);
    });

    test('H1: short tap toggles on and keeps recording (latched)', () {
      final h = _Hybrid();
      h.handler.onKeyDown();
      expect(h.toggle, 1);
      expect(h.recording, isTrue);

      h.advance(const Duration(milliseconds: 120));
      h.handler.onKeyUp();
      expect(h.stop, 0, reason: 'tap latches — release must not stop');
      expect(h.recording, isTrue);
    });

    test('H2: holding ≥ threshold acts as push-to-talk (release stops)', () {
      final h = _Hybrid();
      h.handler.onKeyDown();
      expect(h.recording, isTrue);

      h.advance(const Duration(milliseconds: 1500));
      h.handler.onKeyUp();
      expect(h.stop, 1);
      expect(h.recording, isFalse);
    });

    test(
      'H3: boundary — just below threshold is a tap, exactly at it a hold',
      () {
        final below = _Hybrid();
        below.handler.onKeyDown();
        below.advance(threshold - const Duration(milliseconds: 1));
        below.handler.onKeyUp();
        expect(below.stop, 0);
        expect(below.recording, isTrue);

        final at = _Hybrid();
        at.handler.onKeyDown();
        at.advance(threshold);
        at.handler.onKeyUp();
        expect(at.stop, 1);
        expect(at.recording, isFalse);
      },
    );

    test('H4: double tap — first tap starts, second tap stops', () {
      final h = _Hybrid();
      h.handler.onKeyDown();
      h.advance(const Duration(milliseconds: 80));
      h.handler.onKeyUp();
      h.advance(const Duration(milliseconds: 150));
      h.handler.onKeyDown();
      expect(h.recording, isFalse, reason: 'second press stops like Toggle');
      h.advance(const Duration(milliseconds: 80));
      h.handler.onKeyUp();

      expect(h.toggle, 2);
      expect(h.stop, 0, reason: 'release of the stopping press is a no-op');
      expect(h.recording, isFalse);
    });

    test('H5: OS key-repeat while held fires only once', () {
      final h = _Hybrid();
      h.handler.onKeyDown();
      for (var i = 0; i < 10; i++) {
        h.advance(const Duration(milliseconds: 40));
        h.handler.onKeyDown(); // auto-repeat
      }
      expect(h.toggle, 1, reason: 'repeats must not toggle again');
      expect(h.recording, isTrue);

      h.advance(const Duration(milliseconds: 700));
      h.handler.onKeyUp();
      expect(h.stop, 1);
      expect(h.recording, isFalse);
    });

    test('H6: a long press that stops a latched recording does not restart '
        'or re-stop it on release', () {
      final h = _Hybrid();
      h.handler.onKeyDown();
      h.advance(const Duration(milliseconds: 50));
      h.handler.onKeyUp(); // latched
      h.advance(const Duration(seconds: 5));
      h.handler.onKeyDown(); // stops
      h.advance(const Duration(seconds: 2));
      h.handler.onKeyUp();

      expect(h.toggle, 2);
      expect(h.stop, 0);
      expect(h.recording, isFalse);
    });

    test('H7: recording ended elsewhere after a tap — next press starts '
        'a new recording', () {
      final h = _Hybrid();
      h.handler.onKeyDown();
      h.advance(const Duration(milliseconds: 50));
      h.handler.onKeyUp();
      h.recording = false; // e.g. silence auto-stop
      h.advance(const Duration(seconds: 3));

      h.handler.onKeyDown();
      expect(h.recording, isTrue);
    });

    test('H8: a lost key-up does not wedge the handler', () {
      final h = _Hybrid();
      h.handler.onKeyDown(); // key-up never arrives
      h.advance(const Duration(seconds: 5));
      h.handler.onKeyDown();
      expect(h.toggle, 2, reason: 'a later genuine press is honoured');
    });

    test('H9: falls back to plain toggle without key-up support', () {
      final h = _Hybrid(supportsKeyUp: false);
      h.handler.onKeyDown();
      h.advance(const Duration(seconds: 2));
      h.handler.onKeyUp();
      expect(h.toggle, 1);
      expect(h.stop, 0);
      expect(h.recording, isTrue);
    });

    test('H10: inactive while push-to-talk itself is off (plain toggle)', () {
      final h = _Hybrid(pushToTalk: false);
      h.handler.onKeyDown();
      h.advance(const Duration(seconds: 2));
      h.handler.onKeyUp();
      expect(h.toggle, 1);
      expect(h.stop, 0);
      expect(h.start, 0);
    });

    test('H11: a hold while not actually recording (e.g. transcribing) '
        'does not call stop on release', () {
      final h = _Hybrid()..toggleStarts = false;
      h.handler.onKeyDown();
      h.advance(const Duration(seconds: 1));
      h.handler.onKeyUp();
      expect(h.stop, 0);
    });
  });

  group('HK-A1 gesture runtime (single rule source: HotkeyGestureMachine)', () {
    test('Befund 2: hold releases stop at 0, 99 and 100 ms', () {
      for (final ms in [0, 99, 100]) {
        final g = _Gesture();
        g.handler.onKeyDown();
        g.advance(Duration(milliseconds: ms));
        g.handler.onKeyUp();
        expect(g.start, 1, reason: '$ms ms');
        expect(g.stop, 1, reason: '$ms ms: every release ends the press');
        expect(g.recording, isFalse, reason: '$ms ms');
      }
    });

    test('Befund 2: hybrid threshold boundaries 249 / 250 / 251 ms', () {
      final below = _Gesture(holdOrTap: true);
      below.handler.onKeyDown();
      below.advance(const Duration(milliseconds: 249));
      below.handler.onKeyUp();
      expect(below.stop, 0, reason: '249 ms latches');

      for (final ms in [250, 251]) {
        final g = _Gesture(holdOrTap: true);
        g.handler.onKeyDown();
        g.advance(Duration(milliseconds: ms));
        g.handler.onKeyUp();
        expect(g.stop, 1, reason: '$ms ms is push-to-talk');
      }
    });

    test('Befund 3: double tap starts hands-free, one tap stops it', () async {
      final g = _Gesture(pushToTalk: false, doubleTap: true, latch: true);
      g.handler.onKeyDown();
      g.advance(const Duration(milliseconds: 80));
      g.handler.onKeyUp();
      g.advance(const Duration(milliseconds: 150));
      g.handler.onKeyDown();
      await _pump();
      expect(g.start, 1, reason: 'double tap starts');
      expect(g.recording, isTrue);
      g.advance(const Duration(milliseconds: 80));
      g.handler.onKeyUp();
      g.advance(const Duration(seconds: 2));
      g.handler.onKeyDown();
      await _pump();
      expect(g.toggle, 1, reason: 'a single tap stops the latched recording');
      expect(g.recording, isFalse);
      g.handler.onKeyUp();
      expect(g.stop, 0, reason: 'release after the stop changes nothing');
    });

    test('Befund 3: a single tap alone starts nothing', () async {
      final g = _Gesture(pushToTalk: false, doubleTap: true, latch: true);
      g.handler.onKeyDown();
      g.advance(const Duration(milliseconds: 80));
      g.handler.onKeyUp();
      await _pump();
      expect(g.start, 0);
      expect(g.toggle, 0);
    });

    test(
      'Befund 5 / Grenzwerte: double-tap window 399 pairs, 400 and 401 do not',
      () async {
        for (final gap in [399, 400, 401]) {
          final g = _Gesture(pushToTalk: false, doubleTap: true, latch: true);
          g.handler.onKeyDown();
          g.advance(const Duration(milliseconds: 80));
          g.handler.onKeyUp();
          g.advance(Duration(milliseconds: gap));
          g.handler.onKeyDown();
          await _pump();
          expect(
            g.start,
            gap == 399 ? 1 : 0,
            reason: 'gap $gap ms after release',
          );
        }
      },
    );

    test(
      'Befund 4: action waits until the aborted recording is cancelled',
      () async {
        final gate = Completer<void>();
        final g = _Gesture(doubleTap: true)..cancelGate = () => gate.future;
        g.handler.onKeyDown();
        g.advance(const Duration(milliseconds: 80));
        g.handler.onKeyUp(); // short first tap: discard starts
        g.advance(const Duration(milliseconds: 150));
        g.handler.onKeyDown(); // second tap: action must wait for the discard
        await _pump();
        expect(g.cancel, 1);
        expect(g.action, 0, reason: 'no race with the still-running cancel');

        gate.complete();
        await _pump();
        expect(g.action, 1);
      },
    );

    test(
      'Befund 15: a press that did not start the recording never stops it',
      () async {
        final rejected = _Gesture()..startRejects = true;
        rejected.handler.onKeyDown();
        rejected.advance(const Duration(milliseconds: 1000));
        rejected.handler.onKeyUp();
        expect(rejected.stop, 0, reason: 'rejected start is not owned');

        final foreign = _Gesture()..recording = true;
        foreign.handler.onKeyDown();
        foreign.advance(const Duration(milliseconds: 1000));
        foreign.handler.onKeyUp();
        expect(foreign.stop, 0, reason: 'foreign recording is not ours');
        expect(foreign.recording, isTrue);
      },
    );

    test(
      'Befund 15: hybrid release during a slow start stops after it',
      () async {
        final gate = Completer<void>();
        final g = _Gesture(holdOrTap: true)..toggleGate = () => gate.future;
        g.handler.onKeyDown();
        g.advance(const Duration(milliseconds: 1500));
        g.handler.onKeyUp();
        await _pump();
        expect(g.stop, 0, reason: 'recording is not running yet');

        gate.complete();
        await _pump();
        expect(g.stop, 1, reason: 'the release is caught up once it runs');
        expect(g.recording, isFalse);
      },
    );

    test(
      'Befund 15: changing the threshold mid-press keeps the press state',
      () async {
        final g = _Gesture(holdOrTap: true);
        g.handler.onKeyDown();
        g.advance(const Duration(milliseconds: 100));
        g.thresholdMs = 1000;
        g.advance(const Duration(milliseconds: 300));
        g.handler.onKeyUp();
        await _pump();
        expect(g.stop, 1, reason: 'the press keeps its own threshold (250 ms)');
      },
    );

    test(
      'Befund 15: an externally ended latched recording resets the latch',
      () async {
        final g = _Gesture(doubleTap: true, latch: true);
        g.handler.onKeyDown();
        g.advance(const Duration(milliseconds: 80));
        g.handler.onKeyUp();
        g.advance(const Duration(milliseconds: 150));
        g.handler.onKeyDown();
        await _pump();
        expect(g.recording, isTrue, reason: 'hands-free recording latched');
        g.handler.onKeyUp();

        g.recording = false; // e.g. silence auto-stop
        g.advance(const Duration(seconds: 3));
        g.handler.onKeyDown();
        await _pump();
        expect(g.recording, isTrue, reason: 'a new press starts, not stops');
        g.advance(const Duration(seconds: 1));
        g.handler.onKeyUp();
        await _pump();
        expect(g.recording, isFalse);
      },
    );
  });
}

/// Lets queued microtasks and async handler work run.
Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Gesture harness: fake clock, fake recording state, optional async gates
/// (slow or rejected starts, a cancel that really takes time).
class _Gesture {
  _Gesture({
    this.pushToTalk = true,
    this.holdOrTap = false,
    this.doubleTap = false,
    this.latch = false,
  }) {
    handler = RecordingTriggerHandler(
      startRecording: () async {
        start++;
        if (startGate != null) await startGate!();
        if (!startRejects) recording = true;
      },
      stopRecording: () async {
        stop++;
        recording = false;
      },
      toggleRecording: () async {
        toggle++;
        final was = recording;
        if (toggleGate != null) await toggleGate!();
        recording = !was;
      },
      cancelRecording: () async {
        cancel++;
        if (cancelGate != null) await cancelGate!();
        recording = false;
      },
      onDoubleTap: () async {
        action++;
      },
      pushToTalkEnabled: () => pushToTalk,
      registrarSupportsKeyUp: () => supportsKeyUp,
      holdOrTapEnabled: () => holdOrTap,
      holdOrTapThresholdMs: () => thresholdMs,
      doubleTapEnabled: () => doubleTap,
      doubleTapLatches: () => latch,
      isRecording: () => recording,
      clock: () => _now,
    );
  }

  late final RecordingTriggerHandler handler;
  final bool pushToTalk;
  final bool holdOrTap;
  final bool doubleTap;
  final bool latch;
  final bool supportsKeyUp = true;
  int thresholdMs = 250;
  DateTime _now = DateTime(2026);
  bool recording = false;
  bool startRejects = false;
  Future<void> Function()? startGate;
  Future<void> Function()? toggleGate;
  Future<void> Function()? cancelGate;
  int start = 0;
  int stop = 0;
  int toggle = 0;
  int cancel = 0;
  int action = 0;

  void advance(Duration d) => _now = _now.add(d);
}

/// Hybrid-mode harness with a fake clock and a fake recording state, so tap
/// vs. hold is asserted deterministically instead of via real delays.
class _Hybrid {
  _Hybrid({bool pushToTalk = true, bool supportsKeyUp = true}) {
    handler = RecordingTriggerHandler(
      startRecording: () async {
        start++;
        recording = true;
      },
      stopRecording: () async {
        stop++;
        recording = false;
      },
      toggleRecording: () async {
        toggle++;
        if (recording) {
          recording = false;
        } else if (toggleStarts) {
          recording = true;
        }
      },
      pushToTalkEnabled: () => pushToTalk,
      registrarSupportsKeyUp: () => supportsKeyUp,
      holdOrTapEnabled: () => true,
      isRecording: () => recording,
      clock: () => _now,
    );
  }

  late final RecordingTriggerHandler handler;
  DateTime _now = DateTime(2026);
  bool recording = false;

  /// When false, toggle cannot start (mimics the orchestrator ignoring a
  /// press while the pipeline is still transcribing).
  bool toggleStarts = true;
  int start = 0;
  int stop = 0;
  int toggle = 0;

  void advance(Duration d) => _now = _now.add(d);
}

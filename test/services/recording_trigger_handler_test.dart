/// Unit tests for [RecordingTriggerHandler] — Push-to-Talk vs Toggle mode.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _Counters {
  int start = 0;
  int stop = 0;
  int toggle = 0;

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
    startRecording: () async => counters.start++,
    stopRecording: () async => counters.stop++,
    toggleRecording: () async => counters.toggle++,
    pushToTalkEnabled: () => pushToTalk,
    registrarSupportsKeyUp: () => supportsKeyUp,
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
        'T3: hold < 100 ms → startRecording only, no stopRecording',
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
          expect(c.stop, equals(0), reason: 'anti-glitch: held < 100 ms');
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

    test('threshold is ~300 ms', () {
      expect(threshold, const Duration(milliseconds: 300));
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

      h.advance(const Duration(milliseconds: 400));
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

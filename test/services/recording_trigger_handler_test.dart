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
}

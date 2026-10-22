/// Double-tap actions of the global hotkey.
///
/// Without hold the key carries only the double tap: the first tap starts
/// nothing, the second tap within the window runs the action. With push-to-
/// talk a short first tap is discarded silently and the second tap runs the
/// action; hands-free latches the recording instead.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int started;
  late int stopped;
  late int cancelled;
  late int actionRuns;
  late bool recording;
  late DateTime now;
  late RecordingTriggerHandler handler;

  void build({
    required bool pushToTalk,
    required bool latches,
    bool holdOrTap = false,
  }) {
    started = 0;
    stopped = 0;
    cancelled = 0;
    actionRuns = 0;
    recording = false;
    now = DateTime(2026, 10, 22);
    handler = RecordingTriggerHandler(
      startRecording: () async {
        started++;
        recording = true;
      },
      stopRecording: () async {
        stopped++;
        recording = false;
      },
      toggleRecording: () async {
        recording = !recording;
      },
      cancelRecording: () async {
        cancelled++;
        recording = false;
      },
      pushToTalkEnabled: () => pushToTalk,
      registrarSupportsKeyUp: () => true,
      holdOrTapEnabled: () => holdOrTap,
      doubleTapEnabled: () => true,
      doubleTapLatches: () => latches,
      onDoubleTap: () async {
        actionRuns++;
      },
      isRecording: () => recording,
      clock: () => now,
    );
  }

  void tapOnce({int heldMs = 40}) {
    handler.onKeyDown();
    now = now.add(Duration(milliseconds: heldMs));
    handler.onKeyUp();
  }

  group('double tap only (toggle mode)', () {
    test('the first tap starts nothing', () {
      build(pushToTalk: false, latches: false);

      tapOnce();

      expect(started, 0);
      expect(actionRuns, 0);
    });

    test('a second tap within the window runs the action', () {
      build(pushToTalk: false, latches: false);

      tapOnce();
      now = now.add(const Duration(milliseconds: 150));
      handler.onKeyDown();

      expect(actionRuns, 1);
      expect(started, 0);
    });

    test('a second tap after the window starts a new first tap', () {
      build(pushToTalk: false, latches: false);

      tapOnce();
      now = now.add(const Duration(milliseconds: 600));
      handler.onKeyDown();

      expect(actionRuns, 0);
    });

    test('a long press is no tap and does not pair with a later quick tap', () {
      build(pushToTalk: false, latches: false);

      tapOnce(heldMs: 400);
      now = now.add(const Duration(milliseconds: 100));
      handler.onKeyDown();

      expect(actionRuns, 0);
    });
  });

  group('push-to-talk with double tap', () {
    test(
      'a short first tap is discarded and the second tap runs the action',
      () {
        build(pushToTalk: true, latches: false);

        tapOnce();
        expect(started, 1, reason: 'the first press starts a recording');
        now = now.add(const Duration(milliseconds: 150));
        handler.onKeyDown();

        expect(cancelled, 1);
        expect(actionRuns, 1);
        expect(stopped, 0, reason: 'a discard is not a normal stop');
      },
    );

    test('hands-free latches the recording on the second tap instead', () {
      build(pushToTalk: true, latches: true);

      tapOnce();
      now = now.add(const Duration(milliseconds: 150));
      handler.onKeyDown();

      expect(actionRuns, 0);
      expect(cancelled, 0);
    });
  });
}

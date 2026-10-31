/// Double tap of the global hotkey (maintainer decision 2026-10-30).
///
/// A combination and a single key work alike: hold to dictate, double tap
/// for hands-free. In toggle mode a combination ignores the double tap (each
/// press toggles), while a single key keeps it, so a stray tap of the key
/// never starts a recording. Keys also used for typing and shortcuts start a
/// hold only after a short delay, and another key cancels it.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

/// Lets queued async handler work run.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int started;
  late int stopped;
  late int cancelled;
  late int actionRuns;
  late bool recording;
  late List<bool> handsFreeReports;
  late DateTime now;
  late RecordingTriggerHandler handler;

  void build({
    required bool pushToTalk,
    required bool latches,
    bool holdOrTap = false,
    bool singleKey = false,
    Duration holdStartDelay = Duration.zero,
  }) {
    started = 0;
    stopped = 0;
    cancelled = 0;
    actionRuns = 0;
    recording = false;
    handsFreeReports = [];
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
      singleKey: () => singleKey,
      holdStartDelay: () => holdStartDelay,
      onDoubleTap: () async {
        actionRuns++;
      },
      isRecording: () => recording,
      onHandsFreeChanged: handsFreeReports.add,
      clock: () => now,
    );
  }

  void tapOnce({int heldMs = 40}) {
    handler.onKeyDown();
    now = now.add(Duration(milliseconds: heldMs));
    handler.onKeyUp();
  }

  group('single key in toggle mode: double tap only', () {
    test('the first tap starts nothing', () {
      build(pushToTalk: false, latches: false, singleKey: true);

      tapOnce();

      expect(started, 0);
      expect(actionRuns, 0);
    });

    test('a second tap within the window runs the action', () {
      build(pushToTalk: false, latches: false, singleKey: true);

      tapOnce();
      now = now.add(const Duration(milliseconds: 150));
      handler.onKeyDown();

      expect(actionRuns, 1);
      expect(started, 0);
    });

    test('a second tap after the window starts a new first tap', () {
      build(pushToTalk: false, latches: false, singleKey: true);

      tapOnce();
      now = now.add(const Duration(milliseconds: 600));
      handler.onKeyDown();

      expect(actionRuns, 0);
    });

    test('a long press is no tap and does not pair with a later quick tap', () {
      build(pushToTalk: false, latches: false, singleKey: true);

      tapOnce(heldMs: 400);
      now = now.add(const Duration(milliseconds: 100));
      handler.onKeyDown();

      expect(actionRuns, 0);
    });

    test('a combination in toggle mode ignores the double tap: each press '
        'toggles', () async {
      build(pushToTalk: false, latches: true);

      tapOnce();
      await _settle();
      expect(recording, isTrue, reason: 'one press starts');
      now = now.add(const Duration(milliseconds: 150));
      tapOnce();
      await _settle();

      expect(recording, isFalse, reason: 'the next press stops');
      expect(actionRuns, 0);
    });
  });

  group('push-to-talk with double tap', () {
    test(
      'a short first tap is discarded and the second tap runs the action',
      () async {
        build(pushToTalk: true, latches: false);

        tapOnce();
        expect(started, 1, reason: 'the first press starts a recording');
        now = now.add(const Duration(milliseconds: 150));
        handler.onKeyDown();
        await _settle();

        expect(cancelled, 1);
        expect(actionRuns, 1);
        expect(stopped, 0, reason: 'a discard is not a normal stop');
      },
    );

    test(
      'hands-free latches a new recording on the second tap instead',
      () async {
        build(pushToTalk: true, latches: true);

        tapOnce();
        now = now.add(const Duration(milliseconds: 150));
        handler.onKeyDown();
        await _settle();

        expect(actionRuns, 0);
        expect(cancelled, 1, reason: 'the first short tap is discarded');
        expect(started, 2, reason: 'the second tap starts the latched one');
        expect(recording, isTrue);
      },
    );
  });

  group('single key as the dictation trigger', () {
    test('a double tap starts hands-free, the release keeps it, one tap '
        'stops it; both changes are reported', () async {
      build(pushToTalk: false, latches: true, singleKey: true);

      tapOnce();
      expect(started, 0, reason: 'a single tap starts nothing');
      now = now.add(const Duration(milliseconds: 150));
      tapOnce();
      await _settle();
      expect(recording, isTrue);
      expect(stopped, 0);
      expect(handsFreeReports, [true]);

      now = now.add(const Duration(seconds: 2));
      tapOnce();
      await _settle();

      expect(recording, isFalse);
      expect(started, 1);
      expect(handsFreeReports, [true, false]);
    });

    test('holding the key dictates until it is let go', () async {
      build(pushToTalk: true, latches: true, singleKey: true);

      handler.onKeyDown();
      await _settle();
      expect(recording, isTrue, reason: 'a right key starts on key-down');
      now = now.add(const Duration(milliseconds: 800));
      handler.onKeyUp();
      await _settle();

      expect(stopped, 1);
      expect(recording, isFalse);
    });

    test('a busy key starts only after the delay, so a quick shortcut '
        'records nothing', () {
      fakeAsync((async) {
        build(
          pushToTalk: true,
          latches: true,
          singleKey: true,
          holdStartDelay: const Duration(milliseconds: 250),
        );

        handler.onKeyDown();
        async.elapse(const Duration(milliseconds: 100));
        handler.onOtherKey();
        async.elapse(const Duration(milliseconds: 400));
        handler.onKeyUp();
        async.flushMicrotasks();

        expect(started, 0);
        expect(cancelled, 0);
        expect(stopped, 0);
      });
    });

    test(
      'a busy key held alone starts after the delay and stops on release',
      () {
        fakeAsync((async) {
          build(
            pushToTalk: true,
            latches: true,
            singleKey: true,
            holdStartDelay: const Duration(milliseconds: 250),
          );

          handler.onKeyDown();
          async.elapse(const Duration(milliseconds: 100));
          expect(started, 0, reason: 'still within the delay');
          async.elapse(const Duration(milliseconds: 300));
          expect(started, 1);
          now = now.add(const Duration(milliseconds: 800));
          handler.onKeyUp();
          async.flushMicrotasks();

          expect(stopped, 1);
          expect(recording, isFalse);
        });
      },
    );

    test('a busy key released before the delay records nothing', () {
      fakeAsync((async) {
        build(
          pushToTalk: true,
          latches: true,
          singleKey: true,
          holdStartDelay: const Duration(milliseconds: 250),
        );

        handler.onKeyDown();
        async.elapse(const Duration(milliseconds: 150));
        now = now.add(const Duration(milliseconds: 150));
        handler.onKeyUp();
        async.elapse(const Duration(milliseconds: 400));

        expect(started, 0);
        expect(stopped, 0);
      });
    });

    test('a shortcut is no tap: ⌘C, ⌘V does not start hands-free', () async {
      build(pushToTalk: true, latches: true, singleKey: true);

      handler.onKeyDown();
      handler.onOtherKey();
      now = now.add(const Duration(milliseconds: 40));
      handler.onKeyUp();
      now = now.add(const Duration(milliseconds: 150));
      handler.onKeyDown();
      handler.onOtherKey();
      now = now.add(const Duration(milliseconds: 40));
      handler.onKeyUp();
      await _settle();

      expect(recording, isFalse);
    });
  });
}

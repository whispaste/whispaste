/// Central gate for every nudge dialog (growth review R-11).
///
/// A nudge may open only when no dictation is running and the user has been
/// idle inside the app for at least [kNudgeIdleThreshold]. Time is driven by
/// a fake clock so the rules are checked without real waiting.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/nudge_gate.dart';

void main() {
  final start = DateTime(2026, 10, 19, 12);

  group('decideNudge', () {
    test('allows a nudge after 30 s without input and no dictation', () {
      final decision = decideNudge(
        dictationBusy: false,
        now: start.add(const Duration(seconds: 30)),
        lastInputAt: start,
      );
      expect(decision, isA<NudgeAllow>());
    });

    test('waits the remaining idle time when input was recent', () {
      final decision = decideNudge(
        dictationBusy: false,
        now: start.add(const Duration(seconds: 10)),
        lastInputAt: start,
      );
      expect(decision, isA<NudgeWait>());
      expect((decision as NudgeWait).after, const Duration(seconds: 20));
    });

    test('never allows while a dictation is busy, even when idle', () {
      final decision = decideNudge(
        dictationBusy: true,
        now: start.add(const Duration(minutes: 5)),
        lastInputAt: start,
      );
      expect(decision, isA<NudgeWait>());
      expect((decision as NudgeWait).after, kNudgeBusyRecheck);
    });
  });

  group('NudgeGate.whenAllowed', () {
    test('completes only after 30 s of idle time and no dictation', () {
      fakeAsync((async) {
        const busy = false;
        final gate = NudgeGate(
          clock: () => start.add(async.elapsed),
          isDictationBusy: () => busy,
        );
        var done = false;
        gate.whenAllowed().then((_) => done = true);

        async.elapse(const Duration(seconds: 29));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(done, isTrue);
      });
    });

    test('waits while a dictation runs, then completes after it ends', () {
      fakeAsync((async) {
        var busy = true;
        final gate = NudgeGate(
          clock: () => start.add(async.elapsed),
          isDictationBusy: () => busy,
        );
        var done = false;
        gate.whenAllowed().then((_) => done = true);

        async.elapse(const Duration(minutes: 2));
        expect(done, isFalse);

        busy = false;
        async.elapse(kNudgeBusyRecheck);
        expect(done, isTrue);
      });
    });

    test('input restarts the idle window', () {
      fakeAsync((async) {
        final gate = NudgeGate(
          clock: () => start.add(async.elapsed),
          isDictationBusy: () => false,
        );
        var done = false;
        gate.whenAllowed().then((_) => done = true);

        async.elapse(const Duration(seconds: 20));
        gate.noteInput(start.add(async.elapsed));
        async.elapse(const Duration(seconds: 25));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 5));
        expect(done, isTrue);
      });
    });
  });

  group('NudgeGate.dispose', () {
    test('cancels the re-check timer of a pending wait', () {
      fakeAsync((async) {
        final gate = NudgeGate(clock: () => start, isDictationBusy: () => true);
        var done = false;
        gate.whenAllowed().then((_) => done = true);
        expect(async.pendingTimers, isNotEmpty);

        gate.dispose();

        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(minutes: 1));
        expect(done, isFalse);
      });
    });
  });
}

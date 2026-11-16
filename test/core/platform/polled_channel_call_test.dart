/// Logic tests for [PolledChannelCall]: deadline, single-flight and the
/// stuck-read guard. A send that never completes stands in for a native
/// reply that never arrives. Simulated time only (fakeAsync), no real waits.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/platform/polled_channel_call.dart';

void main() {
  const timeout = Duration(seconds: 5);

  test('an answer inside the deadline is returned', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      PolledCallResult<int>? result;
      unawaited(call.run(() async => 7).then((r) => result = r));
      async.flushMicrotasks();
      expect(result?.status, PolledCallStatus.answered);
      expect(result?.value, 7);
      expect(call.unansweredCalls, 0);
    });
  });

  test('a silent native side times out and the slot is released', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      PolledCallResult<int>? result;
      unawaited(
        call.run(() => Completer<int>().future).then((r) => result = r),
      );
      async.elapse(timeout + const Duration(milliseconds: 1));
      expect(result?.status, PolledCallStatus.timedOut);
      expect(result?.value, isNull);
      // The native call is still outstanding and is counted as such.
      expect(call.unansweredCalls, 1);
    });
  });

  test('overlapping calls are skipped while one is running', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      var sends = 0;
      final never = Completer<int>();
      unawaited(
        call.run(() {
          sends++;
          return never.future;
        }),
      );
      PolledCallResult<int>? second;
      unawaited(
        call
            .run(() {
              sends++;
              return never.future;
            })
            .then((r) => second = r),
      );
      async.flushMicrotasks();
      expect(second?.status, PolledCallStatus.skipped);
      expect(sends, 1);
    });
  });

  test('after a timeout no further send happens while the read stays stuck; '
      'a poll that would have stacked is skipped', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      var sends = 0;
      final never = Completer<int>();
      Future<int> send() {
        sends++;
        return never.future;
      }

      // Poll every 2 s for a minute, as the secure-input monitor does.
      final statuses = <PolledCallStatus>[];
      final timer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(call.run(send).then((r) => statuses.add(r.status)));
      });
      async.elapse(const Duration(minutes: 1));
      timer.cancel();
      async.flushMicrotasks();

      expect(sends, 1, reason: 'a stuck read must not stack new handles');
      expect(call.unansweredCalls, 1);
      // Completion order: the immediate skips land before the timeout.
      expect(
        statuses.where((s) => s == PolledCallStatus.timedOut),
        hasLength(1),
      );
      expect(
        statuses.where((s) => s == PolledCallStatus.skipped),
        hasLength(statuses.length - 1),
      );
    });
  });

  test('once the stuck read answers, the next poll sends again', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      var sends = 0;
      final first = Completer<int>();
      unawaited(
        call.run(() {
          sends++;
          return first.future;
        }),
      );
      async.elapse(timeout + const Duration(seconds: 1));
      expect(call.unansweredCalls, 1);

      first.complete(1);
      async.flushMicrotasks();
      expect(call.unansweredCalls, 0);

      PolledCallResult<int>? result;
      unawaited(
        call
            .run(() {
              sends++;
              return Future.value(2);
            })
            .then((r) => result = r),
      );
      async.flushMicrotasks();
      expect(sends, 2);
      expect(result?.status, PolledCallStatus.answered);
      expect(result?.value, 2);
    });
  });

  test('a forced call (user prompt) is sent even while a read is stuck', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      var sends = 0;
      unawaited(
        call.run(() {
          sends++;
          return Completer<int>().future;
        }),
      );
      async.elapse(timeout + const Duration(seconds: 1));

      unawaited(
        call.run(() {
          sends++;
          return Completer<int>().future;
        }, force: true),
      );
      async.flushMicrotasks();
      expect(sends, 2);
    });
  });

  test('a forced call is sent while a read is still in flight; each caller '
      'gets its own answer and dispose ends both deadlines', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      final read = Completer<int>();
      final prompt = Completer<int>();
      PolledCallResult<int>? readResult;
      PolledCallResult<int>? promptResult;
      unawaited(call.run(() => read.future).then((r) => readResult = r));
      unawaited(
        call
            .run(() => prompt.future, force: true)
            .then((r) => promptResult = r),
      );
      async.flushMicrotasks();
      expect(call.unansweredCalls, 2);
      // Per sent call: its deadline and its stale-warning timer.
      expect(async.pendingTimers, hasLength(4));

      prompt.complete(7);
      async.flushMicrotasks();
      expect(promptResult?.status, PolledCallStatus.answered);
      expect(promptResult?.value, 7);
      expect(readResult, isNull);

      call.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
      expect(readResult?.status, PolledCallStatus.timedOut);
    });
  });

  test('a failing send propagates its error to the caller', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      Object? error;
      unawaited(() async {
        try {
          await call.run(() => Future<int>.error(StateError('boom')));
        } on Object catch (e) {
          error = e;
        }
      }());
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(call.unansweredCalls, 0);
    });
  });

  test('dispose cancels the pending deadline and releases the waiter', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      PolledCallResult<int>? result;
      unawaited(
        call.run(() => Completer<int>().future).then((r) => result = r),
      );
      async.flushMicrotasks();
      // The deadline and the stale-warning timer.
      expect(async.pendingTimers, hasLength(2));

      call.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
      expect(result?.status, PolledCallStatus.timedOut);
    });
  });

  test('a call after dispose is skipped and starts no timer', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      call.dispose();
      PolledCallResult<int>? result;
      unawaited(call.run(() async => 1).then((r) => result = r));
      async.flushMicrotasks();
      expect(result?.status, PolledCallStatus.skipped);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a call never answered warns once after a long silence', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(
        timeout: timeout,
        staleWarnAfter: const Duration(minutes: 5),
      );
      unawaited(call.run(() => Completer<int>().future));
      async.elapse(const Duration(minutes: 4));
      expect(call.staleWarnings, 0);
      async.elapse(const Duration(minutes: 1, seconds: 1));
      expect(call.staleWarnings, 1);
      // Skipped polls and more silence add no further warning.
      unawaited(call.run(() async => 1));
      async.elapse(const Duration(hours: 1));
      expect(call.staleWarnings, 1);
    });
  });

  test('an answered call never warns', () {
    fakeAsync((async) {
      final call = PolledChannelCall<int>(timeout: timeout);
      unawaited(call.run(() async => 1));
      async.elapse(const Duration(hours: 1));
      expect(call.staleWarnings, 0);
    });
  });
}

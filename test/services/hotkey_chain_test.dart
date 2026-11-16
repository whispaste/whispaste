/// #293 (F33-4, F33-5): one hotkey-chain step at a time, also past the limit;
/// the limit aborts the step and answers its caller; quit answers everyone.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hotkey_chain.dart';

const _limit = Duration(seconds: 60);

void main() {
  test('a step past the limit is aborted, its caller answered, and the next '
      'step still waits for its end', () {
    FakeAsync().run((async) {
      final chain = HotkeyChain(limit: _limit);
      var inFlight = 0;
      var maxInFlight = 0;
      late ChainStep first;
      String? firstResult;
      String? secondResult;

      Future<String> work(Duration d, String name) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(d);
        inFlight--;
        return name;
      }

      unawaited(
        chain
            .run(
              (step) {
                first = step;
                return work(const Duration(seconds: 70), 'first');
              },
              onLimit: () => 'limit',
              aborted: 'aborted',
            )
            .then((r) => firstResult = r),
      );
      unawaited(
        chain
            .run(
              (_) => work(const Duration(seconds: 1), 'second'),
              onLimit: () => 'limit',
              aborted: 'aborted',
            )
            .then((r) => secondResult = r),
      );

      async.elapse(const Duration(seconds: 61));
      expect(firstResult, 'limit');
      expect(first.aborted, isTrue);
      expect(secondResult, isNull);

      async.elapse(const Duration(seconds: 15));
      expect(secondResult, 'second');
      expect(maxInFlight, 1);
    });
  });

  test('a step that never ends holds the chain for twice the limit, then '
      'the next step runs', () {
    FakeAsync().run((async) {
      final stuck = <String>[];
      final chain = HotkeyChain(limit: _limit, onStuck: stuck.add);
      var secondDone = false;

      unawaited(
        chain.run(
          (_) => Completer<void>().future,
          onLimit: () {},
          aborted: null,
        ),
      );
      unawaited(
        chain
            .run((_) async {}, onLimit: () {}, aborted: null)
            .then((_) => secondDone = true),
      );

      async.elapse(const Duration(seconds: 119));
      expect(secondDone, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(secondDone, isTrue);
      expect(stuck, hasLength(1));
    });
  });

  test('close answers the running and every waiting caller and leaves no '
      'timer', () {
    FakeAsync().run((async) {
      final chain = HotkeyChain(limit: _limit);
      final results = <String>[];
      late ChainStep running;
      var laterStarted = false;

      unawaited(
        chain
            .run(
              (step) {
                running = step;
                return Completer<String>().future;
              },
              onLimit: () => 'limit',
              aborted: 'aborted',
            )
            .then(results.add),
      );
      for (var i = 0; i < 2; i++) {
        unawaited(
          chain
              .run(
                (_) async {
                  laterStarted = true;
                  return 'ran';
                },
                onLimit: () => 'limit',
                aborted: 'aborted',
              )
              .then(results.add),
        );
      }
      async.elapse(const Duration(seconds: 1));

      chain.close();
      async.flushMicrotasks();
      expect(results, ['aborted', 'aborted', 'aborted']);
      expect(running.aborted, isTrue);
      expect(async.pendingTimers, isEmpty);

      String? afterClose;
      unawaited(
        chain
            .run((_) async => 'ran', onLimit: () => 'limit', aborted: 'aborted')
            .then((r) => afterClose = r),
      );
      async.flushMicrotasks();
      expect(afterClose, 'aborted');
      expect(laterStarted, isFalse);
    });
  });

  test('an error reaches its caller and the chain goes on', () {
    FakeAsync().run((async) {
      final chain = HotkeyChain(limit: _limit);
      Object? error;
      String? next;

      unawaited(
        chain
            .run<String>(
              (_) async => throw StateError('native'),
              onLimit: () => 'limit',
              aborted: 'aborted',
            )
            .catchError((Object e) {
              error = e;
              return 'caught';
            }),
      );
      unawaited(
        chain
            .run(
              (_) async => 'next',
              onLimit: () => 'limit',
              aborted: 'aborted',
            )
            .then((r) => next = r),
      );
      async.flushMicrotasks();

      expect(error, isA<StateError>());
      expect(next, 'next');
      expect(async.pendingTimers, isEmpty);
    });
  });
}

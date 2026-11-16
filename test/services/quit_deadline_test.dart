/// Hard deadline for quit paths: an orderly shutdown that never finishes must
/// not keep the process alive (SIGTERM, tray "Beenden", Cmd+Q, the window's
/// X when close means quit, "Quit" in the first-run close dialog, #1609).
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/quit_deadline.dart';

void main() {
  test('a shutdown step that never completes is cut off at the deadline', () {
    fakeAsync((async) {
      var hardExits = 0;
      final hanging = Completer<void>(); // a step waiting on a future forever
      unawaited(
        shutdownWithHardDeadline(
          orderlyShutdown: () => hanging.future,
          hardExit: () => hardExits++,
        ),
      );

      async.elapse(const Duration(milliseconds: 2900));
      expect(hardExits, 0, reason: 'not before the deadline');

      async.elapse(const Duration(milliseconds: 200));
      expect(hardExits, 1, reason: 'hard exit at 3 s');
      expect(kQuitHardDeadline, const Duration(seconds: 3));
    });
  });

  test('a finished orderly shutdown does not hard-exit', () {
    fakeAsync((async) {
      var hardExits = 0;
      var finished = false;
      unawaited(
        shutdownWithHardDeadline(
          orderlyShutdown: () async {},
          hardExit: () => hardExits++,
        ).then((_) => finished = true),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));

      expect(finished, isTrue);
      expect(hardExits, 0);
    });
  });

  test('a failing orderly shutdown is not turned into a hard exit', () {
    fakeAsync((async) {
      var hardExits = 0;
      var finished = false;
      unawaited(
        shutdownWithHardDeadline(
          orderlyShutdown: () async => throw StateError('db closed twice'),
          hardExit: () => hardExits++,
        ).then((_) => finished = true),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));

      expect(finished, isTrue);
      expect(
        hardExits,
        0,
        reason: 'errors end the orderly path, not the process',
      );
    });
  });

  group('QuitOnce (window X, first-run "Quit", tray, #1609)', () {
    test('a hanging window quit is cut off at the deadline', () {
      fakeAsync((async) {
        final quit = QuitOnce();
        var hardExits = 0;
        final hanging = Completer<void>();
        unawaited(
          quit.run(
            orderlyShutdown: () => hanging.future,
            hardExit: () => hardExits++,
          ),
        );
        expect(quit.isRunning, isTrue);

        async.elapse(const Duration(milliseconds: 2900));
        expect(hardExits, 0, reason: 'not before the deadline');

        async.elapse(const Duration(milliseconds: 200));
        expect(hardExits, 1, reason: 'hard exit at 3 s');
      });
    });

    test('a second request during a hanging quit joins it', () {
      fakeAsync((async) {
        final quit = QuitOnce();
        var orderlyRuns = 0;
        var hardExits = 0;
        final hanging = Completer<void>();
        Future<void> orderly() {
          orderlyRuns++;
          return hanging.future;
        }

        unawaited(
          quit.run(orderlyShutdown: orderly, hardExit: () => hardExits++),
        );
        async.elapse(const Duration(seconds: 1));
        // A second click on the X one second later.
        unawaited(
          quit.run(orderlyShutdown: orderly, hardExit: () => hardExits++),
        );
        async.elapse(const Duration(milliseconds: 2100));
        expect(hardExits, 1, reason: 'at 3 s after the first request');

        async.elapse(const Duration(seconds: 10));
        expect(orderlyRuns, 1, reason: 'no second shutdown');
        expect(hardExits, 1, reason: 'one hard exit only');
      });
    });

    test('a finished quit frees the slot and does not hard-exit', () {
      fakeAsync((async) {
        final quit = QuitOnce();
        var hardExits = 0;
        unawaited(
          quit.run(orderlyShutdown: () async {}, hardExit: () => hardExits++),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));

        expect(quit.isRunning, isFalse);
        expect(hardExits, 0);
      });
    });
  });
}

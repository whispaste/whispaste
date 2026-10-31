/// Hard deadline for quit paths: an orderly shutdown that never finishes must
/// not keep the process alive (SIGTERM, tray "Beenden", Cmd+Q).
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
}

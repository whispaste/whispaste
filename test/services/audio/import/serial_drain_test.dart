/// F31-4: work added while the previous drain is finishing (it has returned,
/// but its future has not completed yet) is drained too, and the caller that
/// added it is not told it is finished while it is still waiting.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';

void main() {
  test(
    'a run requested in the finishing window still drains its work',
    () async {
      // Sweep the depth of the microtask chain, so one of them lands between
      // the drain returning and its future completing.
      for (var depth = 0; depth < 8; depth++) {
        final pending = <int>[1];
        final done = <int>[];
        late SerialDrain drain;
        Future<void>? lateRun;
        var lateDone = false;
        var scheduled = false;

        void afterMicrotasks(int n, void Function() action) {
          if (n == 0) return action();
          scheduleMicrotask(() => afterMicrotasks(n - 1, action));
        }

        drain = SerialDrain(() async {
          while (pending.isNotEmpty) {
            await Future<void>.value();
            done.add(pending.removeAt(0));
          }
          if (!scheduled) {
            scheduled = true;
            afterMicrotasks(depth, () {
              pending.add(2);
              lateRun = drain.run().then((_) {
                lateDone = true;
                // Nothing the late caller added may still be waiting.
                expect(pending, isEmpty, reason: 'depth $depth');
              });
            });
          }
        }, hasPending: () => pending.isNotEmpty);

        await drain.run();
        // Let the microtask chain finish before looking at the late run.
        await pumpEventQueue();
        await lateRun;

        expect(lateDone, isTrue, reason: 'depth $depth');
        expect(done, [1, 2], reason: 'depth $depth');
        expect(pending, isEmpty, reason: 'depth $depth');
      }
    },
  );
}

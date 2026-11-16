import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/connection_return_watcher.dart';

void main() {
  group('ConnectionReturnWatcher', () {
    test('reports exactly once when the probe succeeds', () {
      fakeAsync((async) {
        final answers = <bool>[false, false, true, true];
        var probes = 0;
        var reports = 0;
        final watcher = ConnectionReturnWatcher(
          probe: () async => answers[probes++],
          onReturned: () => reports++,
        )..start();

        async.elapse(kConnectionProbeInterval * 2);
        expect(probes, 2);
        expect(reports, 0);
        expect(watcher.isRunning, isTrue);

        async.elapse(kConnectionProbeInterval);
        expect(reports, 1);
        expect(watcher.isRunning, isFalse);

        // The timer is gone: no further probe, no second report.
        async.elapse(kConnectionProbeInterval * 5);
        expect(probes, 3);
        expect(reports, 1);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('stop leaves no timer and never reports', () {
      fakeAsync((async) {
        var reports = 0;
        final watcher = ConnectionReturnWatcher(
          probe: () async => true,
          onReturned: () => reports++,
        )..start();
        expect(async.pendingTimers, hasLength(1));

        watcher.stop();
        async.elapse(kConnectionProbeInterval * 3);

        expect(async.pendingTimers, isEmpty);
        expect(reports, 0);
      });
    });

    test('a probe that finishes after stop is ignored', () {
      fakeAsync((async) {
        var reports = 0;
        late ConnectionReturnWatcher watcher;
        watcher = ConnectionReturnWatcher(
          probe: () async {
            watcher.stop();
            return true;
          },
          onReturned: () => reports++,
        )..start();

        async.elapse(kConnectionProbeInterval);

        expect(reports, 0);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a throwing probe counts as still offline', () {
      fakeAsync((async) {
        var probes = 0;
        var reports = 0;
        final watcher = ConnectionReturnWatcher(
          probe: () async {
            probes++;
            if (probes == 1) throw StateError('resolver down');
            return true;
          },
          onReturned: () => reports++,
        )..start();

        async.elapse(kConnectionProbeInterval * 2);

        expect(probes, 2);
        expect(reports, 1);
        watcher.stop();
      });
    });
  });
}

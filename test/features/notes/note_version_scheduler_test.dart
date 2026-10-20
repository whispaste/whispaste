/// Snapshot triggers for note versions (WP-31a): explicit save snapshots at
/// once, idle snapshots wait for a quiet period, and every edit restarts it.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_version_scheduler.dart';

void main() {
  test('an idle snapshot fires once after the quiet period', () {
    fakeAsync((async) {
      final saved = <String>[];
      final scheduler = NoteVersionScheduler(
        onSnapshot: (id) async => saved.add(id),
      );

      scheduler.touch('n1');
      async.elapse(const Duration(seconds: 29));
      expect(saved, isEmpty);
      expect(scheduler.hasPending, isTrue);

      async.elapse(const Duration(seconds: 2));
      expect(saved, ['n1']);
      expect(scheduler.hasPending, isFalse);
    });
  });

  test('every edit restarts the idle timer: one snapshot for a burst', () {
    fakeAsync((async) {
      final saved = <String>[];
      final scheduler = NoteVersionScheduler(
        onSnapshot: (id) async => saved.add(id),
      );

      for (var i = 0; i < 10; i++) {
        scheduler.touch('n1');
        async.elapse(const Duration(seconds: 10));
      }
      expect(saved, isEmpty, reason: 'still typing, no pause yet');

      async.elapse(const Duration(seconds: 30));
      expect(saved, ['n1']);
    });
  });

  test(
    'snapshotNow stores immediately and drops the pending idle snapshot',
    () {
      fakeAsync((async) {
        final saved = <String>[];
        final scheduler = NoteVersionScheduler(
          onSnapshot: (id) async => saved.add(id),
        );

        scheduler.touch('n1');
        scheduler.snapshotNow('n1');
        expect(saved, ['n1']);

        async.elapse(const Duration(minutes: 5));
        expect(saved, ['n1'], reason: 'no second snapshot from the timer');
      });
    },
  );

  test('dispose cancels a pending idle snapshot', () {
    fakeAsync((async) {
      final saved = <String>[];
      final scheduler = NoteVersionScheduler(
        onSnapshot: (id) async => saved.add(id),
      );

      scheduler.touch('n1');
      scheduler.dispose();
      async.elapse(const Duration(minutes: 5));
      expect(saved, isEmpty);
    });
  });

  test('a custom idle delay is honoured', () {
    fakeAsync((async) {
      final saved = <String>[];
      final scheduler = NoteVersionScheduler(
        onSnapshot: (id) async => saved.add(id),
        idleDelay: const Duration(seconds: 2),
      );

      scheduler.touch('n1');
      async.elapse(const Duration(seconds: 2));
      expect(saved, ['n1']);
    });
  });
}

/// Textbausteine go through the single-writer coordinator for create, change,
/// delete-all, delete and restore (#459). A lock taken inside a lock would wait
/// on itself, so every case runs on simulated time and must finish without
/// the clock moving past the coordinator's own retry schedule.
library;

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Runs [body] on simulated time. Only microtasks and zero-length timers
  /// are drained, never a retry backoff, so a write that waits on its own lock
  /// stays incomplete and fails the expectation.
  void finishes(Future<void> Function() body) {
    var done = false;
    Object? error;
    fakeAsync((async) {
      body().then(
        (_) => done = true,
        onError: (Object e) {
          error = e;
          return false;
        },
      );
      for (var i = 0; i < 50 && !done && error == null; i++) {
        async.flushMicrotasks();
        async.elapse(Duration.zero);
      }
    });
    expect(error, isNull);
    expect(
      done,
      isTrue,
      reason:
          'not finished after the microtask drain (a write waiting on its own lock)',
    );
  }

  test('create and change with fields complete in one pass', () async {
    final created = DateTime(2026, 11, 4);
    await db.upsertSnippetWithFields(
      id: 's1',
      title: 'Address',
      body: '{{name}} {{street}}',
      createdAt: created,
      kind: 'interactive',
      fieldNames: ['name', 'street'],
    );
    await db.upsertSnippetWithFields(
      id: 's1',
      title: 'Address 2',
      body: '{{street}}',
      createdAt: created,
      kind: 'interactive',
      fieldNames: ['street'],
    );
    final stored = (await db.readSnippetWithFields('s1'))!;
    expect(stored.row.title, 'Address 2');
    expect(stored.fields, ['street']);
  });

  test('delete, restore, replace fields and delete-all never wait on their own '
      'lock', () {
    final created = DateTime(2026, 11, 4);
    finishes(() async {
      await db.upsertSnippetWithFields(
        id: 's1',
        title: 'A',
        body: '{{x}}',
        createdAt: created,
        kind: 'interactive',
        fieldNames: ['x'],
      );
      final before = (await db.readSnippetWithFields('s1'))!;
      await db.deleteSnippet('s1');
      expect(await db.readSnippetWithFields('s1'), isNull);
      expect(await db.readSnippetFields('s1'), isEmpty);
      await db.restoreSnippet(before);
      final after = (await db.readSnippetWithFields('s1'))!;
      expect(after.row, before.row);
      expect(after.fields, ['x']);
      await db.upsertSnippet(
        id: 's2',
        title: 'B',
        body: 'b',
        createdAt: created,
      );
      await db.replaceSnippetFields(snippetId: 's1', fieldNames: ['y', 'z']);
      expect((await db.readSnippetWithFields('s1'))!.fields, ['y', 'z']);
      await db.deleteAllSnippets();
      expect(await db.readAllSnippets(), isEmpty);
      expect(await db.readSnippetFields('s1'), isEmpty);
    });
  });

  test('app meta round-trips after snippet writes', () async {
    await db.upsertSnippet(
      id: 's1',
      title: 'A',
      body: 'a',
      createdAt: DateTime(2026, 11, 4),
    );
    await db.writeAppMeta('k', 'v');
    expect(await db.readAppMeta('k'), 'v');
    await db.writeAppMeta('k', 'w');
    expect(await db.readAppMeta('k'), 'w');
    expect(await db.readAppMeta('missing'), isNull);
  });
}

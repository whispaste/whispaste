import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/index_maintenance.dart';

/// #668: the derived indexes heal on open and rebuild on demand; the user
/// texts are only read.
void main() {
  test('transient search failures never mark the index damaged', () {
    // Include extended IOERR_READ and BUSY_SNAPSHOT result codes.
    for (final code in [5, 6, 7, 10, 13, 14, 266, 517]) {
      expect(
        isSearchIndexFailure(
          SqliteException(
            extendedResultCode: code,
            message: 'cannot access history_fts',
          ),
        ),
        isFalse,
        reason: 'SQLite code $code is not evidence of index damage',
      );
    }
    for (final (code, message) in [
      (11, 'database disk image is malformed'),
      (267, 'database disk image is malformed'),
      (1, 'no such table: history_fts'),
    ]) {
      expect(
        isSearchIndexFailure(
          SqliteException(extendedResultCode: code, message: message),
        ),
        isTrue,
      );
    }
    expect(
      isSearchIndexFailure(
        SqliteException(extendedResultCode: 1, message: 'invalid query'),
      ),
      isFalse,
    );
  });

  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_index_rebuild_');
    file = File('${dir.path}/history.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryDatabase open() => HistoryDatabase.forTesting(NativeDatabase(file));

  Future<void> save(HistoryDatabase db, String id, String text, int day) =>
      db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: id,
          timestamp: DateTime(2026, 1, day),
          content: Value(text),
        ),
      );

  Future<List<String>> texts(HistoryDatabase db) async =>
      (await db
              .customSelect(
                'SELECT id, content FROM history_entries ORDER BY id',
              )
              .get())
          .map((r) => '${r.read<String>('id')}:${r.data['content']}')
          .toList();

  Future<Set<String>> found(HistoryDatabase db, String q) async =>
      (await db.searchEntries(q)).map((e) => e.id).toSet();

  Future<void> seed() async {
    final db = open();
    await save(db, 'a', 'alpha apple', 1);
    await save(db, 'b', 'beta apple', 2);
    await db.close();
  }

  for (final (name, breakIt) in <(String, String)>[
    ('missing', 'DROP TABLE history_fts'),
    ('missing trigger', 'DROP TRIGGER history_fts_ai'),
    (
      'corrupt segment with unchanged document count',
      "UPDATE history_fts_data SET block = X'00' WHERE id > 10",
    ),
    (
      'reported corrupt',
      "INSERT INTO app_meta (key, value) VALUES ('$kSearchIndexDamagedKey', '1')",
    ),
  ]) {
    test('$name search index is rebuilt on open and reported', () async {
      await seed();
      final broken = open();
      final before = await texts(broken);
      await broken.customStatement(breakIt);
      if (name == 'corrupt segment with unchanged document count') {
        // Prove this fixture evades the former count-only health check.
        final count = await broken
            .customSelect('SELECT COUNT(*) AS n FROM history_fts_docsize')
            .getSingle();
        expect(count.read<int>('n'), before.length);
      }
      await broken.close();

      final db = open();
      addTearDown(db.close);
      expect(await found(db, 'apple'), {'a', 'b'});
      expect(db.indexesRepairedOnOpen, isTrue);
      expect(await texts(db), before);
    });
  }

  test('equal counts with an orphaned document rebuild on open', () async {
    await seed();
    final broken = open();
    final before = await broken
        .customSelect('SELECT * FROM history_entries ORDER BY id')
        .get();
    // A valid FTS index with the right count but the wrong document identity.
    // SQLite's own integrity check passes, yet searching would lose entry a.
    await broken.customStatement("""
      INSERT INTO history_fts(history_fts, rowid, title, content, tags)
      SELECT 'delete', rowid, title, content, tags
      FROM history_entries WHERE id = 'a'
    """);
    await broken.customStatement("""
      INSERT INTO history_fts(rowid, title, content, tags)
      SELECT 9999, title, content, tags FROM history_entries WHERE id = 'a'
    """);
    await broken.customStatement(
      "INSERT INTO history_fts(history_fts) VALUES ('integrity-check')",
    );
    final indexed = await broken
        .customSelect('SELECT COUNT(*) AS n FROM history_fts_docsize')
        .getSingle();
    expect(indexed.read<int>('n'), before.length);
    expect(await found(broken, 'apple'), {'b'});
    await broken.close();

    final db = open();
    addTearDown(db.close);
    expect(await found(db, 'apple'), {'a', 'b'});
    expect(db.indexesRepairedOnOpen, isTrue);
    final after = await db
        .customSelect('SELECT * FROM history_entries ORDER BY id')
        .get();
    expect(after.map((r) => r.data), before.map((r) => r.data));
    await db.close();

    final reopened = open();
    addTearDown(reopened.close);
    expect(await found(reopened, 'apple'), {'a', 'b'});
    expect(reopened.indexesRepairedOnOpen, isFalse);
  });

  test('healthy index is left alone and not reported', () async {
    await seed();
    final db = open();
    addTearDown(db.close);
    expect(await found(db, 'apple'), {'a', 'b'});
    expect(db.indexesRepairedOnOpen, isFalse);
  });

  test('outdated layout version rebuilds silently', () async {
    await seed();
    final old = open();
    await old.customStatement(
      'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)',
      [kSearchIndexVersionKey, '0'],
    );
    await old.close();
    final db = open();
    addTearDown(db.close);
    expect(await found(db, 'apple'), {'a', 'b'});
    expect(db.indexesRepairedOnOpen, isFalse);
  });

  test(
    'manual rebuild reports progress, keeps texts and live triggers',
    () async {
      await seed();
      final db = open();
      addTearDown(db.close);
      final before = await texts(db);

      final steps = await db.rebuildIndexes().toList();
      final search = steps.where((p) => p.phase == IndexRebuildPhase.search);
      expect(
        search.last,
        const IndexRebuildProgress(IndexRebuildPhase.search, 2, 2),
      );
      expect(steps.last.phase, IndexRebuildPhase.done);
      expect(await texts(db), before);
      expect(await found(db, 'apple'), {'a', 'b'});

      // The recreated triggers keep the index in step with later changes.
      await save(db, 'c', 'gamma apple', 3);
      await save(db, 'a', 'alpha pear', 1);
      await db.customStatement("DELETE FROM history_entries WHERE id = 'b'");
      expect(await found(db, 'apple'), {'c'});
      expect(await found(db, 'pear'), {'a'});
    },
  );
  test('stalled previews report failure without a success event', () async {
    final db = open();
    addTearDown(db.close);
    await save(db, 'a', 'unchanged text', 1);
    final before = await texts(db);
    final maintenance = IndexMaintenance(db, (action) => action());
    final steps = <IndexRebuildProgress>[];
    await expectLater(
      maintenance
          .rebuild(
            resetPreview: () async {},
            previewCounts: () async => (1, 1),
            poll: const Duration(milliseconds: 1),
            stall: Duration.zero,
          )
          .forEach(steps.add),
      throwsA(isA<TimeoutException>()),
    );
    expect(steps.any((p) => p.phase == IndexRebuildPhase.done), isFalse);
    expect(await texts(db), before);
  });

  test('search failure does not reset previews or report success', () async {
    final db = open();
    addTearDown(db.close);
    var reset = false;
    final maintenance = IndexMaintenance(
      db,
      (_) async => throw StateError('write failed'),
    );
    final steps = <IndexRebuildProgress>[];
    final errors = <Object>[];
    final completed = Completer<void>();
    maintenance
        .rebuild(
          resetPreview: () async {
            reset = true;
          },
          previewCounts: () async => (0, 0),
        )
        .listen(steps.add, onError: errors.add, onDone: completed.complete);
    await completed.future;
    expect(errors, [isA<StateError>()]);
    expect(reset, isFalse);
    expect(steps, isEmpty);
  });
}

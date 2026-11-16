import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/index_maintenance.dart';

/// #668: the derived indexes heal on open and rebuild on demand; the user
/// texts are only read.
void main() {
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
      'reported corrupt',
      "INSERT INTO app_meta (key, value) VALUES ('$kSearchIndexDamagedKey', '1')",
    ),
  ]) {
    test('$name search index is rebuilt on open and reported', () async {
      await seed();
      final broken = open();
      final before = await texts(broken);
      await broken.customStatement(breakIt);
      await broken.close();

      final db = open();
      addTearDown(db.close);
      expect(await found(db, 'apple'), {'a', 'b'});
      expect(db.indexesRepairedOnOpen, isTrue);
      expect(await texts(db), before);
    });
  }

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
}

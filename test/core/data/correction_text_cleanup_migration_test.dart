import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

import '../../fixtures/scratch_database.dart';

/// v33 -> v34: deletes the whole-text correction rows of v25 (issue #350) and
/// leaves word-level rows alone.
void main() {
  late Directory tmpDir;
  late File dbFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_v34_');
    dbFile = File(p.join(tmpDir.path, 'history.db'));
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<void> insertRow(
    HistoryDatabase db,
    String id,
    String unit,
    String status, {
    int ageDays = 2,
  }) => db.customInsert(
    'INSERT INTO correction_observations (id, normalized_key, source_text, '
    'target_text, occurrence_count, status, source, first_seen_at, '
    'last_seen_at, unit) VALUES (?, ?, ?, ?, 2, ?, ?, ?, ?, ?)',
    variables: [
      Variable.withString(id),
      Variable.withString('key-$id'),
      Variable.withString('source $id'),
      Variable.withString('target $id'),
      Variable.withString(status),
      Variable.withString('manualEdit'),
      Variable.withDateTime(
        DateTime.now().subtract(Duration(days: ageDays + 1)),
      ),
      Variable.withDateTime(DateTime.now().subtract(Duration(days: ageDays))),
      Variable.withString(unit),
    ],
  );

  Future<Map<String, String>> statusById(HistoryDatabase db) async {
    final rows = await db
        .customSelect('SELECT id, status FROM correction_observations')
        .get();
    return {
      for (final r in rows) r.data['id'] as String: r.data['status'] as String,
    };
  }

  Future<void> seedV33File() async {
    final seed = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
    await insertRow(seed, 'whole-pending', 'text', 'pending');
    await insertRow(seed, 'whole-accepted', 'text', 'accepted');
    await insertRow(seed, 'word-pending', 'word', 'pending');
    await insertRow(seed, 'word-rejected', 'word', 'rejected');
    await seed.customStatement('PRAGMA user_version = 33');
    await seed.close();
  }

  test('a v33 file loses its whole-text rows and keeps word rows', () async {
    await seedV33File();

    final db = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
    addTearDown(db.close);

    expect(await statusById(db), {
      'word-pending': 'pending',
      'word-rejected': 'rejected',
    });
  });

  test('the cleanup runs once: a later row survives the next start', () async {
    await seedV33File();
    final upgraded = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
    await insertRow(upgraded, 'later', 'text', 'pending');
    await upgraded.close();

    final reopened = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
    addTearDown(reopened.close);

    expect((await statusById(reopened)).keys, contains('later'));
  });

  test('start deletes observations outside the 30-day window (#328)', () async {
    final seed = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
    await insertRow(seed, 'old-pending', 'word', 'pending', ageDays: 31);
    await insertRow(seed, 'old-rejected', 'word', 'rejected', ageDays: 90);
    await insertRow(seed, 'fresh-pending', 'word', 'pending', ageDays: 29);
    await insertRow(seed, 'fresh-rejected', 'word', 'rejected');
    await seed.close();

    final db = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
    addTearDown(db.close);

    expect((await statusById(db)).keys.toSet(), {
      'fresh-pending',
      'fresh-rejected',
    });
  });

  // v25 and v32 files predate the `unit` column: every row in them is a
  // whole-text row (issue #1197).
  for (final version in [25, 32]) {
    test('a v$version file ends up with no rows of the old whole-text unit, '
        'and learning still works', () async {
      final seed = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
      await seed.customStatement(
        'ALTER TABLE correction_observations DROP COLUMN unit',
      );
      for (final id in ['a', 'b']) {
        await seed.customInsert(
          'INSERT INTO correction_observations (id, normalized_key, '
          'source_text, target_text, occurrence_count, status, source, '
          'first_seen_at, last_seen_at) VALUES (?, ?, ?, ?, 3, ?, ?, ?, ?)',
          variables: [
            Variable.withString(id),
            Variable.withString('key-$id'),
            Variable.withString('complete user text $id'),
            Variable.withString('complete fixed user text $id'),
            Variable.withString('pending'),
            Variable.withString('manualEdit'),
            Variable.withDateTime(DateTime.now()),
            Variable.withDateTime(DateTime.now()),
          ],
        );
      }
      await seed.customStatement('PRAGMA user_version = $version');
      await seed.close();

      final db = HistoryDatabase.forTesting(scratchFileDatabase(dbFile));
      addTearDown(db.close);

      final legacy = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM correction_observations '
            "WHERE unit = 'text'",
          )
          .getSingle();
      expect(legacy.data['c'], 0);

      await insertRow(db, 'word-new', 'word', 'pending');
      expect(await statusById(db), {'word-new': 'pending'});
    });
  }
}

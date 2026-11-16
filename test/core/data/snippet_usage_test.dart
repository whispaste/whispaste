/// The v39 upgrade step (#865) adds the usage counter and last-used time to
/// `snippets`; `recordSnippetUse` maintains them locally.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp865_v39_');
    dbFile = File('${tempDir.path}/history.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('upgrade from 38 keeps snippets, never used', () async {
    final first = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await first.customSelect('SELECT 1').get();
    await first.upsertSnippet(
      id: 's1',
      title: 'Old',
      body: 'body',
      createdAt: DateTime(2026),
    );
    await first.customStatement('ALTER TABLE snippets DROP COLUMN use_count');
    await first.customStatement(
      'ALTER TABLE snippets DROP COLUMN last_used_at',
    );
    await first.customStatement('PRAGMA user_version = 38');
    await first.close();

    final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);
    final rows = await db.readAllSnippetsWithFields();

    expect(rows.single.row.title, 'Old');
    expect(rows.single.row.useCount, 0);
    expect(rows.single.row.lastUsedAt, isNull);
  });

  test(
    'a database that already has the columns is not upgraded twice',
    () async {
      final first = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await first.customSelect('SELECT 1').get();
      await first.customStatement('PRAGMA user_version = 38');
      await first.close();

      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);
      await expectLater(db.customSelect('SELECT 1').get(), completes);
    },
  );

  group('recordSnippetUse', () {
    late HistoryDatabase db;

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await db.upsertSnippet(
        id: 's1',
        title: 'One',
        body: 'body',
        createdAt: DateTime(2026),
      );
    });

    tearDown(() => db.close());

    test('counts uses and stores the last time, content untouched', () async {
      final before = (await db.readAllSnippetsWithFields()).single.row;
      await db.recordSnippetUse('s1', at: DateTime(2026, 3));
      await db.recordSnippetUse('s1', at: DateTime(2026, 4));
      final row = (await db.readAllSnippetsWithFields()).single.row;

      expect(row.useCount, 2);
      expect(row.lastUsedAt, DateTime(2026, 4));
      expect(row.updatedAt, before.updatedAt);
    });

    test('an unknown id changes nothing', () async {
      await db.recordSnippetUse('missing');
      final row = (await db.readAllSnippetsWithFields()).single.row;
      expect(row.useCount, 0);
      expect(row.lastUsedAt, isNull);
    });

    test('editing a snippet keeps its usage', () async {
      await db.recordSnippetUse('s1', at: DateTime(2026, 3));
      await db.upsertSnippet(
        id: 's1',
        title: 'Renamed',
        body: 'new body',
        createdAt: DateTime(2026),
      );
      final row = (await db.readAllSnippetsWithFields()).single.row;

      expect(row.title, 'Renamed');
      expect(row.useCount, 1);
      expect(row.lastUsedAt, DateTime(2026, 3));
    });
  });
}

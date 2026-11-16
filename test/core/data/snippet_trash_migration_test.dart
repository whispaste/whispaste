/// The v36 upgrade step (#852) adds the favourite star and the trash mark to
/// `snippets`, keeps every existing row as an active, un-starred snippet, and
/// survives being run twice.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp852_v36_');
    dbFile = File('${tempDir.path}/history.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('upgrade from 35 keeps snippets active and un-starred', () async {
    final first = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await first.customSelect('SELECT 1').get();
    await first.upsertSnippet(
      id: 's1',
      title: 'Old',
      body: 'body',
      createdAt: DateTime(2026),
    );
    await first.customStatement('ALTER TABLE snippets DROP COLUMN is_favorite');
    await first.customStatement('ALTER TABLE snippets DROP COLUMN deleted_at');
    await first.customStatement('PRAGMA user_version = 35');
    await first.close();

    final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);
    final active = await db.readAllSnippetsWithFields();

    expect(active.single.row.title, 'Old');
    expect(active.single.row.isFavorite, isFalse);
    expect(active.single.row.deletedAt, isNull);
    expect(await db.readTrashedSnippetsWithFields(), isEmpty);
  });

  test(
    'a database that already has the columns is not upgraded twice',
    () async {
      final first = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await first.customSelect('SELECT 1').get();
      // Columns exist, version is old: the state an interrupted upgrade leaves.
      await first.customStatement('PRAGMA user_version = 35');
      await first.close();

      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], db.schemaVersion);
    },
  );
}

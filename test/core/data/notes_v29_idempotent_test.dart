/// The v29 upgrade step (WP-31a) must not fail on a database that already has
/// some of its tables, for example after an interrupted or repeated upgrade.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp31a_v29_idem_');
    dbFile = File('${tempDir.path}/history.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('v29 tables already present: the upgrade from 26 skips them', () async {
    // A current database with one stored version.
    final first = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await first.customSelect('SELECT 1').get();
    await first.customStatement(
      'INSERT INTO note_versions (id, note_id, title, content, size_bytes, '
      "created_at) VALUES ('v1', 'n1', 'T', 'Inhalt', 10, 1700000000)",
    );
    // Roll back to what a v26 build leaves: the columns are gone, the tables
    // stay. This is the state an interrupted upgrade can leave behind.
    await first.customStatement('ALTER TABLE notes DROP COLUMN title');
    await first.customStatement(
      'ALTER TABLE snippets DROP COLUMN source_note_id',
    );
    await first.customStatement('PRAGMA user_version = 26');
    await first.close();

    final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 31);
    final kept = await db
        .customSelect('SELECT content FROM note_versions')
        .get();
    expect(kept.map((r) => r.data['content']), ['Inhalt']);
  });
}

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

/// v26 → v27: adds the nullable Smart-Mode undo columns to history_entries.
///
/// Builds a current database, strips the two v27 columns and sets
/// `user_version` back to 26 (what an installed v26 app would have left on
/// disk), then reopens it so the real onUpgrade branch runs.
void main() {
  group('Drift migration v26 → v27 (Smart-Mode undo columns)', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_v27_');
      dbFile = File(p.join(tmpDir.path, 'history.db'));
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    Future<Set<String>> columnNames(HistoryDatabase db) async {
      final rows = await db
          .customSelect("PRAGMA table_info('history_entries')")
          .get();
      return rows.map((r) => r.data['name'] as String).toSet();
    }

    test('an old v26 database gains both columns and keeps its rows', () async {
      final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await seed.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: const Value('old-entry'),
          content: const Value('Alter Text'),
          title: const Value('Alt'),
          timestamp: Value(DateTime(2026, 1, 2, 3, 4, 5)),
        ),
      );
      await seed.customStatement(
        'ALTER TABLE history_entries DROP COLUMN smart_mode_input',
      );
      await seed.customStatement(
        'ALTER TABLE history_entries DROP COLUMN smart_mode_output',
      );
      await seed.customStatement(
        'ALTER TABLE history_entries DROP COLUMN smart_mode_applied',
      );
      await seed.customStatement('PRAGMA user_version = 26');
      await seed.close();

      final upgraded = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      final columns = await columnNames(upgraded);
      expect(columns, contains('smart_mode_input'));
      expect(columns, contains('smart_mode_output'));
      expect(columns, contains('smart_mode_applied'));

      final entry = await upgraded.getEntry('old-entry');
      expect(entry, isNotNull);
      expect(entry!.content, 'Alter Text');
      expect(entry.smartModeInput, isNull);
      expect(entry.smartModeOutput, isNull);
      expect(entry.smartModeApplied, isNull);
    });

    test('reopening an upgraded database again changes nothing', () async {
      final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await seed.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: const Value('kept'),
          content: const Value('Bleibt'),
          title: const Value('T'),
          timestamp: Value(DateTime(2026, 1, 2)),
        ),
      );
      await seed.customStatement(
        'ALTER TABLE history_entries DROP COLUMN smart_mode_input',
      );
      await seed.customStatement(
        'ALTER TABLE history_entries DROP COLUMN smart_mode_output',
      );
      await seed.customStatement(
        'ALTER TABLE history_entries DROP COLUMN smart_mode_applied',
      );
      await seed.customStatement('PRAGMA user_version = 26');
      await seed.close();

      for (var round = 0; round < 2; round++) {
        final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
        final entry = await db.getEntry('kept');
        expect(entry!.content, 'Bleibt');
        expect(
          await columnNames(db),
          containsAll(<String>[
            'smart_mode_input',
            'smart_mode_output',
            'smart_mode_applied',
          ]),
        );
        await db.close();
      }
    });

    test('the v27 step on a database that already has the columns changes '
        'nothing and does not fail (DEV-259)', () async {
      final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await seed.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: const Value('present'),
          content: const Value('Schon da'),
          title: const Value('T'),
          timestamp: Value(DateTime(2026, 1, 2)),
        ),
      );
      // Columns stay in place; only the version is rolled back, so the v27
      // step runs over columns that already exist.
      await seed.customStatement('PRAGMA user_version = 26');
      final before = await columnNames(seed);
      await seed.close();

      final upgraded = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      expect(await columnNames(upgraded), before);
      final entry = await upgraded.getEntry('present');
      expect(entry, isNotNull);
      expect(entry!.content, 'Schon da');
      expect(entry.smartModeInput, isNull);
    });

    test(
      'a database at v27 without the marker column gets it on open (DEV-86)',
      () async {
        final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
        await seed.insertHistoryEntry(
          HistoryEntriesCompanion(
            id: const Value('dev'),
            content: const Value('Entwickler'),
            title: const Value('T'),
            timestamp: Value(DateTime(2026, 1, 2)),
          ),
        );
        await seed.customStatement(
          'ALTER TABLE history_entries DROP COLUMN smart_mode_applied',
        );
        await seed.customStatement('PRAGMA user_version = 27');
        await seed.close();

        final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
        addTearDown(db.close);

        expect(await columnNames(db), contains('smart_mode_applied'));
        expect((await db.getEntry('dev'))!.content, 'Entwickler');
        expect(await db.undoSmartMode('dev'), isFalse);
      },
    );
  });
}

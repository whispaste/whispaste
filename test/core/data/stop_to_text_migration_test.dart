import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

/// v27/v28 → v30: adds the nullable `stop_to_text_ms` column to
/// hotkey_latency_entries (XP-6-09). Version 29 is reserved for another
/// branch, so both a v27 and a v28 file must reach v30 across the gap.
///
/// Builds a current database, strips the column and sets `user_version`
/// back, then reopens it so the real onUpgrade branch runs.
void main() {
  late Directory tmpDir;
  late File dbFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_v30_');
    dbFile = File(p.join(tmpDir.path, 'history.db'));
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<Set<String>> columnNames(HistoryDatabase db) async {
    final rows = await db
        .customSelect("PRAGMA table_info('hotkey_latency_entries')")
        .get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  /// Writes one pre-v30 sample (hotkey → text, including speaking time)
  /// and leaves the file at [version] without the new column.
  Future<void> seedOldFile(int version) async {
    final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await seed.customStatement(
      'ALTER TABLE hotkey_latency_entries DROP COLUMN stop_to_text_ms',
    );
    await seed.customInsert(
      'INSERT INTO hotkey_latency_entries (id, recorded_at, latency_ms) '
      'VALUES (?, ?, ?)',
      variables: [
        Variable.withString('old'),
        Variable.withDateTime(DateTime(2026, 10, 1)),
        Variable.withInt(9000),
      ],
    );
    await seed.customStatement('PRAGMA user_version = $version');
    await seed.close();
  }

  for (final from in [27, 28]) {
    test('a v$from file gains the column, keeps old rows as NULL and '
        'averages only new samples', () async {
      await seedOldFile(from);

      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      expect(await columnNames(db), contains('stop_to_text_ms'));
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], db.schemaVersion);

      final old = await db
          .customSelect(
            'SELECT latency_ms, stop_to_text_ms FROM hotkey_latency_entries '
            "WHERE id = 'old'",
          )
          .getSingle();
      expect(old.data['latency_ms'], 9000);
      expect(old.data['stop_to_text_ms'], isNull);

      expect(await db.analyticsAverageStopToTextMs(), isNull);
      await db.recordHotkeyLatency(
        recordedAt: DateTime.now(),
        latencyMs: 4000,
        stopToTextMs: 300,
      );
      expect(await db.analyticsAverageStopToTextMs(), 300.0);
    });
  }

  test('the schema version is 31', () {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 31);
  });

  test('reopening an upgraded file changes nothing', () async {
    await seedOldFile(28);
    final first = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await columnNames(first);
    await first.close();

    final again = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(again.close);
    expect(await columnNames(again), contains('stop_to_text_ms'));
  });
}

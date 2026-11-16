import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

/// v32 → v33 adds `correction_observations.unit` (issue #144); the later v34
/// step (issue #350) then deletes the whole-text rows. Builds a current
/// database, strips the column, sets `user_version` back to 32 and reopens it
/// so the real onUpgrade steps run.
void main() {
  late Directory tmpDir;
  late File dbFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_v33_');
    dbFile = File(p.join(tmpDir.path, 'history.db'));
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  Future<void> seedV32File() async {
    final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await seed.customStatement(
      'ALTER TABLE correction_observations DROP COLUMN unit',
    );
    // An old whole-text observation that already crossed the threshold.
    await seed.customInsert(
      'INSERT INTO correction_observations (id, normalized_key, source_text, '
      'target_text, occurrence_count, status, source, first_seen_at, '
      'last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString('old'),
        Variable.withString('whole text => whole fixed text'),
        Variable.withString('whole text'),
        Variable.withString('whole fixed text'),
        Variable.withInt(5),
        Variable.withString('pending'),
        Variable.withString('manualEdit'),
        Variable.withDateTime(DateTime(2026, 10, 1)),
        Variable.withDateTime(DateTime(2026, 10, 2)),
      ],
    );
    await seed.customStatement('PRAGMA user_version = 32');
    await seed.close();
  }

  Future<bool> hasUnitColumn(HistoryDatabase db) async {
    final cols = await db
        .customSelect("PRAGMA table_info('correction_observations')")
        .get();
    return cols.any((r) => r.data['name'] == 'unit');
  }

  test('a v32 file gains the unit column and its old whole-text rows never '
      'come back as candidates, also after a second open', () async {
    await seedV32File();

    for (var open = 0; open < 2; open++) {
      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      expect(await hasUnitColumn(db), isTrue, reason: 'open #$open');
      expect(await db.readPendingCorrectionCandidates(1), isEmpty);
      expect(await db.readWordCorrectionObservations(), isEmpty);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], db.schemaVersion);
      await db.close();
    }
  });
}

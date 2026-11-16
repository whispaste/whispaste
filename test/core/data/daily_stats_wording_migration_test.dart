import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

/// v39 → v40 (#887): daily_stats gains raw_words and action_count, so the
/// wording figures no longer depend on the history. Existing aggregates
/// start with raw = revised words; transformed entries still in the history
/// add their raw surplus and one action each.
void main() {
  late Directory tmpDir;
  late File dbFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_v40_');
    dbFile = File(p.join(tmpDir.path, 'history.db'));
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test('a v39 file seeds the wording columns from the history', () async {
    final at = DateTime(2026, 10, 10, 9);
    final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    // Two dictations that day: one plain (3 words), one transformed
    // (5 raw words, 1 revised).
    for (final words in [3, 1]) {
      await seed.recordDailyStat(
        timestamp: at,
        model: 'small',
        isLocal: true,
        durationSec: 4,
        processingDurationSec: 1,
        wordCount: words,
        costUsd: 0,
      );
    }
    await seed
        .into(seed.historyEntries)
        .insert(
          HistoryEntriesCompanion.insert(
            id: 't',
            content: const Value('kurz'),
            timestamp: at,
            model: const Value('small'),
            isLocal: const Value(true),
            originalTranscript: const Value('ein etwas längerer roher Satz'),
          ),
        );
    await seed.customStatement('ALTER TABLE daily_stats DROP COLUMN raw_words');
    await seed.customStatement(
      'ALTER TABLE daily_stats DROP COLUMN action_count',
    );
    await seed.customStatement('PRAGMA user_version = 39');
    await seed.close();

    final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);
    final w = await db.analyticsWording();

    expect(w.revisedWords, 4);
    expect(w.rawWords, 8);
    expect(w.actionCount, 1);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], historySchemaVersion);
  });
}

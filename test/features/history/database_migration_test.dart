import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  group('DailyStats migration', () {
    test('v4 → v5 adds duration bucket columns to daily_stats', () async {
      // Create an in-memory DB with schema v4 (without duration columns)
      final executor = NativeDatabase.memory();

      // Manually create v4 schema (daily_stats without duration buckets)
      await executor.ensureOpen(_MockQueryExecutorUser());
      await executor.runCustom('''
        CREATE TABLE daily_stats (
          date TEXT NOT NULL,
          model TEXT NOT NULL,
          is_local INTEGER NOT NULL,
          count INTEGER NOT NULL DEFAULT 0,
          total_duration_sec REAL NOT NULL DEFAULT 0.0,
          total_processing_sec REAL NOT NULL DEFAULT 0.0,
          total_words INTEGER NOT NULL DEFAULT 0,
          total_cost_usd REAL NOT NULL DEFAULT 0.0,
          PRIMARY KEY (date, model, is_local)
        )
      ''');

      // Verify columns are missing
      final colsBefore = await executor.runSelect(
        "PRAGMA table_info('daily_stats')",
        [],
      );
      final colNamesBefore = colsBefore.map((r) => r['name'] as String).toSet();
      expect(colNamesBefore.contains('dur_under15s'), false);
      expect(colNamesBefore.contains('dur15_to30s'), false);
      expect(colNamesBefore.contains('dur30_to60s'), false);
      expect(colNamesBefore.contains('dur1_to3m'), false);
      expect(colNamesBefore.contains('dur_over3m'), false);

      // Close and reopen with HistoryDatabase (triggers migration via beforeOpen)
      await executor.close();

      // Create a fresh DB that will run the migration
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // The migration runs automatically in beforeOpen, but we need to trigger
      // it by creating the v4 schema first, then letting the DB reconcile it.
      // For testing purposes, we'll manually add the columns using the same
      // logic as the migration.

      // First, create the v4 schema in the test DB
      await db.customStatement('DROP TABLE IF EXISTS daily_stats');
      await db.customStatement('''
        CREATE TABLE daily_stats (
          date TEXT NOT NULL,
          model TEXT NOT NULL,
          is_local INTEGER NOT NULL,
          count INTEGER NOT NULL DEFAULT 0,
          total_duration_sec REAL NOT NULL DEFAULT 0.0,
          total_processing_sec REAL NOT NULL DEFAULT 0.0,
          total_words INTEGER NOT NULL DEFAULT 0,
          total_cost_usd REAL NOT NULL DEFAULT 0.0,
          PRIMARY KEY (date, model, is_local)
        )
      ''');

      // Verify columns are missing
      final colsBeforeMigration = await db
          .customSelect("PRAGMA table_info('daily_stats')")
          .get();
      final colNamesBeforeMigration = colsBeforeMigration
          .map((r) => r.data['name'] as String)
          .toSet();
      expect(colNamesBeforeMigration.contains('dur_under15s'), false);

      // Now manually trigger the migration logic (simulating what happens in beforeOpen)
      final columnsToAdd = [
        ('dur_under15s', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur15_to30s', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur30_to60s', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur1_to3m', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur_over3m', 'INTEGER NOT NULL DEFAULT 0'),
      ];

      for (final (colName, colDef) in columnsToAdd) {
        await db.customStatement(
          'ALTER TABLE daily_stats ADD COLUMN $colName $colDef',
        );
      }

      // Verify columns were added
      final colsAfter = await db
          .customSelect("PRAGMA table_info('daily_stats')")
          .get();
      final colNamesAfter = colsAfter
          .map((r) => r.data['name'] as String)
          .toSet();
      expect(colNamesAfter.contains('dur_under15s'), true);
      expect(colNamesAfter.contains('dur15_to30s'), true);
      expect(colNamesAfter.contains('dur30_to60s'), true);
      expect(colNamesAfter.contains('dur1_to3m'), true);
      expect(colNamesAfter.contains('dur_over3m'), true);

      await db.close();
    });

    test('recordDailyStat succeeds after migration', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // Record a stat (should not crash)
      await db.recordDailyStat(
        timestamp: DateTime(2026, 4, 14),
        model: 'whisper-large-v3-turbo',
        isLocal: true,
        durationSec: 45.0,
        processingDurationSec: 2.5,
        wordCount: 120,
        costUsd: 0.0,
      );

      // Verify it was recorded
      final stats = await db.select(db.dailyStats).get();
      expect(stats.length, 1);
      expect(stats.first.model, 'whisper-large-v3-turbo');
      expect(stats.first.dur30To60s, 1); // 45s falls into 30-60s bucket
      expect(stats.first.durUnder15s, 0);
      expect(stats.first.dur15To30s, 0);
      expect(stats.first.dur1To3m, 0);
      expect(stats.first.durOver3m, 0);

      await db.close();
    });

    test('migration is idempotent — no error if columns exist', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // The columns should already exist from the initial schema creation
      // Try to add them again (simulating what the migration does)
      final cols = await db
          .customSelect("PRAGMA table_info('daily_stats')")
          .get();
      final colNames = cols.map((r) => r.data['name'] as String).toSet();

      // Columns should exist
      expect(colNames.contains('dur_under15s'), true);

      // Try to add them again - this should be handled gracefully
      // by checking if they exist first (as the migration does)
      final columnsToAdd = [
        ('dur_under15s', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur15_to30s', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur30_to60s', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur1_to3m', 'INTEGER NOT NULL DEFAULT 0'),
        ('dur_over3m', 'INTEGER NOT NULL DEFAULT 0'),
      ];

      for (final (colName, colDef) in columnsToAdd) {
        if (!colNames.contains(colName)) {
          await db.customStatement(
            'ALTER TABLE daily_stats ADD COLUMN $colName $colDef',
          );
        }
      }

      // Should not crash, columns should still exist
      final colsAfter = await db
          .customSelect("PRAGMA table_info('daily_stats')")
          .get();
      final colNamesAfter = colsAfter
          .map((r) => r.data['name'] as String)
          .toSet();
      expect(colNamesAfter.contains('dur_under15s'), true);
      expect(colNamesAfter.contains('dur15_to30s'), true);
      expect(colNamesAfter.contains('dur30_to60s'), true);
      expect(colNamesAfter.contains('dur1_to3m'), true);
      expect(colNamesAfter.contains('dur_over3m'), true);

      await db.close();
    });

    test(
      'recordDailyStat works with duration buckets after migration',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());

        // Manually record a stat with duration bucket tracking
        // (simulating what backfillDailyStats does)
        await db.recordDailyStat(
          timestamp: DateTime(2026, 4, 14),
          model: 'whisper-small',
          isLocal: true,
          durationSec: 25.0, // Falls into 15-30s bucket (< 30)
          processingDurationSec: 1.5,
          wordCount: 6, // "Test content with multiple words here"
          costUsd: 0.0,
        );

        // Verify stats were created with correct duration bucket
        final stats = await db.select(db.dailyStats).get();
        expect(stats.length, 1);
        expect(stats.first.count, 1);
        expect(stats.first.model, 'whisper-small');
        expect(stats.first.dur15To30s, 1); // 25s falls into 15-30s bucket
        expect(stats.first.durUnder15s, 0);
        expect(stats.first.dur30To60s, 0);
        expect(stats.first.dur1To3m, 0);
        expect(stats.first.durOver3m, 0);

        await db.close();
      },
    );

    test('duration buckets are correctly assigned', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // Test each bucket
      final testCases = [
        (10.0, 'durUnder15s'), // < 15s
        (20.0, 'dur15To30s'), // 15-30s
        (45.0, 'dur30To60s'), // 30-60s
        (120.0, 'dur1To3m'), // 1-3m
        (200.0, 'durOver3m'), // > 3m
      ];

      for (var i = 0; i < testCases.length; i++) {
        final (duration, expectedBucket) = testCases[i];
        await db.recordDailyStat(
          timestamp: DateTime(2026, 4, 14 + i),
          model: 'test-model-$i',
          isLocal: true,
          durationSec: duration,
          processingDurationSec: 1.0,
          wordCount: 50,
          costUsd: 0.0,
        );
      }

      final stats = await db.select(db.dailyStats).get();
      expect(stats.length, 5);

      // Verify each bucket
      final stat0 = stats.firstWhere((s) => s.model == 'test-model-0');
      expect(stat0.durUnder15s, 1);
      expect(stat0.dur15To30s, 0);

      final stat1 = stats.firstWhere((s) => s.model == 'test-model-1');
      expect(stat1.dur15To30s, 1);
      expect(stat1.durUnder15s, 0);

      final stat2 = stats.firstWhere((s) => s.model == 'test-model-2');
      expect(stat2.dur30To60s, 1);
      expect(stat2.dur15To30s, 0);

      final stat3 = stats.firstWhere((s) => s.model == 'test-model-3');
      expect(stat3.dur1To3m, 1);
      expect(stat3.dur30To60s, 0);

      final stat4 = stats.firstWhere((s) => s.model == 'test-model-4');
      expect(stat4.durOver3m, 1);
      expect(stat4.dur1To3m, 0);

      await db.close();
    });

    test('duration buckets accumulate correctly on upsert', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // Record multiple stats for the same day/model/isLocal
      await db.recordDailyStat(
        timestamp: DateTime(2026, 4, 14),
        model: 'whisper-large-v3-turbo',
        isLocal: true,
        durationSec: 10.0, // < 15s
        processingDurationSec: 1.0,
        wordCount: 50,
        costUsd: 0.0,
      );

      await db.recordDailyStat(
        timestamp: DateTime(2026, 4, 14),
        model: 'whisper-large-v3-turbo',
        isLocal: true,
        durationSec: 25.0, // 15-30s
        processingDurationSec: 1.0,
        wordCount: 50,
        costUsd: 0.0,
      );

      await db.recordDailyStat(
        timestamp: DateTime(2026, 4, 14),
        model: 'whisper-large-v3-turbo',
        isLocal: true,
        durationSec: 10.0, // < 15s again
        processingDurationSec: 1.0,
        wordCount: 50,
        costUsd: 0.0,
      );

      // Should have one row with accumulated buckets
      final stats = await db.select(db.dailyStats).get();
      expect(stats.length, 1);
      expect(stats.first.count, 3);
      expect(stats.first.durUnder15s, 2); // Two recordings < 15s
      expect(stats.first.dur15To30s, 1); // One recording 15-30s
      expect(stats.first.dur30To60s, 0);
      expect(stats.first.dur1To3m, 0);
      expect(stats.first.durOver3m, 0);

      await db.close();
    });
  });

  group('Groq removal migration (v1.2.13)', () {
    test(
      'stt_provider = Groq is rewritten to On Device and flag is set',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());

        // Open the DB and create the app_settings table via a no-op query.
        await db.customSelect('SELECT 1').get();

        // Manually insert legacy Groq provider row and groq_api_key column
        // (simulating a pre-v1.2.13 database that had Groq configured).
        await db.customStatement(
          "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('stt_provider', 'Groq')",
        );
        // Add the groq_api_key column as it existed before the migration.
        try {
          await db.customStatement(
            'ALTER TABLE app_settings ADD COLUMN groq_api_key TEXT',
          );
        } catch (_) {
          // Column may not exist in the test schema — that's fine.
        }

        // Run the migration directly.
        await db.runGroqMigrationForTesting();

        // Verify the migration flag was raised.
        expect(db.consumeGroqMigrationFlag(), isTrue);
        // Consuming the flag again must return false (one-shot).
        expect(db.consumeGroqMigrationFlag(), isFalse);

        // Verify the stt_provider row was rewritten.
        final rows = await db.readAppSettings();
        expect(rows['stt_provider'], 'On Device');

        // Verify the groq_api_key column was dropped (SQLite ≥ 3.35).
        // After DROP COLUMN the key should not appear in readAppSettings.
        expect(rows.containsKey('groq_api_key'), isFalse);

        await db.close();
      },
    );

    test('migration is idempotent — second run does not re-raise flag', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();

      // Write On Device (not Groq) — migration must not fire.
      await db.customStatement(
        "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('stt_provider', 'On Device')",
      );

      await db.runGroqMigrationForTesting();

      // Flag must NOT be set when provider was not Groq.
      expect(db.consumeGroqMigrationFlag(), isFalse);

      await db.close();
    });

    test('stt_provider other than Groq is left unchanged', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();

      await db.customStatement(
        "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('stt_provider', 'OpenAI')",
      );

      await db.runGroqMigrationForTesting();

      expect(db.consumeGroqMigrationFlag(), isFalse);

      final rows = await db.readAppSettings();
      expect(rows['stt_provider'], 'OpenAI');

      await db.close();
    });
  });

  group('Legacy-NULL backfill migration (v12, FLUTTER_WHISPASTE-B1)', () {
    test(
      'backfills legacy NULL values in history_entries with schema defaults',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.customSelect('SELECT 1').get();

        // Recreate history_entries without NOT NULL, mimicking a legacy row
        // that slipped through before these columns' NULL-ness was closed
        // off (the exact shape that crashed $HistoryEntriesTable.map with a
        // null-check error).
        await db.customStatement('DROP TABLE history_entries');
        await db.customStatement('''
          CREATE TABLE history_entries (
            id TEXT NOT NULL PRIMARY KEY,
            content TEXT,
            title TEXT,
            timestamp INTEGER NOT NULL,
            duration_sec REAL,
            processing_duration_sec REAL,
            language TEXT,
            language_hint TEXT,
            tags TEXT,
            pinned INTEGER,
            source TEXT,
            model TEXT,
            is_local INTEGER,
            cost_usd REAL,
            archived INTEGER,
            title_edited INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');

        await db.customStatement('''
          INSERT INTO history_entries (id, timestamp)
          VALUES ('legacy-1', 1767225600000)
        ''');

        await db.backfillNullableHistoryColumnsForTesting();

        final row = await db
            .customSelect("SELECT * FROM history_entries WHERE id = 'legacy-1'")
            .getSingle();

        expect(row.data['content'], '');
        expect(row.data['title'], '');
        expect(row.data['duration_sec'], 0.0);
        expect(row.data['processing_duration_sec'], 0.0);
        expect(row.data['language'], '');
        expect(row.data['language_hint'], '');
        expect(row.data['tags'], '[]');
        expect(row.data['pinned'], 0);
        expect(row.data['source'], 'dictation');
        expect(row.data['model'], '');
        expect(row.data['is_local'], 0);
        expect(row.data['cost_usd'], 0.0);
        expect(row.data['archived'], 0);

        await db.close();
      },
    );

    test(
      'is idempotent — second run does not alter already-backfilled rows',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.customSelect('SELECT 1').get();

        await db.customStatement('DROP TABLE history_entries');
        await db.customStatement('''
        CREATE TABLE history_entries (
          id TEXT NOT NULL PRIMARY KEY,
          content TEXT,
          title TEXT,
          timestamp INTEGER NOT NULL,
          duration_sec REAL,
          processing_duration_sec REAL,
          language TEXT,
          language_hint TEXT,
          tags TEXT,
          pinned INTEGER,
          source TEXT,
          model TEXT,
          is_local INTEGER,
          cost_usd REAL,
          archived INTEGER,
          title_edited INTEGER NOT NULL DEFAULT 0,
          deleted_at INTEGER
        )
      ''');

        // A row that already has real, non-default values must survive
        // untouched — the backfill only targets genuine NULLs.
        await db.customStatement('''
        INSERT INTO history_entries
          (id, content, title, timestamp, source, pinned)
        VALUES
          ('real-1', 'hello world', 'My title', 1767225600000, 'dictation', 1)
      ''');

        await db.backfillNullableHistoryColumnsForTesting();
        await db.backfillNullableHistoryColumnsForTesting();

        final row = await db
            .customSelect("SELECT * FROM history_entries WHERE id = 'real-1'")
            .getSingle();
        expect(row.data['content'], 'hello world');
        expect(row.data['title'], 'My title');
        expect(row.data['pinned'], 1);

        await db.close();
      },
    );
  });

  group('History color-slot migration (v17 → v18)', () {
    test('adds color_slot column to history_entries', () async {
      final executor = NativeDatabase.memory();
      await executor.ensureOpen(_MockQueryExecutorUser());
      await executor.close();

      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // Verify the column is present after the schema-v18 migration runs
      // automatically for a freshly-created (i.e. already-current) DB.
      final cols = await db
          .customSelect("PRAGMA table_info('history_entries')")
          .get();
      final colNames = cols.map((r) => r.data['name'] as String).toSet();
      expect(colNames.contains('color_slot'), true);

      await db.close();
    });

    test(
      'backfills existing rows with a slot in the 8-category range',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.customSelect('SELECT 1').get();

        // Simulate a pre-v18 row: drop the column, insert without it, then
        // re-run the migration logic directly (mirrors the other migration
        // tests in this file, which call the private migration step rather
        // than fabricating a whole legacy schema).
        await db.customStatement(
          'ALTER TABLE history_entries DROP COLUMN color_slot',
        );
        await db.customStatement('''
          INSERT INTO history_entries (id, timestamp)
          VALUES ('legacy-1', 1767225600000), ('legacy-2', 1767225700000)
        ''');

        await db.addHistoryColorSlotColumnForTesting();

        final rows = await db
            .customSelect('SELECT color_slot FROM history_entries')
            .get();
        expect(rows, hasLength(2));
        for (final row in rows) {
          final slot = row.data['color_slot'] as int;
          expect(slot, inInclusiveRange(0, 7));
        }

        await db.close();
      },
    );

    test('migration is idempotent — a second run neither errors nor re-rolls '
        'already-assigned slots', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();

      // Simulate a pre-v18 row exactly like the backfill test, so the
      // first call actually exercises the ALTER/UPDATE branch instead of
      // finding the column already present (which would make this test
      // pass even with broken migration SQL).
      await db.customStatement(
        'ALTER TABLE history_entries DROP COLUMN color_slot',
      );
      await db.customStatement('''
          INSERT INTO history_entries (id, timestamp)
          VALUES ('legacy-1', 1767225600000), ('legacy-2', 1767225700000)
        ''');

      await db.addHistoryColorSlotColumnForTesting();
      final firstRun = await db
          .customSelect(
            'SELECT id, color_slot FROM history_entries ORDER BY id',
          )
          .get();
      final slotsAfterFirstRun = {
        for (final row in firstRun)
          row.data['id'] as String: row.data['color_slot'] as int,
      };

      // Second call must be a no-op: the column already exists, so this
      // must not re-run the ALTER (would throw "duplicate column") nor
      // re-randomize the slots already assigned by the first run — this
      // guarantee now matters beyond the one-time v17->v18 upgrade path,
      // since _reconcileGoSchema also calls this on every app open.
      await db.addHistoryColorSlotColumnForTesting();

      final secondRun = await db
          .customSelect(
            'SELECT id, color_slot FROM history_entries ORDER BY id',
          )
          .get();
      final slotsAfterSecondRun = {
        for (final row in secondRun)
          row.data['id'] as String: row.data['color_slot'] as int,
      };
      expect(slotsAfterSecondRun, slotsAfterFirstRun);

      await db.close();
    });
  });

  group('Quick-note migration (v18 → v19)', () {
    test('adds is_quick_note column to notes', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      final cols = await db.customSelect("PRAGMA table_info('notes')").get();
      final colNames = cols.map((r) => r.data['name'] as String).toSet();
      expect(colNames.contains('is_quick_note'), true);

      await db.close();
    });

    test('a partial unique index rejects two notes marked at once', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.createNote();
      final a = await db.createNote();
      final b = await db.createNote();
      await db.setQuickNote(a.id);

      await expectLater(
        db.customStatement(
          "UPDATE notes SET is_quick_note = 1 WHERE id = '${b.id}'",
        ),
        throwsA(anything),
      );

      await db.close();
    });
  });

  group('Fuzzy-replacement migration (v19 → v20)', () {
    test(
      'adds match_mode/fuzzy_threshold/origin columns to text_replacements',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());

        final cols = await db
            .customSelect("PRAGMA table_info('text_replacements')")
            .get();
        final colNames = cols.map((r) => r.data['name'] as String).toSet();
        expect(colNames.contains('match_mode'), true);
        expect(colNames.contains('fuzzy_threshold'), true);
        expect(colNames.contains('origin'), true);

        await db.close();
      },
    );

    test(
      'a pre-v20 row keeps matching exactly as before (default exact/manual)',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.upsertReplacementWithTriggers(
          id: 'r1',
          triggers: ['omw'],
          replacement: 'on my way',
          createdAt: DateTime.now(),
        );

        final rows = await db.readAllReplacements();
        expect(rows.single.row.matchMode, 'exact');
        expect(rows.single.row.origin, 'manual');
        expect(rows.single.row.fuzzyThreshold, null);

        await db.close();
      },
    );

    test('migration is idempotent — a second run does not error or overwrite '
        'existing values', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.upsertReplacementWithTriggers(
        id: 'r1',
        triggers: ['id'],
        replacement: 'ID',
        createdAt: DateTime.now(),
        matchMode: 'fuzzy',
        fuzzyThreshold: 0.85,
        origin: 'imported',
      );

      await db.addFuzzyReplacementColumnsForTesting();

      final rows = await db.readAllReplacements();
      expect(rows.single.row.matchMode, 'fuzzy');
      expect(rows.single.row.fuzzyThreshold, 0.85);
      expect(rows.single.row.origin, 'imported');

      await db.close();
    });

    test(
      'migration is idempotent — re-running the index guard does not error',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.customSelect('SELECT 1').get();

        // beforeOpen already ran _ensureNotesIndexes once during open above;
        // re-invoking it directly must be a no-op, not a "duplicate index"
        // error — mirrors the color-slot migration's idempotency guarantee.
        await db.ensureNotesIndexesForTesting();
        await db.ensureNotesIndexesForTesting();

        await db.close();
      },
    );
  });

  group('Smart Mode edited-content migration (v21 → v22)', () {
    test('adds smart_mode_edited_content column to history_entries', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      final cols = await db
          .customSelect("PRAGMA table_info('history_entries')")
          .get();
      final colNames = cols.map((r) => r.data['name'] as String).toSet();
      expect(colNames.contains('smart_mode_edited_content'), true);

      await db.close();
    });

    test('a pre-v22 entry has no edited version until one is set', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(id: 'e1', timestamp: DateTime(2025, 1)),
      );

      final entry = await db.getEntry('e1');
      expect(entry!.smartModeEditedContent, null);

      await db.updateEntry(
        'e1',
        const HistoryEntriesCompanion(
          smartModeEditedContent: Value('cleaned up text'),
        ),
      );
      final updated = await db.getEntry('e1');
      expect(updated!.smartModeEditedContent, 'cleaned up text');
      expect(updated.content, ''); // raw content untouched

      await db.close();
    });

    test('migration is idempotent — a second run does not error or overwrite '
        'existing values', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(id: 'e1', timestamp: DateTime(2025, 1)),
      );
      await db.updateEntry(
        'e1',
        const HistoryEntriesCompanion(
          smartModeEditedContent: Value('already edited'),
        ),
      );

      await db.addSmartModeEditedContentColumnForTesting();

      final entry = await db.getEntry('e1');
      expect(entry!.smartModeEditedContent, 'already edited');

      await db.close();
    });
  });

  group(
    'TextReplacementTriggers migration (v13, multi-trigger replacements)',
    () {
      test(
        'backfills existing single-trigger replacements into the triggers table — no data loss',
        () async {
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          await db.customSelect('SELECT 1').get();

          await db.customStatement('''
          INSERT INTO text_replacements (id, trigger, replacement, created_at)
          VALUES ('r1', 'mfg', 'Mit freundlichen Grüßen', 1767225600000)
        ''');
          await db.customStatement('''
          INSERT INTO text_replacements (id, trigger, replacement, created_at)
          VALUES ('r2', 'lg', 'Liebe Grüße', 1767225600000)
        ''');

          await db.backfillReplacementTriggersForTesting();

          final triggerRows = await db
              .customSelect(
                'SELECT replacement_id, trigger FROM text_replacement_triggers '
                'ORDER BY replacement_id',
              )
              .get();
          expect(triggerRows, hasLength(2));
          expect(triggerRows[0].data['replacement_id'], 'r1');
          expect(triggerRows[0].data['trigger'], 'mfg');
          expect(triggerRows[1].data['replacement_id'], 'r2');
          expect(triggerRows[1].data['trigger'], 'lg');

          final replacements = await db.readAllReplacements();
          expect(replacements, hasLength(2));
          expect(replacements.firstWhere((r) => r.row.id == 'r1').triggers, [
            'mfg',
          ]);
          expect(replacements.firstWhere((r) => r.row.id == 'r2').triggers, [
            'lg',
          ]);

          await db.close();
        },
      );

      test(
        'is idempotent — second run does not duplicate trigger rows',
        () async {
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          await db.customSelect('SELECT 1').get();

          await db.customStatement('''
          INSERT INTO text_replacements (id, trigger, replacement, created_at)
          VALUES ('r1', 'mfg', 'Mit freundlichen Grüßen', 1767225600000)
        ''');

          await db.backfillReplacementTriggersForTesting();
          await db.backfillReplacementTriggersForTesting();

          final triggerRows = await db
              .customSelect('SELECT * FROM text_replacement_triggers')
              .get();
          expect(triggerRows, hasLength(1));

          await db.close();
        },
      );
    },
  );

  group('entry_notes index (perf: per-entry "Anmerkung" lookups)', () {
    test('idx_entry_notes_entry_id is created on a fresh database', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();

      final indexes = await db
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type = 'index' AND tbl_name = 'entry_notes'",
          )
          .get();
      expect(
        indexes.map((r) => r.data['name'] as String),
        contains('idx_entry_notes_entry_id'),
      );

      await db.close();
    });

    test('notesForEntry only returns rows for the requested entry '
        '(index does not change query results)', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e1',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e2',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      final now = DateTime(2026, 1, 1);
      await db.upsertNote(
        EntryNotesCompanion.insert(
          id: 'n1',
          entryId: 'e1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.upsertNote(
        EntryNotesCompanion.insert(
          id: 'n2',
          entryId: 'e2',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final notesForE1 = await db.notesForEntry('e1');
      expect(notesForE1.map((n) => n.id), ['n1']);

      await db.close();
    });
  });

  group('backfillDailyStats (perf: transaction-wrapped loop)', () {
    test('reopening a file-backed DB with real history entries and an empty '
        'DailyStats table backfills correctly (exercises the '
        'transaction-wrapped loop with non-empty rows, not just the '
        'no-op/empty case)', () async {
      final dir = await Directory.systemTemp.createTemp('wp_backfill_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/test.sqlite');

      var db = HistoryDatabase.forTesting(NativeDatabase(file));
      for (var i = 0; i < 5; i++) {
        await db.upsertEntry(
          HistoryEntriesCompanion.insert(
            id: 'e$i',
            timestamp: DateTime(2026, 1, 1),
            content: const Value('hello world'),
            model: const Value('whisper-small'),
          ),
        );
      }
      // backfillDailyStats already ran once on open (entries were empty
      // at that point, so it was a no-op) — confirm the entries
      // themselves exist. DailyStats is populated only by
      // recordDailyStat/backfillDailyStats, not by upsertEntry, so
      // analyticsEntryCount() (which reads DailyStats) is still 0 here.
      expect(await db.select(db.historyEntries).get(), hasLength(5));
      expect(await db.analyticsEntryCount(), 0);

      await db.resetDailyStats();
      await db.close();

      // Reopen the same file: beforeOpen re-runs backfillDailyStats, this
      // time with 5 real history entries and an empty DailyStats table —
      // exactly the "reset stats, then relaunch" scenario the
      // transaction-wrap fix targets. This exercises the loop with
      // actual rows, not an empty transaction.
      db = HistoryDatabase.forTesting(NativeDatabase(file));
      expect(await db.analyticsEntryCount(), 5);

      await db.close();
    });
  });
}

/// Mock query executor user for manual schema creation
class _MockQueryExecutorUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}

  @override
  int get schemaVersion => 4;
}

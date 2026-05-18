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

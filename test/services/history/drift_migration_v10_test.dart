/// Drift migration v9 → v10 test.
///
/// Verifies the destructive migration that drops the `projects` table and the
/// `history_entries.project_id` column. The migration is implemented in
/// [HistoryDatabase] (see `lib/core/data/database.dart`).
///
/// We seed an old-schema (pre-v10) database manually via raw SQL, set
/// `PRAGMA user_version`, then open it through [HistoryDatabase] so Drift's
/// onUpgrade hook fires the v10 branch.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

void main() {
  group('Drift migration v9 → v10', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_v10_');
      dbFile = File(p.join(tmpDir.path, 'history.db'));
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    /// Seeds an old (pre-v10) database with the historical `projects` table
    /// and `history_entries.project_id` column, then closes it cleanly.
    Future<void> seedOldSchema() async {
      final raw = NativeDatabase(dbFile);
      final user = _SeedExecutorUser();
      await raw.ensureOpen(user);

      // history_entries with project_id column
      await raw.runCustom('''
        CREATE TABLE history_entries (
          id TEXT NOT NULL PRIMARY KEY,
          content TEXT NOT NULL DEFAULT '',
          title TEXT NOT NULL DEFAULT '',
          timestamp INTEGER NOT NULL,
          duration_sec REAL NOT NULL DEFAULT 0.0,
          processing_duration_sec REAL NOT NULL DEFAULT 0.0,
          language TEXT NOT NULL DEFAULT '',
          language_hint TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '[]',
          pinned INTEGER NOT NULL DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'dictation',
          model TEXT NOT NULL DEFAULT '',
          is_local INTEGER NOT NULL DEFAULT 0,
          cost_usd REAL NOT NULL DEFAULT 0.0,
          project_id TEXT NOT NULL DEFAULT '',
          archived INTEGER NOT NULL DEFAULT 0,
          title_edited INTEGER NOT NULL DEFAULT 0,
          deleted_at INTEGER
        )
      ''', const []);

      // projects table
      await raw.runCustom('''
        CREATE TABLE projects (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )
      ''', const []);

      // Minimal supporting tables so HistoryDatabase open doesn't choke.
      await raw.runCustom('''
        CREATE TABLE daily_stats (
          date TEXT NOT NULL,
          model TEXT NOT NULL,
          is_local INTEGER NOT NULL,
          count INTEGER NOT NULL DEFAULT 0,
          total_duration_sec REAL NOT NULL DEFAULT 0.0,
          total_processing_sec REAL NOT NULL DEFAULT 0.0,
          total_words INTEGER NOT NULL DEFAULT 0,
          total_cost_usd REAL NOT NULL DEFAULT 0.0,
          dur_under15s INTEGER NOT NULL DEFAULT 0,
          dur15_to30s INTEGER NOT NULL DEFAULT 0,
          dur30_to60s INTEGER NOT NULL DEFAULT 0,
          dur1_to3m INTEGER NOT NULL DEFAULT 0,
          dur_over3m INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (date, model, is_local)
        )
      ''', const []);
      await raw.runCustom('''
        CREATE TABLE entry_notes (
          id TEXT NOT NULL PRIMARY KEY,
          entry_id TEXT NOT NULL REFERENCES history_entries(id),
          content TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''', const []);
      await raw.runCustom('''
        CREATE TABLE entry_attachments (
          id TEXT NOT NULL PRIMARY KEY,
          entry_id TEXT NOT NULL REFERENCES history_entries(id),
          filename TEXT NOT NULL,
          filepath TEXT NOT NULL,
          mime_type TEXT NOT NULL DEFAULT '',
          size_bytes INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''', const []);
      await raw.runCustom('''
        CREATE TABLE text_replacements (
          id TEXT NOT NULL PRIMARY KEY,
          trigger TEXT NOT NULL,
          replacement TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''', const []);
      await raw.runCustom('''
        CREATE TABLE tags (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )
      ''', const []);
      await raw.runCustom('''
        CREATE TABLE entry_tags (
          entry_id TEXT NOT NULL REFERENCES history_entries(id),
          tag_id TEXT NOT NULL REFERENCES tags(id),
          PRIMARY KEY (entry_id, tag_id)
        )
      ''', const []);
      await raw.runCustom('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''', const []);

      // Seed 2 projects
      await raw.runInsert(
        'INSERT INTO projects (id, name, created_at) VALUES (?, ?, ?)',
        ['proj-1', 'Project Alpha', 1700000000],
      );
      await raw.runInsert(
        'INSERT INTO projects (id, name, created_at) VALUES (?, ?, ?)',
        ['proj-2', 'Project Beta', 1700000001],
      );

      // Seed 3 history entries with project_id populated
      const ts = 1700000100;
      await raw.runInsert(
        'INSERT INTO history_entries '
        '(id, content, title, timestamp, duration_sec, language, tags, pinned, project_id, archived, title_edited) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'e1',
          'Content one',
          'Title one',
          ts,
          12.5,
          'en',
          '["a","b"]',
          1, // pinned
          'proj-1',
          0,
          0,
        ],
      );
      await raw.runInsert(
        'INSERT INTO history_entries '
        '(id, content, title, timestamp, duration_sec, language, tags, pinned, project_id, archived, title_edited) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'e2',
          'Content two',
          'Title two',
          ts + 10,
          22.0,
          'de',
          '["c"]',
          0,
          'proj-2',
          0,
          0,
        ],
      );
      await raw.runInsert(
        'INSERT INTO history_entries '
        '(id, content, title, timestamp, duration_sec, language, tags, pinned, project_id, archived, title_edited) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'e3',
          'Content three',
          'Title three',
          ts + 20,
          5.0,
          'en',
          '[]',
          0,
          '',
          0,
          0,
        ],
      );

      // Set the user_version so Drift treats this as a pre-v10 DB.
      await raw.runCustom('PRAGMA user_version = 9', const []);

      await raw.close();
    }

    test(
      'migrates v9 (projects + project_id) to v10 with data intact',
      () async {
        await seedOldSchema();

        // Opening through HistoryDatabase triggers onUpgrade from 9 → 10.
        final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));

        // Force the DB to open by issuing a query.
        await db.customSelect('SELECT 1').get();

        // 1. Projects table is gone — any query against it must throw.
        await expectLater(
          db.customSelect('SELECT id FROM projects').get(),
          throwsA(anything),
        );

        // 2. project_id column is gone — any query against it must throw.
        await expectLater(
          db.customSelect('SELECT project_id FROM history_entries').get(),
          throwsA(anything),
        );

        // 3. All 3 history_entries are intact with content/title/tags/pinned.
        final entries = await db.select(db.historyEntries).get();
        expect(entries, hasLength(3));

        final byId = {for (final e in entries) e.id: e};
        expect(byId.containsKey('e1'), isTrue);
        expect(byId['e1']!.content, 'Content one');
        expect(byId['e1']!.title, 'Title one');
        expect(byId['e1']!.tags, '["a","b"]');
        expect(byId['e1']!.pinned, isTrue);

        expect(byId['e2']!.content, 'Content two');
        expect(byId['e2']!.title, 'Title two');
        expect(byId['e2']!.tags, '["c"]');
        expect(byId['e2']!.pinned, isFalse);

        expect(byId['e3']!.content, 'Content three');
        expect(byId['e3']!.title, 'Title three');

        await db.close();
      },
    );

    test('migration is idempotent — second open does not error', () async {
      await seedOldSchema();

      // First open: runs the v10 migration.
      var db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
      await db.close();

      // Second open: schemaVersion is now 10; onUpgrade must not re-fire.
      // Even if it did, dropping a non-existent projects table and rebuilding
      // the (already correct) history_entries table is safe.
      db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();

      final entries = await db.select(db.historyEntries).get();
      expect(entries, hasLength(3));

      // Projects table still gone after second open.
      await expectLater(
        db.customSelect('SELECT id FROM projects').get(),
        throwsA(anything),
      );

      await db.close();
    });

    test('runV10MigrationForTesting drops projects + project_id', () async {
      // Use an in-memory DB so we can exercise the public test hook directly.
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // Replace the freshly-created v10 history_entries with a legacy variant
      // that has the project_id column, plus a legacy projects table.
      await db.customStatement('DROP TABLE IF EXISTS history_entries');
      await db.customStatement('''
        CREATE TABLE history_entries (
          id TEXT NOT NULL PRIMARY KEY,
          content TEXT NOT NULL DEFAULT '',
          title TEXT NOT NULL DEFAULT '',
          timestamp INTEGER NOT NULL,
          duration_sec REAL NOT NULL DEFAULT 0.0,
          processing_duration_sec REAL NOT NULL DEFAULT 0.0,
          language TEXT NOT NULL DEFAULT '',
          language_hint TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '[]',
          pinned INTEGER NOT NULL DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'dictation',
          model TEXT NOT NULL DEFAULT '',
          is_local INTEGER NOT NULL DEFAULT 0,
          cost_usd REAL NOT NULL DEFAULT 0.0,
          project_id TEXT NOT NULL DEFAULT '',
          archived INTEGER NOT NULL DEFAULT 0,
          title_edited INTEGER NOT NULL DEFAULT 0,
          deleted_at INTEGER
        )
      ''');
      await db.customStatement('''
        CREATE TABLE projects (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )
      ''');

      // Sanity: both legacy structures exist.
      await db.customSelect('SELECT id FROM projects').get();
      await db.customSelect('SELECT project_id FROM history_entries').get();

      // Run the migration directly.
      await db.runV10MigrationForTesting();

      // After: projects gone, project_id gone.
      await expectLater(
        db.customSelect('SELECT id FROM projects').get(),
        throwsA(anything),
      );
      await expectLater(
        db.customSelect('SELECT project_id FROM history_entries').get(),
        throwsA(anything),
      );

      // Second run is idempotent.
      await db.runV10MigrationForTesting();

      await db.close();
    });
  });
}

/// Minimal [QueryExecutorUser] for raw seed setup before Drift takes over.
class _SeedExecutorUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}

  @override
  int get schemaVersion => 9;
}

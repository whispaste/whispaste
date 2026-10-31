/// Regression test for the post-v10-migration watchEntries stream.
///
/// Reproduces the user-reported "no new entries appear in history" bug:
/// after the destructive v10 migration rebuilds `history_entries` via
/// CREATE NEW + COPY + DROP OLD + RENAME, the Drift `watch()` stream must
/// still emit when subsequent inserts happen.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

void main() {
  group('watchEntries() after v10 migration', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('whispaste_v10_watch_');
      dbFile = File(p.join(tmpDir.path, 'history.db'));
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test(
      'stream emits new entries inserted via upsertEntry after migration',
      () async {
        await _seedV9Schema(dbFile);

        // Open via HistoryDatabase → onUpgrade triggers v10 migration.
        final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
        await db.customSelect('SELECT 1').get();

        final emissions = <List<HistoryEntry>>[];
        final sub = db.watchEntries().listen(emissions.add);

        // Wait for the initial emission (post-migration snapshot).
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final initialCount = emissions.length;
        expect(initialCount, greaterThan(0), reason: 'initial snapshot');

        // Now insert a fresh entry — exactly like recording_orchestrator does.
        final now = DateTime.now();
        await db.upsertEntry(
          HistoryEntriesCompanion(
            id: const Value('e-after-migration'),
            content: const Value('post-migration content'),
            title: const Value('post-migration title'),
            timestamp: Value(now),
            durationSec: const Value(3.0),
            language: const Value('de'),
            model: const Value('whisper-small'),
            isLocal: const Value(true),
            source: const Value('dictation'),
          ),
        );

        // Drift's broadcast pump is async — give it a beat.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          emissions.length,
          greaterThan(initialCount),
          reason:
              'watchEntries() must emit again after upsertEntry. '
              'If this fails, Drift\'s update-tracker lost the table after '
              'the v10 DROP+RENAME and streams are silently broken.',
        );

        final last = emissions.last;
        expect(last.any((e) => e.id == 'e-after-migration'), isTrue);

        await sub.cancel();
        await db.close();
      },
    );
  });
}

/// Seeds a minimal pre-v10 schema (same shape as the v10 migration test
/// fixture, condensed to what's needed to open and insert).
Future<void> _seedV9Schema(File dbFile) async {
  final raw = NativeDatabase(dbFile);
  await raw.ensureOpen(_SeedExecutorUser());

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

  await raw.runCustom('''
    CREATE TABLE projects (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      created_at INTEGER NOT NULL
    )
  ''', const []);

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

  // Seed one entry so the post-migration snapshot is non-empty.
  await raw.runInsert(
    'INSERT INTO history_entries '
    '(id, content, title, timestamp, duration_sec, language, tags, pinned, project_id, archived, title_edited) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      'e-pre',
      'Pre content',
      'Pre title',
      1700000100,
      4.0,
      'de',
      '[]',
      0,
      '',
      0,
      0,
    ],
  );

  await raw.runCustom('PRAGMA user_version = 9', const []);
  await raw.close();
}

class _SeedExecutorUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
  @override
  int get schemaVersion => 9;
}

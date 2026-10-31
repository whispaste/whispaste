/// Schema v29 (WP-31a): explicit note title, version history, note image
/// assets and the snippet back-link. Runs the real upgrade step from a v26
/// file database that holds realistic notes, because installed user databases
/// take that path. Existing notes must keep content and formatting unchanged.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp31a_v29_');
    dbFile = File('${tempDir.path}/history.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> openOnce(Future<void> Function(HistoryDatabase db) body) async {
    final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    await body(db);
    await db.close();
  }

  /// Turns the current file into what an installed v26 build leaves behind:
  /// no v29 column or table, version 26.
  Future<void> downgradeToV26() async {
    await openOnce((db) async {
      await db.customStatement('DROP TABLE IF EXISTS note_versions');
      await db.customStatement('DROP TABLE IF EXISTS note_assets');
      await db.customStatement('ALTER TABLE notes DROP COLUMN title');
      await db.customStatement(
        'ALTER TABLE snippets DROP COLUMN source_note_id',
      );
      await db.customStatement('PRAGMA user_version = 26');
    });
  }

  const markdownBody =
      '# Einkaufsliste\n\n- Milch\n- **Brot**\n- ==Eier== für den Kuchen';
  const longBody =
      'Besprechung mit dem Team am Donnerstag, Zeile zwei mit Umlauten: '
      'äöüß, Emoji 🎙️ und ein Link [WhisPaste](https://whispaste.app).';

  test(
    'v26 notes keep content, formatting and timestamps; title is null',
    () async {
      await openOnce((db) async {
        await db.customStatement(
          'INSERT INTO notes (id, content, pinned, is_quick_note, deleted_at, '
          'created_at, updated_at) VALUES '
          "('n-markdown', '$markdownBody', 1, 0, NULL, 1760000000, 1760000100), "
          "('n-long', '$longBody', 0, 1, NULL, 1760000200, 1760000300), "
          "('n-trashed', 'alt', 0, 0, 1760000400, 1760000000, 1760000400)",
        );
        await db.customStatement(
          'INSERT INTO snippets (id, title, body, created_at, kind) VALUES '
          "('s1', 'Gruß', 'Mit freundlichen Grüßen', 1760000000, 'static')",
        );
      });
      await downgradeToV26();

      await openOnce((db) async {
        final markdown = await db.getNote('n-markdown');
        expect(markdown, isNotNull);
        expect(markdown!.content, markdownBody);
        expect(markdown.pinned, isTrue);
        expect(markdown.isQuickNote, isFalse);
        expect(markdown.title, isNull, reason: 'NULL = derive from first line');

        final long = await db.getNote('n-long');
        expect(long!.content, longBody);
        expect(long.isQuickNote, isTrue);

        final trashed = await db.getNote('n-trashed');
        expect(trashed!.deletedAt, isNotNull);

        final snippet = await db
            .customSelect(
              'SELECT body FROM snippets WHERE id = ?',
              variables: [Variable.withString('s1')],
            )
            .getSingle();
        expect(snippet.read<String>('body'), 'Mit freundlichen Grüßen');
      });
    },
  );

  test('v29 tables and columns exist after upgrade from v26', () async {
    await openOnce((db) async {
      await db.customStatement(
        'INSERT INTO notes (id, content, created_at, updated_at) '
        "VALUES ('n1', 'x', 1760000000, 1760000000)",
      );
    });
    await downgradeToV26();

    await openOnce((db) async {
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 31);

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND "
            "name IN ('note_versions', 'note_assets')",
          )
          .get();
      expect(tables.map((r) => r.read<String>('name')).toSet(), {
        'note_versions',
        'note_assets',
      });

      final snippetCols = await db
          .customSelect("PRAGMA table_info('snippets')")
          .get();
      expect(
        snippetCols.map((r) => r.read<String>('name')),
        contains('source_note_id'),
      );
    });
  });

  test('a v29 database reopens without changes (idempotent)', () async {
    await openOnce((db) async {
      await db.customStatement(
        'INSERT INTO notes (id, content, created_at, updated_at) '
        "VALUES ('n1', 'x', 1760000000, 1760000000)",
      );
    });
    await openOnce((db) async {
      expect((await db.getNote('n1'))!.content, 'x');
    });
    await openOnce((db) async {
      expect((await db.getNote('n1'))!.content, 'x');
    });
  });
}

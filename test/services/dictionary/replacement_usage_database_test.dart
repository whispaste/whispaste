/// Schema v26 (matrix 4.5): usage counter and favourite flag on
/// `text_replacements`. Runs the real upgrade step from a v25 file database,
/// not only a fresh schema, because existing user databases take that path.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp34_dictionary_');
    dbFile = File('${tempDir.path}/history.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Opens the file through the app's database, forcing schema creation or
  /// upgrade, and closes it again.
  Future<void> openOnce(Future<void> Function(HistoryDatabase db) body) async {
    final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    await body(db);
    await db.close();
  }

  /// Turns the current file into a v25 database: drops the two v26 columns
  /// and sets the version the way an installed v25 build left it.
  Future<void> downgradeToV25({required bool keepColumns}) async {
    await openOnce((db) async {
      if (!keepColumns) {
        await db.customStatement(
          'ALTER TABLE text_replacements DROP COLUMN usage_count',
        );
        await db.customStatement(
          'ALTER TABLE text_replacements DROP COLUMN is_favorite',
        );
      }
      await db.customStatement('PRAGMA user_version = 25');
    });
  }

  group('schema v26 upgrade', () {
    test('existing entries get zero usage and are not favourites', () async {
      await openOnce((db) async {
        await db.upsertReplacementWithTriggers(
          id: 'mfg',
          triggers: ['mfg'],
          replacement: 'Mit freundlichen Grüßen',
          createdAt: DateTime(2026, 10, 1),
        );
      });
      await downgradeToV25(keepColumns: false);

      await openOnce((db) async {
        final rows = await db.readAllReplacements();
        expect(rows.single.row.replacement, 'Mit freundlichen Grüßen');
        expect(rows.single.row.usageCount, 0);
        expect(rows.single.row.isFavorite, isFalse);
      });
    });

    test('upgrade is a no-op when the columns already exist', () async {
      await openOnce((db) async {
        await db.upsertReplacementWithTriggers(
          id: 'lg',
          triggers: ['lg'],
          replacement: 'Liebe Grüße',
          createdAt: DateTime(2026, 10, 1),
        );
        await db.addReplacementUsage({'lg': 4});
      });
      await downgradeToV25(keepColumns: true);

      await openOnce((db) async {
        final rows = await db.readAllReplacements();
        expect(rows.single.row.usageCount, 4);
      });
    });
  });

  group('usage and favourite persistence', () {
    test('usage adds up across saves and survives an edit', () async {
      await openOnce((db) async {
        await db.upsertReplacementWithTriggers(
          id: 'tel',
          triggers: ['tel'],
          replacement: '+49 123',
          createdAt: DateTime(2026, 10, 1),
        );
        await db.addReplacementUsage({'tel': 2});
        await db.addReplacementUsage({'tel': 3, 'unknown-id': 9});

        // Editing the entry must not reset its counter.
        await db.upsertReplacementWithTriggers(
          id: 'tel',
          triggers: ['telefon'],
          replacement: '+49 123 456',
          createdAt: DateTime(2026, 10, 1),
        );

        final row = (await db.readAllReplacements()).single.row;
        expect(row.usageCount, 5);
        expect(row.replacement, '+49 123 456');
      });
    });

    test('an empty usage map writes nothing', () async {
      await openOnce((db) async {
        await db.addReplacementUsage(const {});
        expect(await db.readAllReplacements(), isEmpty);
      });
    });

    test('favourite flag can be set, cleared and survives an edit', () async {
      await openOnce((db) async {
        await db.upsertReplacementWithTriggers(
          id: 'mfg',
          triggers: ['mfg'],
          replacement: 'Mit freundlichen Grüßen',
          createdAt: DateTime(2026, 10, 1),
        );
        await db.setReplacementFavourite('mfg', value: true);
        expect((await db.readAllReplacements()).single.row.isFavorite, isTrue);

        await db.upsertReplacementWithTriggers(
          id: 'mfg',
          triggers: ['mfg'],
          replacement: 'Mit freundlichen Grüßen!',
          createdAt: DateTime(2026, 10, 1),
        );
        expect((await db.readAllReplacements()).single.row.isFavorite, isTrue);

        await db.setReplacementFavourite('mfg', value: false);
        expect((await db.readAllReplacements()).single.row.isFavorite, isFalse);
      });
    });
  });
}

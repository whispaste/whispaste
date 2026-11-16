import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/sorting/list_sort.dart';
import 'package:whispaste/core/sorting/list_sort_preference.dart';
import 'package:whispaste/services/drift_recording_store.dart';

/// Schema v32 adds the nullable `updated_at` column to text_replacements and
/// snippets, with no backfill. Also covers the write rules the sort relies on:
/// createdAt is fixed after insert, updatedAt moves on content changes only,
/// and the stored sort preference is read back safely.
void main() {
  final t0 = DateTime(2026, 3, 1, 12);
  DateTime day(int n) => t0.add(Duration(days: n));

  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('write rules', () {
    test('an edit keeps the original createdAt', () async {
      await db.upsertReplacementWithTriggers(
        id: 'r1',
        triggers: const ['mfg'],
        replacement: 'Mit freundlichen Grüßen',
        createdAt: day(1),
      );
      await db.upsertReplacementWithTriggers(
        id: 'r1',
        triggers: const ['mfg'],
        replacement: 'Mit besten Grüßen',
        createdAt: day(5),
      );

      final row = (await db.readAllReplacements()).single.row;
      expect(row.createdAt, day(1));
      expect(row.replacement, 'Mit besten Grüßen');
    });

    test('a content edit sets updatedAt, usage and favourite do not', () async {
      await db.upsertReplacementWithTriggers(
        id: 'r1',
        triggers: const ['mfg'],
        replacement: 'x',
        createdAt: day(1),
        updatedAt: day(2),
      );
      final afterCreate = (await db.readAllReplacements()).single.row;
      expect(afterCreate.updatedAt, day(2));

      await db.addReplacementUsage({'r1': 1});
      await db.setReplacementFavourite('r1', value: true);

      final afterUse = (await db.readAllReplacements()).single.row;
      expect(afterUse.updatedAt, day(2));
      expect(afterUse.createdAt, day(1));
    });

    test('a snippet edit keeps createdAt and stamps updatedAt', () async {
      await db.upsertSnippet(
        id: 's1',
        title: 'Signatur',
        body: 'Viele Grüße',
        createdAt: day(1),
        updatedAt: day(2),
      );
      await db.upsertSnippet(
        id: 's1',
        title: 'Signatur neu',
        body: 'Viele Grüße',
        createdAt: day(9),
        updatedAt: day(4),
      );

      final row = (await db.readAllSnippets()).single;
      expect(row.createdAt, day(1));
      expect(row.updatedAt, day(4));
      expect(row.title, 'Signatur neu');
    });
  });

  group('execution order', () {
    test('rules keep creation order whatever the list is sorted by', () async {
      // Creation order differs from A–Z by trigger on purpose.
      await db.upsertReplacementWithTriggers(
        id: 'z',
        triggers: const ['zebra'],
        replacement: 'first',
        createdAt: day(1),
      );
      await db.upsertReplacementWithTriggers(
        id: 'a',
        triggers: const ['alpha'],
        replacement: 'second',
        createdAt: day(2),
      );
      await db.upsertReplacementWithTriggers(
        id: 'm',
        triggers: const ['mid'],
        replacement: 'third',
        createdAt: day(3),
      );

      final rows = await db.readAllReplacements();
      final rules = textReplacementRulesFrom(rows);

      expect([for (final r in rows) r.row.id], ['z', 'a', 'm']);
      expect(
        [for (final r in rules) r.replacement],
        ['first', 'second', 'third'],
      );
    });
  });

  group('sort preference', () {
    ProviderContainer containerFor() {
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('defaults before a choice, then reads back a saved choice', () async {
      final first = containerFor();
      expect(
        await first.read(replacementsSortProvider.future),
        kReplacementsDefaultSort,
      );

      const chosen = ListSort(ListSortField.changed, reversed: true);
      await first.read(replacementsSortProvider.notifier).choose(chosen);
      expect(await first.read(replacementsSortProvider.future), chosen);

      // A new container reads the persisted value, as after a restart.
      final second = containerFor();
      expect(await second.read(replacementsSortProvider.future), chosen);
    });

    test('an unknown stored value falls back to the default', () async {
      await db.writeAppSetting('snippets_sort', 'bogus:reversed:more');
      expect(
        await containerFor().read(snippetsSortProvider.future),
        kSnippetsDefaultSort,
      );
    });

    test('a field the list does not offer falls back to the default', () async {
      await db.writeAppSetting('snippets_sort', 'trigger');
      expect(
        await containerFor().read(snippetsSortProvider.future),
        kSnippetsDefaultSort,
      );
    });
  });

  group('migration v31 to v32', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('whispaste_mig_v32_');
      dbFile = File(p.join(tmpDir.path, 'history.db'));
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    test('old rows gain a NULL updatedAt and keep their createdAt', () async {
      // Build a current file, strip the new columns, set the version back.
      final seed = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await seed.upsertReplacementWithTriggers(
        id: 'old',
        triggers: const ['mfg'],
        replacement: 'Gruß',
        createdAt: day(1),
      );
      await seed.upsertSnippet(
        id: 'snip',
        title: 'Titel',
        body: 'Text',
        createdAt: day(2),
      );
      await seed.customStatement(
        'ALTER TABLE text_replacements DROP COLUMN updated_at',
      );
      await seed.customStatement('ALTER TABLE snippets DROP COLUMN updated_at');
      await seed.customStatement('PRAGMA user_version = 31');
      await seed.close();

      final upgraded = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      final replacement = (await upgraded.readAllReplacements()).single.row;
      expect(replacement.createdAt, day(1));
      expect(replacement.updatedAt, isNull);

      final snippet = (await upgraded.readAllSnippets()).single;
      expect(snippet.createdAt, day(2));
      expect(snippet.updatedAt, isNull);

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data['user_version'], db.schemaVersion);
    });
  });
}

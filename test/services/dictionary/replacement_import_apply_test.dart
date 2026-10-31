/// R-08: a planned replacement import is written in one transaction. Entries
/// the plan only trims keep their favourite flag and usage count; a failing
/// step leaves the stored list exactly as it was.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/dictionary/replacement_import_plan.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<ReplacementWithTriggers> stored(String id) async =>
      (await db.readAllReplacements()).singleWhere((r) => r.row.id == id);

  Future<void> seed(String id, List<String> triggers) =>
      db.upsertReplacementWithTriggers(
        id: id,
        triggers: triggers,
        replacement: 'Ersatz $id',
        createdAt: DateTime(2026),
      );

  group('HistoryDatabase.applyReplacementImport', () {
    test('trimmed entry keeps its favourite flag and usage count', () async {
      await seed('keep', ['mfg', 'mahlzeit']);
      await db.setReplacementFavourite('keep', value: true);
      await db.addReplacementUsage({'keep': 3});

      await db.applyReplacementImport(
        updates: [
          (id: 'keep', triggers: const ['mahlzeit']),
        ],
        deleteIds: const [],
        inserts: const [],
      );

      final after = await stored('keep');
      expect(after.triggers, ['mahlzeit']);
      expect(after.row.trigger, 'mahlzeit');
      expect(after.row.isFavorite, isTrue);
      expect(after.row.usageCount, 3);
    });

    test('deleted entries lose their triggers and row', () async {
      await seed('gone', ['x']);
      await seed('stays', ['y']);

      await db.applyReplacementImport(
        updates: const [],
        deleteIds: const ['gone'],
        inserts: const [],
      );

      final rows = await db.readAllReplacements();
      expect(rows.map((r) => r.row.id), ['stays']);
      final triggers = await db.select(db.textReplacementTriggers).get();
      expect(triggers.map((t) => t.replacementId), ['stays']);
    });

    test('inserts are written with their match settings', () async {
      await db.applyReplacementImport(
        updates: const [],
        deleteIds: const [],
        inserts: [
          ReplacementWrite(
            id: 'new',
            triggers: const ['sig', 'signatur'],
            replacement: 'Signatur',
            createdAt: DateTime(2026),
            matchMode: 'fuzzy',
            fuzzyThreshold: 0.85,
          ),
        ],
      );

      final row = await stored('new');
      expect(row.triggers, ['sig', 'signatur']);
      expect(row.row.matchMode, 'fuzzy');
      expect(row.row.fuzzyThreshold, 0.85);
      expect(row.row.origin, 'manual');
    });

    test('a failing insert rolls back the update and the delete too', () async {
      await seed('a', ['a']);
      await seed('b', ['b']);

      await expectLater(
        db.applyReplacementImport(
          updates: [
            (id: 'a', triggers: const ['aa']),
          ],
          deleteIds: const ['b'],
          inserts: [
            // Empty trigger list: rejected while the transaction runs.
            ReplacementWrite(
              id: 'broken',
              triggers: const [],
              replacement: 'Kaputt',
              createdAt: DateTime(2026),
            ),
          ],
        ),
        throwsA(anything),
      );

      expect((await db.readAllReplacements()).map((r) => r.row.id).toSet(), {
        'a',
        'b',
      });
      expect((await stored('a')).triggers, ['a']);
    });
  });

  group('ReplacementsNotifier.applyImportPlan', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('overwrite takes the shared trigger and keeps the rest', () async {
      final notifier = container.read(replacementsProvider.notifier);
      await container.read(replacementsProvider.future);
      await notifier.replaceAll(const [
        Replacement(
          id: 'ignored',
          triggers: ['mfg', 'mahlzeit'],
          replacement: 'Gruß',
        ),
      ]);
      final current = container.read(replacementsProvider).value!;

      final plan = planReplacementImport(
        rows: const [
          ReplacementCsvRow(
            triggers: ['mfg'],
            replacement: 'Mit freundlichen Grüßen',
            matchMode: TextReplacementMatchMode.exact,
          ),
        ],
        existing: [
          for (final r in current)
            ReplacementImportExisting(
              id: r.id,
              triggers: r.triggers,
              replacement: r.replacement,
            ),
        ],
        strategy: ReplacementImportStrategy.overwrite,
      );

      await notifier.applyImportPlan(plan);

      final after = await container.read(replacementsProvider.future);
      final byReplacement = {for (final r in after) r.replacement: r.triggers};
      expect(byReplacement['Gruß'], ['mahlzeit']);
      expect(byReplacement['Mit freundlichen Grüßen'], ['mfg']);
      expect(after.length, 2);
    });
  });
}

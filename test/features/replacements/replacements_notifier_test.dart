/// Tests for [ReplacementsNotifier.replaceAll] — the bulk-restore method used
/// by settings import (Cluster 5 portability). Exercised via a
/// [ProviderContainer] against an in-memory DB, without a widget tree.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
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

  test(
    'replaceAll clears existing replacements and inserts the new set',
    () async {
      final notifier = container.read(replacementsProvider.notifier);
      // Wait for the initial build (which auto-inserts sample data).
      await container.read(replacementsProvider.future);

      await notifier.replaceAll(const [
        Replacement(
          id: 'ignored',
          triggers: ['tel'],
          replacement: '+49 123 456789',
        ),
        Replacement(
          id: 'ignored2',
          triggers: ['addr', 'anschrift'],
          replacement: 'Musterstraße 1',
        ),
      ]);

      final result = container.read(replacementsProvider).value!;
      expect(result.length, 2);
      expect(result.map((r) => r.triggers.first), containsAll(['tel', 'addr']));
      expect(
        result.firstWhere((r) => r.triggers.first == 'tel').replacement,
        '+49 123 456789',
      );
      expect(result.firstWhere((r) => r.triggers.first == 'addr').triggers, [
        'addr',
        'anschrift',
      ]);
    },
  );

  test('replaceAll with an empty list removes all replacements', () async {
    final notifier = container.read(replacementsProvider.notifier);
    await container.read(replacementsProvider.future);

    await notifier.replaceAll(const []);

    expect(container.read(replacementsProvider).value, isEmpty);
  });

  test('build() does not reseed sample data for a replacement row with zero '
      'trigger rows (e.g. an incomplete migration backfill)', () async {
    // Bypass the app-level write path entirely, mirroring a row that
    // predates trigger normalization and whose backfill somehow produced
    // no trigger rows — the emptiness check that guards reseeding must
    // key off `text_replacements` row presence, not the joined result.
    await db.customStatement('''
        INSERT INTO text_replacements (id, trigger, replacement, created_at)
        VALUES ('orphan', 'x', 'y', 0)
      ''');

    final result = await container.read(replacementsProvider.future);

    expect(result.length, 1);
    expect(result.single.id, 'orphan');
    // Sample data ('mfg', 'lg', 'tel') must not have been inserted.
    expect(
      result.any((r) => r.triggers.contains('mfg')),
      isFalse,
      reason:
          'Sample data must not be re-seeded when the table already '
          'has rows',
    );
  });
}

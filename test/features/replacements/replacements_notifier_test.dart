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
          trigger: 'tel',
          replacement: '+49 123 456789',
        ),
        Replacement(
          id: 'ignored2',
          trigger: 'addr',
          replacement: 'Musterstraße 1',
        ),
      ]);

      final result = container.read(replacementsProvider).value!;
      expect(result.length, 2);
      expect(result.map((r) => r.trigger), containsAll(['tel', 'addr']));
      expect(
        result.firstWhere((r) => r.trigger == 'tel').replacement,
        '+49 123 456789',
      );
    },
  );

  test('replaceAll with an empty list removes all replacements', () async {
    final notifier = container.read(replacementsProvider.notifier);
    await container.read(replacementsProvider.future);

    await notifier.replaceAll(const []);

    expect(container.read(replacementsProvider).value, isEmpty);
  });
}

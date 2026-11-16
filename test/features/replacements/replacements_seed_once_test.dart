/// Sample replacements are seeded once, on the first start, and never again
/// after the user has cleared the list (UIA-DIC-04).
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [historyDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('an empty list is seeded on the very first start', () async {
    final rows = await newContainer().read(replacementsProvider.future);
    expect(rows, hasLength(3));
  });

  test('clearing the list does not bring the samples back', () async {
    final first = await newContainer().read(replacementsProvider.future);
    for (final r in first) {
      await db.deleteReplacement(r.id);
    }

    final rows = await newContainer().read(replacementsProvider.future);
    expect(rows, isEmpty);
  });
}

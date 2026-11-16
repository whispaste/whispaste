// UIA-SNP-01: replacing the snippet library by an import is all or nothing. A
// failing row leaves the existing library in place instead of an empty or
// half-written one.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

void main() {
  test(
    'a failing import leaves the existing snippets untouched (UIA-SNP-01)',
    () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWith((ref) => db)],
      );
      addTearDown(container.dispose);

      await db.upsertSnippetWithFields(
        id: 'old',
        title: 'Old',
        body: 'kept',
        kind: 'static',
        fieldNames: const [],
        createdAt: DateTime(2026, 1, 1),
      );
      await container.read(snippetsProvider.future);
      await db.customStatement('''
        CREATE TRIGGER fail_boom BEFORE INSERT ON snippets
        WHEN NEW.title = 'boom'
        BEGIN SELECT RAISE(ABORT, 'disk full'); END
      ''');

      await expectLater(
        container.read(snippetsProvider.notifier).replaceAll([
          SnippetItem(
            createdAt: DateTime(2026),
            id: 'a',
            title: 'New',
            body: 'first',
          ),
          SnippetItem(
            createdAt: DateTime(2026),
            id: 'b',
            title: 'boom',
            body: 'second',
          ),
        ]),
        throwsA(anything),
      );

      final rows = await db.select(db.snippets).get();
      expect(rows.map((r) => r.title), ['Old']);
    },
  );
}

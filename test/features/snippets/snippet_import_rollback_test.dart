// UIA-SNP-01: replacing the snippet library by an import is all or nothing. A
// failing row leaves the existing library in place instead of an empty or
// half-written one.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

class _FailingOnBoomDb extends HistoryDatabase {
  _FailingOnBoomDb() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> upsertSnippetWithFields({
    required String id,
    required String title,
    required String body,
    required DateTime createdAt,
    String kind = 'static',
    List<String> fieldNames = const [],
  }) async {
    if (title == 'boom') throw StateError('disk full');
    return super.upsertSnippetWithFields(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      kind: kind,
      fieldNames: fieldNames,
    );
  }
}

void main() {
  test(
    'a failing import leaves the existing snippets untouched (UIA-SNP-01)',
    () async {
      final db = _FailingOnBoomDb();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWith((ref) => db)],
      );
      addTearDown(container.dispose);

      await db.upsertSnippetWithFields(
        id: 'old',
        title: 'Old',
        body: 'kept',
        createdAt: DateTime(2026, 1, 1),
      );
      await container.read(snippetsProvider.future);

      await expectLater(
        container.read(snippetsProvider.notifier).replaceAll([
          const SnippetItem(id: 'a', title: 'New', body: 'first'),
          const SnippetItem(id: 'b', title: 'boom', body: 'second'),
        ]),
        throwsA(isA<StateError>()),
      );

      final rows = await db.select(db.snippets).get();
      expect(rows.map((r) => r.title), ['Old']);
    },
  );
}

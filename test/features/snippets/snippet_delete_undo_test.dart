/// Deleting a Textbaustein moves it to the trash (#852): nothing is lost, the
/// restore brings back id, content, kind, timestamps, source note, fields and
/// the favourite star, and only the trash can remove a snippet for good.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

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

  tearDown(() => container.dispose());

  test(
    'moveToTrash() then restore() brings an interactive snippet back exactly',
    () async {
      final notifier = container.read(snippetsProvider.notifier);
      await container.read(snippetsProvider.future);
      final id = await notifier.add(
        'Address',
        'Dear {{name}}, {{street}}',
        kind: 'interactive',
        fields: ['name', 'street'],
      );
      await db.upsertSnippet(
        id: id,
        title: 'Address',
        body: 'Dear {{name}}, {{street}}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        kind: 'interactive',
        sourceNoteId: 'note-1',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000100000),
      );
      await notifier.setFavourite(id, value: true);
      final before = (await db.readSnippetWithFields(id))!;

      await notifier.moveToTrash([id]);
      expect(container.read(snippetsProvider).value, isEmpty);
      // Invisible to every reader outside the trash (picker, API, export).
      expect(await db.readAllSnippetsWithFields(), isEmpty);
      expect(await db.readTrashedSnippetsWithFields(), hasLength(1));

      await notifier.restore([id]);

      final after = (await db.readSnippetWithFields(id))!;
      expect(after.row, before.row);
      expect(after.fields, ['name', 'street']);
      expect(container.read(snippetsProvider).value!.single.isFavorite, isTrue);
      expect(await container.read(snippetsTrashProvider.future), isEmpty);
    },
  );

  test('deleteForever() removes trashed snippets only', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);
    final keep = await notifier.add('Keep', 'body');
    final gone = await notifier.add('Gone', 'body');
    await notifier.moveToTrash([gone]);

    // An active snippet is not touched even when its id is passed.
    expect(await notifier.deleteForever([keep, gone]), 1);
    expect(container.read(snippetsProvider).value!.single.id, keep);
    expect(await db.readTrashedSnippetsWithFields(), isEmpty);
  });

  test('emptyTrash() and the retention purge leave active ones', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);
    await notifier.add('Active', 'body');
    final a = await notifier.add('A', 'body');
    final b = await notifier.add('B', 'body');
    await notifier.moveToTrash([a, b]);

    // Nothing is older than the cutoff yet.
    expect(
      await db.purgeSnippetsTrashBefore(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
      0,
    );
    expect(await notifier.emptyTrash(), 2);
    expect(container.read(snippetsProvider).value, hasLength(1));
  });

  test('the favourite star is not an edit', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);
    final id = await notifier.add('Star', 'body');
    final changed = (await db.readSnippetWithFields(id))!.row.updatedAt;

    await notifier.setFavourite(id, value: true);

    expect((await db.readSnippetWithFields(id))!.row.updatedAt, changed);
    expect(
      favouritesFirst([
        SnippetItem(id: 'x', title: 'x', body: '', createdAt: DateTime(2026)),
        SnippetItem(
          id: 'y',
          title: 'y',
          body: '',
          createdAt: DateTime(2026),
          isFavorite: true,
        ),
      ]).map((s) => s.id),
      ['y', 'x'],
    );
  });

  test('replaceAll() (settings import) keeps the trash', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);
    final id = await notifier.add('Trashed', 'body');
    await notifier.moveToTrash([id]);

    await notifier.replaceAll([
      SnippetItem(id: 'n', title: 'New', body: 'b', createdAt: DateTime(2026)),
    ]);

    expect(container.read(snippetsProvider).value!.single.title, 'New');
    expect(await db.readTrashedSnippetsWithFields(), hasLength(1));
  });
}

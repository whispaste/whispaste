/// Tests for [SnippetsNotifier] — add/edit/delete for the Snippets settings
/// page (dictation-automations ticket 05). Exercised via a
/// [ProviderContainer] against an in-memory DB, without a widget tree.
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

  tearDown(() {
    container.dispose();
  });

  test('build() starts empty — no sample data is seeded', () async {
    final result = await container.read(snippetsProvider.future);
    expect(result, isEmpty);
  });

  test('add() persists a new snippet with its title and body', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);

    await notifier.add('Greeting', 'Hello,\nthanks for reaching out.');

    final result = container.read(snippetsProvider).value!;
    expect(result, hasLength(1));
    expect(result.single.title, 'Greeting');
    expect(result.single.body, 'Hello,\nthanks for reaching out.');
  });

  test('updateSnippet() changes title and body of an existing row', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);
    await notifier.add('Greeting', 'Hello');
    final id = container.read(snippetsProvider).value!.single.id;

    await notifier.updateSnippet(id, title: 'Signoff', body: 'Best regards');

    final result = container.read(snippetsProvider).value!;
    expect(result, hasLength(1));
    expect(result.single.title, 'Signoff');
    expect(result.single.body, 'Best regards');
  });

  test('remove() deletes the snippet', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);
    await notifier.add('Greeting', 'Hello');

    final id = container.read(snippetsProvider).value!.single.id;
    await notifier.remove(id);

    expect(container.read(snippetsProvider).value, isEmpty);
  });

  test('build() returns snippets in creation order', () async {
    final notifier = container.read(snippetsProvider.notifier);
    await container.read(snippetsProvider.future);

    await notifier.add('first', 'body 1');
    await notifier.add('second', 'body 2');

    final result = await container.refresh(snippetsProvider.future);
    expect(result.map((s) => s.title).toList(), ['first', 'second']);
  });

  test(
    'replaceAll() replaces the entire set with the given items in order',
    () async {
      final notifier = container.read(snippetsProvider.notifier);
      await container.read(snippetsProvider.future);
      await notifier.add('old', 'stale body');

      await notifier.replaceAll(const [
        SnippetItem(id: '', title: 'new-1', body: 'body 1'),
        SnippetItem(id: '', title: 'new-2', body: 'body 2'),
      ]);

      final result = container.read(snippetsProvider).value!;
      expect(result.map((s) => s.title).toList(), ['new-1', 'new-2']);
    },
  );
}

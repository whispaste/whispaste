/// Tests for [AutomationsNotifier] — add/edit/delete for the Automations
/// settings page (dictation-automations ticket 02). Exercised via a
/// [ProviderContainer] against an in-memory DB, without a widget tree.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/automations/automations_page.dart';

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
    final result = await container.read(automationsProvider.future);
    expect(result, isEmpty);
  });

  test('add() persists a new automation with its trigger and URL', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);

    await notifier.add('open timer', 'https://example.com/timer');

    final result = container.read(automationsProvider).value!;
    expect(result, hasLength(1));
    expect(result.single.trigger, 'open timer');
    expect(result.single.url, 'https://example.com/timer');
  });

  test(
    'updateAutomation() changes trigger and URL of an existing row',
    () async {
      final notifier = container.read(automationsProvider.notifier);
      await container.read(automationsProvider.future);
      await notifier.add('open timer', 'https://example.com/timer');
      final id = container.read(automationsProvider).value!.single.id;

      await notifier.updateAutomation(
        id,
        trigger: 'start timer',
        url: 'https://example.com/timer2',
      );

      final result = container.read(automationsProvider).value!;
      expect(result, hasLength(1));
      expect(result.single.trigger, 'start timer');
      expect(result.single.url, 'https://example.com/timer2');
    },
  );

  test('remove() deletes the automation', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);
    await notifier.add('open timer', 'https://example.com/timer');

    final id = container.read(automationsProvider).value!.single.id;
    await notifier.remove(id);

    expect(container.read(automationsProvider).value, isEmpty);
  });

  test('build() returns automations in creation order', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);

    await notifier.add('first', 'https://example.com/1');
    await notifier.add('second', 'https://example.com/2');

    final result = await container.refresh(automationsProvider.future);
    expect(result.map((a) => a.trigger).toList(), ['first', 'second']);
  });

  test('a row with a malformed payload surfaces as an empty URL instead of '
      'crashing the list', () async {
    await db.customStatement('''
        INSERT INTO automations (id, trigger, action_type, payload, created_at)
        VALUES ('a1', 'broken', 'open_url', 'not json', 0)
      ''');

    final result = await container.read(automationsProvider.future);

    expect(result, hasLength(1));
    expect(result.single.trigger, 'broken');
    expect(result.single.url, '');
  });
}

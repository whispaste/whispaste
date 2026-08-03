/// Tests for [AutomationsNotifier] — add/edit/delete for the Automations
/// settings page (dictation-automations tickets 02/03). Exercised via a
/// [ProviderContainer] against an in-memory DB, without a widget tree.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/automations/automations_page.dart';
import 'package:whispaste/services/automation_dispatch_service.dart';

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

  test('add() persists a new openUrl automation with its trigger and '
      'URL', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);

    await notifier.add(
      trigger: 'open timer',
      actionType: AutomationActionType.openUrl,
      actionValue: 'https://example.com/timer',
    );

    final result = container.read(automationsProvider).value!;
    expect(result, hasLength(1));
    expect(result.single.trigger, 'open timer');
    expect(result.single.actionType, AutomationActionType.openUrl);
    expect(result.single.actionValue, 'https://example.com/timer');
  });

  test('add() persists a shellCommand automation and reads the command '
      'back', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);

    await notifier.add(
      trigger: 'lock screen',
      actionType: AutomationActionType.shellCommand,
      actionValue: 'pmset displaysleepnow',
    );

    final result = container.read(automationsProvider).value!;
    expect(result, hasLength(1));
    expect(result.single.trigger, 'lock screen');
    expect(result.single.actionType, AutomationActionType.shellCommand);
    expect(result.single.actionValue, 'pmset displaysleepnow');
  });

  test('add() stores the shellCommand payload in the exact shape the '
      'dispatch service decodes', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);

    await notifier.add(
      trigger: 'lock screen',
      actionType: AutomationActionType.shellCommand,
      actionValue: 'pmset displaysleepnow',
    );

    final row = (await db.readAllAutomations()).single;
    expect(row.actionType, 'shell_command');
    expect(jsonDecode(row.payload), {'command': 'pmset displaysleepnow'});
    expect(decodeShellCommandPayload(row.payload), 'pmset displaysleepnow');
  });

  test(
    'updateAutomation() changes trigger and URL of an existing row',
    () async {
      final notifier = container.read(automationsProvider.notifier);
      await container.read(automationsProvider.future);
      await notifier.add(
        trigger: 'open timer',
        actionType: AutomationActionType.openUrl,
        actionValue: 'https://example.com/timer',
      );
      final id = container.read(automationsProvider).value!.single.id;

      await notifier.updateAutomation(
        id,
        trigger: 'start timer',
        actionType: AutomationActionType.openUrl,
        actionValue: 'https://example.com/timer2',
      );

      final result = container.read(automationsProvider).value!;
      expect(result, hasLength(1));
      expect(result.single.trigger, 'start timer');
      expect(result.single.actionValue, 'https://example.com/timer2');
    },
  );

  test('updateAutomation() can switch an openUrl automation over to '
      'shellCommand', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);
    await notifier.add(
      trigger: 'open timer',
      actionType: AutomationActionType.openUrl,
      actionValue: 'https://example.com/timer',
    );
    final id = container.read(automationsProvider).value!.single.id;

    await notifier.updateAutomation(
      id,
      trigger: 'open timer',
      actionType: AutomationActionType.shellCommand,
      actionValue: 'open -a Clock',
    );

    final result = container.read(automationsProvider).value!;
    expect(result, hasLength(1));
    expect(result.single.actionType, AutomationActionType.shellCommand);
    expect(result.single.actionValue, 'open -a Clock');
  });

  test('remove() deletes the automation', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);
    await notifier.add(
      trigger: 'open timer',
      actionType: AutomationActionType.openUrl,
      actionValue: 'https://example.com/timer',
    );

    final id = container.read(automationsProvider).value!.single.id;
    await notifier.remove(id);

    expect(container.read(automationsProvider).value, isEmpty);
  });

  test('build() returns a mixed list of both action types in creation '
      'order', () async {
    final notifier = container.read(automationsProvider.notifier);
    await container.read(automationsProvider.future);

    await notifier.add(
      trigger: 'first',
      actionType: AutomationActionType.openUrl,
      actionValue: 'https://example.com/1',
    );
    await notifier.add(
      trigger: 'second',
      actionType: AutomationActionType.shellCommand,
      actionValue: 'say hello',
    );

    final result = await container.refresh(automationsProvider.future);
    expect(result.map((a) => a.trigger).toList(), ['first', 'second']);
    expect(result.map((a) => a.actionType).toList(), [
      AutomationActionType.openUrl,
      AutomationActionType.shellCommand,
    ]);
    expect(result.map((a) => a.actionValue).toList(), [
      'https://example.com/1',
      'say hello',
    ]);
  });

  test('a row with a malformed payload surfaces as an empty value instead '
      'of crashing the list', () async {
    await db.customStatement('''
        INSERT INTO automations (id, trigger, action_type, payload, created_at)
        VALUES ('a1', 'broken', 'open_url', 'not json', 0)
      ''');

    final result = await container.read(automationsProvider.future);

    expect(result, hasLength(1));
    expect(result.single.trigger, 'broken');
    expect(result.single.actionValue, '');
  });

  test('a row with an unknown action type falls back to openUrl with an '
      'empty value instead of crashing the list', () async {
    await db.customStatement('''
        INSERT INTO automations (id, trigger, action_type, payload, created_at)
        VALUES ('a2', 'future', 'run_script', '{"script": "x"}', 0)
      ''');

    final result = await container.read(automationsProvider.future);

    expect(result, hasLength(1));
    expect(result.single.trigger, 'future');
    expect(result.single.actionType, AutomationActionType.openUrl);
    expect(result.single.actionValue, '');
  });
}

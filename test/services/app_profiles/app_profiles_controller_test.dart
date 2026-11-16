/// Write methods of [AppProfilesController] (ticket 13, part 1): create,
/// rename, delete and reorder, each read back through the real database.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [historyDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  AppProfilesController controller() =>
      container.read(appProfilesProvider.notifier);

  List<String> ids() => container
      .read(appProfilesProvider)
      .requireValue
      .map((p) => p.id)
      .toList();

  Future<void> loaded() => container.read(appProfilesProvider.future);

  test('save creates a profile at the end of the list', () async {
    await loaded();
    await controller().save(const AppProfile(id: 'a', name: 'Mail'));
    await controller().save(const AppProfile(id: 'b', name: 'Notizen'));

    expect(ids(), ['a', 'b']);
  });

  test('save with an existing id renames it and keeps its position', () async {
    await loaded();
    await controller().save(const AppProfile(id: 'a', name: 'Mail'));
    await controller().save(const AppProfile(id: 'b', name: 'Notizen'));
    await controller().save(const AppProfile(id: 'a', name: 'E-Mail'));

    final profiles = container.read(appProfilesProvider).requireValue;
    expect(profiles.map((p) => p.id), ['a', 'b']);
    expect(profiles.first.name, 'E-Mail');
  });

  test('save stores the rules of the profile', () async {
    await loaded();
    const rule = AppMatchRule(identifier: 'com.apple.mail');
    await controller().save(
      const AppProfile(id: 'a', name: 'Mail', rules: [rule]),
    );

    final stored = container.read(appProfilesProvider).requireValue.single;
    expect(stored.rules, [rule]);
  });

  test('delete removes the profile and its rules', () async {
    await loaded();
    await controller().save(
      const AppProfile(
        id: 'a',
        name: 'Mail',
        rules: [AppMatchRule(identifier: 'com.apple.mail')],
      ),
    );
    await controller().save(const AppProfile(id: 'b', name: 'Notizen'));

    await controller().delete('a');

    expect(ids(), ['b']);
    expect(await db.readAppProfileRules(), isEmpty);
  });

  test('delete of an unknown id changes nothing', () async {
    await loaded();
    await controller().save(const AppProfile(id: 'a', name: 'Mail'));

    await controller().delete('missing');

    expect(ids(), ['a']);
  });

  test('reorder applies the given order', () async {
    await loaded();
    await controller().save(const AppProfile(id: 'a', name: 'Mail'));
    await controller().save(const AppProfile(id: 'b', name: 'Notizen'));
    await controller().save(const AppProfile(id: 'c', name: 'Code'));

    await controller().reorder(['c', 'a', 'b']);

    expect(ids(), ['c', 'a', 'b']);
  });

  test(
    'reorder keeps profiles missing from the list, in their order',
    () async {
      await loaded();
      await controller().save(const AppProfile(id: 'a', name: 'Mail'));
      await controller().save(const AppProfile(id: 'b', name: 'Notizen'));
      await controller().save(const AppProfile(id: 'c', name: 'Code'));

      await controller().reorder(['c']);

      expect(ids(), ['c', 'a', 'b']);
    },
  );

  test('a new profile after a delete goes to the end', () async {
    await loaded();
    await controller().save(const AppProfile(id: 'a', name: 'Mail'));
    await controller().save(const AppProfile(id: 'b', name: 'Notizen'));
    await controller().delete('a');

    await controller().save(const AppProfile(id: 'c', name: 'Code'));

    expect(ids(), ['b', 'c']);
  });
}

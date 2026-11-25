/// Contact names in the dictionary (#2036, schema v48): the import group in
/// the database, its removal, the update, the detach on edit, the settings
/// restore and export, and that contact names never reach the text every
/// engine reads (cloud engines included).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/auto_terms_sync.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/dictionary/contact_terms.dart';
import 'package:whispaste/services/settings_portability_service.dart';

class _MemorySettings extends SettingsNotifier {
  _MemorySettings(this._initial);
  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.requireValue));
  }
}

final _t = DateTime(2026);

Future<void> _import(
  HistoryDatabase db, {
  String group = 'g1',
  List<String> add = const [],
  List<String> removeIds = const [],
  DateTime? consentedAt,
}) => db.applyContactNameImport(
  groupId: group,
  sourceKind: 'file',
  sourceLabel: 'team.vcf',
  consentedAt: consentedAt ?? _t,
  add: [for (final n in add) (id: '$group-$n', name: n)],
  removeIds: removeIds,
  now: _t,
);

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.writeAppSettings({'replacementsSamplesSeeded': '1'});
    await db.upsertReplacementWithTriggers(
      id: 'own',
      triggers: const ['Kubernetes'],
      replacement: 'Kubernetes',
      createdAt: _t,
    );
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWith(
          () => _MemorySettings(
            AppSettings.defaults.copyWithSections(
              stt: AppSettings.defaults.stt.copyWith(termsMigrated: true),
            ),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<Replacement>> entries() async {
    await container.read(replacementsProvider.notifier).reload();
    return container.read(replacementsProvider.future);
  }

  Future<Map<String, String?>> groupOf() async => {
    for (final r in await entries()) r.replacement: r.importGroupId,
  };

  test('an import stores the group with its consent and the names as '
      'term entries tied to it', () async {
    await _import(db, add: ['Lea Wolf', 'Ida Berg']);

    final group = (await db.readContactNameGroups()).single;
    expect(group.id, 'g1');
    expect(group.sourceKind, 'file');
    expect(group.sourceLabel, 'team.vcf');
    expect(group.consentedAt, _t);
    expect(await groupOf(), {
      'Kubernetes': null,
      'Lea Wolf': 'g1',
      'Ida Berg': 'g1',
    });
    final lea = (await entries()).firstWhere(
      (r) => r.replacement == 'Lea Wolf',
    );
    expect(lea.triggers, ['Lea Wolf']);
  });

  test('an update adds and removes; an edited name has left the group and '
      'stays', () async {
    await _import(db, add: ['Lea Wolf', 'Ida Berg', 'Alt Person']);
    final ida = (await entries()).firstWhere(
      (r) => r.replacement == 'Ida Berg',
    );
    await container
        .read(replacementsProvider.notifier)
        .updateReplacement(
          ida.id,
          triggers: const ['Ida Berg', 'Ida'],
          replacement: 'Ida Berg',
          createdAt: ida.createdAt,
          origin: ida.origin,
        );

    await _import(
      db,
      add: ['Neu Person'],
      removeIds: ['g1-Alt Person', ida.id],
      consentedAt: DateTime(2030),
    );

    expect(await groupOf(), {
      'Kubernetes': null,
      'Lea Wolf': 'g1',
      'Ida Berg': null,
      'Neu Person': 'g1',
    });
    // The update keeps the consent of the first import.
    expect((await db.readContactNameGroups()).single.consentedAt, _t);
  });

  test('removing a group (withdrawing consent) removes its names in one '
      'step, nothing else', () async {
    await _import(db, add: ['Lea Wolf']);
    await _import(db, group: 'g2', add: ['Ida Berg']);

    await db.deleteContactNameGroup('g1');

    expect((await db.readContactNameGroups()).map((g) => g.id), ['g2']);
    expect(await groupOf(), {'Kubernetes': null, 'Ida Berg': 'g2'});
    final triggers = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM text_replacement_triggers '
          "WHERE replacement_id = 'g1-Lea Wolf'",
        )
        .getSingle();
    expect(triggers.data['c'], 0);
  });

  test('contact names never enter the text every engine reads, only the '
      'local list', () async {
    await _import(db, add: ['Lea Wolf', 'Ida Berg']);

    await syncAutoTerms(container);

    final stt = container.read(settingsProvider).requireValue.stt;
    expect(stt.customVocabulary, 'Kubernetes');
    expect(container.read(contactTermsProvider), ['Lea Wolf', 'Ida Berg']);
    expect(
      localVocabularyHint(stt.customVocabulary, [
        ...container.read(contactTermsProvider),
      ]),
      'Kubernetes, Lea Wolf, Ida Berg',
    );

    await db.deleteContactNameGroup('g1');
    await container.read(replacementsProvider.notifier).reload();
    await syncAutoTerms(container);
    expect(container.read(contactTermsProvider), isEmpty);
  });

  test('a settings export leaves contact names out, a restore keeps '
      'them', () async {
    await _import(db, add: ['Lea Wolf']);

    final bundle = buildSettingsExportBundle(
      settings: AppSettings.defaults,
      replacements: await entries(),
      snippets: const [],
    );
    expect(bundle.replacements.map((r) => r.replacement), ['Kubernetes']);

    await db.writeReplacements([
      ReplacementWrite(
        id: 'restored',
        triggers: const ['Grafana'],
        replacement: 'Grafana',
        createdAt: _t,
      ),
    ], replaceAll: true);
    expect(await groupOf(), {'Lea Wolf': 'g1', 'Grafana': null});
    expect(await db.readContactNameGroups(), hasLength(1));
  });

  test('upgrade from 47 adds the group table and column, entries '
      'stay', () async {
    final dir = Directory.systemTemp.createTempSync('wp2036_v48_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/history.sqlite');
    final first = HistoryDatabase.forTesting(NativeDatabase(file));
    await first.upsertReplacementWithTriggers(
      id: 'old',
      triggers: const ['mfg'],
      replacement: 'Mit freundlichen Grüßen',
      createdAt: _t,
    );
    await first.customStatement('DROP TABLE contact_name_groups');
    await first.customStatement(
      'DROP INDEX IF EXISTS idx_text_replacements_import_group_id',
    );
    await first.customStatement(
      'ALTER TABLE text_replacements DROP COLUMN import_group_id',
    );
    await first.customStatement('PRAGMA user_version = 47');
    await first.close();

    final upgraded = HistoryDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);
    expect(await upgraded.readContactNameGroups(), isEmpty);
    await _import(upgraded, add: ['Lea Wolf']);
    final rows = await upgraded
        .customSelect(
          'SELECT id, import_group_id FROM text_replacements ORDER BY id',
        )
        .get();
    expect(
      [for (final r in rows) (r.data['id'], r.data['import_group_id'])],
      [('g1-Lea Wolf', 'g1'), ('old', null)],
    );
    final version = await upgraded
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], upgraded.schemaVersion);
    expect(upgraded.schemaVersion, 48);
  });
}

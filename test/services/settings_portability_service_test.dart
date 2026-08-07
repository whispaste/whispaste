/// Tests for [SettingsPortabilityService] — encode/decode + file IO for the
/// deny-list-filtered full settings export/import bundle (format v2), v1
/// backward compatibility, and the anti-obsolescence check.
///
/// Uses `MemoryFileSystem` (same seam as `FactoryResetCoordinator`) so no
/// real disk IO happens in tests.
library;

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/settings_portability_service.dart';

void main() {
  late MemoryFileSystem fs;
  late SettingsPortabilityService service;

  setUp(() {
    fs = MemoryFileSystem.test();
    service = SettingsPortabilityService(fileSystem: fs);
  });

  final sampleSettings = <String, String>{
    ...const AppSettings().toStorageMap(),
    'custom_vocabulary': 'Silvio, WhisPaste, Whispaste',
    'hotkey_enabled': 'true',
    'hotkey_key': 'F',
    'hotkey_key_display': 'F',
    'hotkey_modifiers': 'ctrl+alt',
  };

  const sampleReplacements = [
    Replacement(
      id: 'a',
      triggers: ['mfg', 'mfg2'],
      replacement: 'Mit freundlichen Grüßen',
    ),
    Replacement(id: 'b', triggers: ['lg'], replacement: 'Liebe Grüße'),
  ];

  SettingsExportBundle sampleBundle() => SettingsExportBundle(
    settings: Map.of(sampleSettings),
    replacements: sampleReplacements,
  );

  // ---------------------------------------------------------------------------
  // AC1: export writes a v2 JSON file with settings/replacements/snippets.
  // ---------------------------------------------------------------------------

  test('exportToFile writes format_version 2 JSON containing the settings map '
      'and replacements', () async {
    await service.exportToFile('/exports/settings.json', sampleBundle());

    final written = await fs.file('/exports/settings.json').readAsString();
    expect(written, contains('"format_version": 2'));
    expect(written, contains('"settings"'));
    expect(written, contains('Silvio, WhisPaste, Whispaste'));
    expect(written, contains('"replacements"'));
    expect(written, contains('"triggers"'));
    expect(written, contains('mfg'));
    expect(written, contains('mfg2'));
    expect(written, contains('Mit freundlichen Grüßen'));
  });

  // ---------------------------------------------------------------------------
  // AC2: import restores settings and replacements from the file.
  // ---------------------------------------------------------------------------

  test('importFromFile restores settings and replacements', () async {
    await service.exportToFile('/exports/settings.json', sampleBundle());

    final restored = await service.importFromFile('/exports/settings.json');

    expect(
      restored.settings['custom_vocabulary'],
      'Silvio, WhisPaste, Whispaste',
    );
    expect(restored.settings['hotkey_modifiers'], 'ctrl+alt');
    expect(restored.replacements, hasLength(sampleReplacements.length));
    for (var i = 0; i < sampleReplacements.length; i++) {
      expect(restored.replacements[i].triggers, sampleReplacements[i].triggers);
      expect(
        restored.replacements[i].replacement,
        sampleReplacements[i].replacement,
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC3: round-trip export → import yields an identical configuration.
  // ---------------------------------------------------------------------------

  test('round trip: export then import yields identical, deny-list-filtered '
      'settings', () async {
    final bundle = SettingsExportBundle(
      settings: Map.of(sampleSettings)
        ..['theme_mode'] = 'light'
        ..['locale'] = 'de'
        ..['stt_model'] = 'whisper-large-v3-turbo',
      replacements: const [
        Replacement(
          id: 'x',
          triggers: ['tel', 'telefon'],
          replacement: '+49 123 456789',
        ),
      ],
    );

    await service.exportToFile('/roundtrip.json', bundle);
    final restored = await service.importFromFile('/roundtrip.json');

    for (final key in settingsPortabilityPortableKeysForTest) {
      expect(restored.settings[key], bundle.settings[key], reason: key);
    }
    expect(restored.replacements, hasLength(bundle.replacements.length));
    for (var i = 0; i < bundle.replacements.length; i++) {
      expect(
        restored.replacements[i].triggers,
        bundle.replacements[i].triggers,
      );
      expect(
        restored.replacements[i].replacement,
        bundle.replacements[i].replacement,
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC3b: the JSON-level roundtrip above only proves encode/decode are
  // symmetric — it says nothing about whether the values actually land
  // correctly through `mergeImportedSettings` onto a *different* starting
  // state (User Story 1: "move to a fresh install"). Section `toMap`/
  // `fromMap` pairs are not guaranteed to be identity round-trips: e.g.
  // `SttSettings.fromMap` runs `_migrateModelId`, so a legacy display-label
  // value like `'Best Quality (Large)'` normalizes to `'whisper-large-v3-turbo'`
  // on read. Asserting against typed getters (not the re-serialized storage
  // map — that would just compare two normalized strings and hide the
  // normalization step) and seeding a value only a real older export would
  // contain is what actually exercises that path.
  // ---------------------------------------------------------------------------

  test('export of a non-default state, then import onto AppSettings.defaults, '
      'lands the same values for every portable key — including a legacy '
      'model label that must normalize through SttSettings.fromMap', () async {
    // Every value below is deliberately chosen to differ from
    // `AppSettings.defaults` (dark / en / whisper-medium / whisper /
    // false / '' / 120) — an assertion that happens to match the default
    // would pass whether or not the merge actually carried the value, and
    // `text_replacements_enabled` is exactly the field PRD Schmerzpunkt 1
    // is about ("Daten wandern, der zugehörige Schalter nicht").
    final nonDefault = Map.of(sampleSettings)
      ..['theme_mode'] = 'light'
      ..['locale'] = 'de'
      ..['stt_model'] = 'Best Quality (Large)'
      ..['stt_engine'] = 'parakeet'
      ..['text_replacements_enabled'] = 'true'
      ..['snippet_picker_trigger'] = 'go'
      ..['max_record_duration'] = '600';
    final bundle = SettingsExportBundle(
      settings: nonDefault,
      replacements: const [],
    );

    await service.exportToFile('/roundtrip-merge.json', bundle);
    final restored = await service.importFromFile('/roundtrip-merge.json');
    final merged = mergeImportedSettings(
      AppSettings.defaults,
      restored.settings,
    );

    expect(merged.themeMode, ThemeMode.light);
    expect(merged.locale, 'de');
    // Normalized, not the raw legacy label fed in — proves the merge
    // actually runs through SttSettings.fromMap rather than bypassing it.
    expect(merged.stt.model, 'whisper-large-v3-turbo');
    expect(merged.stt.engine, 'parakeet');
    expect(merged.behavior.textReplacementsEnabled, true);
    expect(merged.behavior.snippetPickerTrigger, 'go');
    expect(merged.behavior.maxRecordDuration, 600);
  });

  test('importing a settings map with a key unknown to this build is silently '
      'dropped — no throw, neighbouring known keys still merge', () async {
    final imported = Map.of(sampleSettings)
      ..['theme_mode'] = 'light'
      ..['a_future_key_this_build_does_not_know'] = 'some-value';

    expect(
      () => mergeImportedSettings(AppSettings.defaults, imported),
      returnsNormally,
    );
    final merged = mergeImportedSettings(AppSettings.defaults, imported);
    expect(merged.themeMode, ThemeMode.light);
  });

  // ---------------------------------------------------------------------------
  // Deny list: filtered on export (bundle assumed pre-filtered by the
  // caller — see below) and filtered *again* on import, so a hand-edited or
  // foreign-version file cannot smuggle denied keys back in.
  // ---------------------------------------------------------------------------

  test(
    'push_to_talk and input_gain travel with the export; only microphone '
    'from AudioInputSettings is excluded (key-exact, not section-wide)',
    () async {
      final bundle = SettingsExportBundle(
        settings: Map.of(sampleSettings)
          ..['push_to_talk'] = 'true'
          ..['input_gain'] = '2.0'
          ..['microphone'] = 'Should Not Travel',
        replacements: const [],
      );

      await service.exportToFile('/settings.json', bundle);
      final written = await fs.file('/settings.json').readAsString();
      final decoded = jsonDecode(written) as Map<String, dynamic>;
      final settingsMap = decoded['settings'] as Map<String, dynamic>;

      expect(settingsMap['push_to_talk'], 'true');
      expect(settingsMap['input_gain'], '2.0');
      expect(settingsMap.containsKey('microphone'), isFalse);
    },
  );

  for (final deniedKey in settingsPortabilityDenyList) {
    test('exportToFile never writes deny-listed key "$deniedKey" even if the '
        'caller-supplied bundle contains it', () async {
      final bundle = SettingsExportBundle(
        settings: Map.of(sampleSettings)..[deniedKey] = 'leaked-value',
        replacements: const [],
      );

      await service.exportToFile('/settings.json', bundle);
      final written = await fs.file('/settings.json').readAsString();
      final decoded = jsonDecode(written) as Map<String, dynamic>;
      final settingsMap = decoded['settings'] as Map<String, dynamic>;

      expect(settingsMap.containsKey(deniedKey), isFalse);
    });
  }

  test(
    'importFromFile strips deny-listed keys from a hand-written import file',
    () async {
      await fs
          .file('/foreign.json')
          .writeAsString(
            jsonEncode({
              'format_version': 2,
              'settings': {
                'theme_mode': 'light',
                'window_x': '999',
                'window_maximized': 'true',
                'onboarding_completed': 'true',
                'microphone': 'Foreign Mic',
              },
              'replacements': <Object?>[],
              'custom_vocabulary': '',
              'hotkey': const HotkeySettings().toMap(),
            }),
          );

      final restored = await service.importFromFile('/foreign.json');

      expect(restored.settings['theme_mode'], 'light');
      expect(restored.settings.containsKey('window_x'), isFalse);
      expect(restored.settings.containsKey('window_maximized'), isFalse);
      expect(restored.settings.containsKey('onboarding_completed'), isFalse);
      expect(restored.settings.containsKey('microphone'), isFalse);
    },
  );

  test('the four settings_export_path/settings_import_path/*_bookmark keys '
      '(Ticket 03) never leave via export and cannot smuggle a foreign '
      'machine-bound path back in on import — the local value wins', () async {
    final bundle = SettingsExportBundle(
      settings: Map.of(sampleSettings)
        ..['settings_export_path'] = '/leaked/export.json'
        ..['settings_import_path'] = '/leaked/import.json'
        ..['settings_export_bookmark'] = 'leaked-bookmark-export'
        ..['settings_import_bookmark'] = 'leaked-bookmark-import',
      replacements: const [],
    );

    await service.exportToFile('/settings.json', bundle);
    final written = await fs.file('/settings.json').readAsString();
    final decoded = jsonDecode(written) as Map<String, dynamic>;
    final settingsMap = decoded['settings'] as Map<String, dynamic>;
    for (final key in [
      'settings_export_path',
      'settings_import_path',
      'settings_export_bookmark',
      'settings_import_bookmark',
    ]) {
      expect(settingsMap.containsKey(key), isFalse, reason: key);
    }

    // A hand-written import file that smuggles these in anyway must not
    // move the *local* machine's remembered path — mergeImportedSettings
    // filters the import map before merging onto `current`, so `current`'s
    // portabilityPaths values simply survive untouched.
    final local = AppSettings.defaults.copyWithSections(
      portabilityPaths: const SettingsPortabilityPathSettings(
        exportPath: '/local/export.json',
        importPath: '/local/import.json',
        exportBookmark: 'local-bookmark-export',
        importBookmark: 'local-bookmark-import',
      ),
    );
    final foreignImport = {
      ...sampleSettings,
      'settings_export_path': '/leaked/export.json',
      'settings_import_path': '/leaked/import.json',
      'settings_export_bookmark': 'leaked-bookmark-export',
      'settings_import_bookmark': 'leaked-bookmark-import',
    };
    final merged = mergeImportedSettings(local, foreignImport);

    expect(merged.portabilityPaths.exportPath, '/local/export.json');
    expect(merged.portabilityPaths.importPath, '/local/import.json');
    expect(merged.portabilityPaths.exportBookmark, 'local-bookmark-export');
    expect(merged.portabilityPaths.importBookmark, 'local-bookmark-import');
  });

  // ---------------------------------------------------------------------------
  // v2 structure: root still carries v1-compat "hotkey"/"custom_vocabulary",
  // derived from the same settings map — so the already-published v1
  // decoder can still import a v2 file.
  // ---------------------------------------------------------------------------

  test(
    'the encoded v2 JSON structure carries a top-level "hotkey" object and '
    '"replacements" list, matching the values inside "settings" — this is '
    'the guard against a future reader deleting them as "redundant"',
    () async {
      final bundle = sampleBundle();
      await service.exportToFile('/settings.json', bundle);
      final written = await fs.file('/settings.json').readAsString();
      final decoded = jsonDecode(written) as Map<String, dynamic>;

      expect(decoded['format_version'], 2);
      expect(decoded['hotkey'], isA<Map>());
      expect(decoded['replacements'], isA<List>());

      final hotkeyDuplicate = decoded['hotkey'] as Map<String, dynamic>;
      expect(
        hotkeyDuplicate['hotkey_enabled'],
        bundle.settings['hotkey_enabled'],
      );
      expect(hotkeyDuplicate['hotkey_key'], bundle.settings['hotkey_key']);
      expect(
        hotkeyDuplicate['hotkey_key_display'],
        bundle.settings['hotkey_key_display'],
      );
      expect(
        hotkeyDuplicate['hotkey_modifiers'],
        bundle.settings['hotkey_modifiers'],
      );
      expect(
        decoded['custom_vocabulary'],
        bundle.settings['custom_vocabulary'],
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Backward compatibility: v1 files (literal fixtures, not produced by the
  // current encoder — else the test would just check the new encoder
  // against itself).
  // ---------------------------------------------------------------------------

  test('importFromFile reads a literal v1 fixture: custom_vocabulary and the '
      'hotkey object are lifted into the flat settings map', () async {
    await fs
        .file('/legacy.json')
        .writeAsString(
          jsonEncode({
            'format_version': 1,
            'custom_vocabulary': 'Legacy Vocab',
            'hotkey': {
              'hotkey_enabled': 'true',
              'hotkey_key': ';',
              'hotkey_key_display': 'Ö',
              'hotkey_modifiers': 'meta+shift',
            },
            'replacements': [
              {'trigger': 'mfg', 'replacement': 'Mit freundlichen Grüßen'},
            ],
          }),
        );

    final restored = await service.importFromFile('/legacy.json');

    expect(restored.settings['custom_vocabulary'], 'Legacy Vocab');
    expect(restored.settings['hotkey_enabled'], 'true');
    expect(restored.settings['hotkey_key'], ';');
    expect(restored.settings['hotkey_key_display'], 'Ö');
    expect(restored.settings['hotkey_modifiers'], 'meta+shift');
    expect(restored.replacements, hasLength(1));
    expect(restored.replacements.single.triggers, ['mfg']);
    expect(restored.replacements.single.replacement, 'Mit freundlichen Grüßen');
  });

  test(
    'a v2 file is readable by decoding "settings" — the v1-compat duplicates '
    'are secondary and "settings" wins on conflicting values',
    () async {
      await fs
          .file('/v2-conflict.json')
          .writeAsString(
            jsonEncode({
              'format_version': 2,
              'settings': {'custom_vocabulary': 'From settings map'},
              // Deliberately conflicting duplicate — must lose.
              'custom_vocabulary': 'From top-level duplicate',
              'hotkey': const HotkeySettings().toMap(),
              'replacements': <Object?>[],
            }),
          );

      final restored = await service.importFromFile('/v2-conflict.json');

      expect(restored.settings['custom_vocabulary'], 'From settings map');
    },
  );

  test('a file with a format_version higher than the app knows is read '
      'best-effort, not rejected', () async {
    await fs
        .file('/future.json')
        .writeAsString(
          jsonEncode({
            'format_version': 99,
            'settings': {'theme_mode': 'light'},
            'custom_vocabulary': '',
            'hotkey': const HotkeySettings().toMap(),
            'replacements': <Object?>[],
          }),
        );

    final restored = await service.importFromFile('/future.json');

    expect(restored.settings['theme_mode'], 'light');
  });

  test('a v2 file that omits the v1-compat "hotkey"/"custom_vocabulary" '
      'duplicates is still read via "settings" alone, not rejected — the '
      'duplicates exist only so *this build\'s v1 decoder* stays happy, not '
      'as a requirement this build\'s own v2 decoder imposes back', () async {
    await fs
        .file('/v2-no-duplicates.json')
        .writeAsString(
          jsonEncode({
            'format_version': 2,
            'settings': {
              'theme_mode': 'light',
              'custom_vocabulary': 'From settings only',
              'hotkey_enabled': 'true',
              'hotkey_key': 'F',
              'hotkey_key_display': 'F',
              'hotkey_modifiers': 'ctrl+alt',
            },
            'replacements': <Object?>[],
          }),
        );

    final restored = await service.importFromFile('/v2-no-duplicates.json');

    expect(restored.settings['theme_mode'], 'light');
    expect(restored.settings['custom_vocabulary'], 'From settings only');
    expect(restored.settings['hotkey_modifiers'], 'ctrl+alt');
  });

  // ---------------------------------------------------------------------------
  // Error handling: malformed import file.
  // ---------------------------------------------------------------------------

  test(
    'importFromFile throws SettingsImportFormatException for invalid JSON',
    () async {
      await fs.file('/broken.json').writeAsString('not json at all');

      expect(
        () => service.importFromFile('/broken.json'),
        throwsA(isA<SettingsImportFormatException>()),
      );
    },
  );

  test(
    'importFromFile throws SettingsImportFormatException when required fields are missing',
    () async {
      await fs
          .file('/incomplete.json')
          .writeAsString('{"custom_vocabulary": "x"}');

      expect(
        () => service.importFromFile('/incomplete.json'),
        throwsA(isA<SettingsImportFormatException>()),
      );
    },
  );

  test(
    'importFromFile throws SettingsImportFileNotFoundException for a missing file',
    () async {
      expect(
        () => service.importFromFile('/does-not-exist.json'),
        throwsA(isA<SettingsImportFileNotFoundException>()),
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Snippets: exported as their own optional section (dictation-automations
  // ticket 05) — unchanged nullable semantics.
  // ---------------------------------------------------------------------------

  test('exportToFile writes snippets as their own JSON section', () async {
    final bundle = SettingsExportBundle(
      settings: Map.of(sampleSettings),
      replacements: const [],
      snippets: const [
        SnippetItem(id: 'x', title: 'Signature', body: 'Best,\nSilvio'),
      ],
    );

    await service.exportToFile('/exports/settings.json', bundle);

    final written = await fs.file('/exports/settings.json').readAsString();
    expect(written, contains('"snippets"'));
    expect(written, contains('"title"'));
    expect(written, contains('Signature'));
    expect(written, contains('Best,\\nSilvio'));
  });

  test('round trip: export then import restores snippets', () async {
    final bundle = SettingsExportBundle(
      settings: Map.of(sampleSettings),
      replacements: const [],
      snippets: const [
        SnippetItem(id: 'a', title: 'Signature', body: 'Best,\nSilvio'),
        SnippetItem(id: 'b', title: 'Greeting', body: 'Hi there'),
      ],
    );

    await service.exportToFile('/roundtrip-snippets.json', bundle);
    final restored = await service.importFromFile('/roundtrip-snippets.json');

    expect(restored.snippets, hasLength(2));
    expect(restored.snippets![0].title, 'Signature');
    expect(restored.snippets![0].body, 'Best,\nSilvio');
    expect(restored.snippets![1].title, 'Greeting');
    expect(restored.snippets![1].body, 'Hi there');
  });

  test('importFromFile reads a v1 export without a '
      '"snippets" section without throwing, decoding it as null (absent) '
      'rather than an empty list — so callers can leave existing snippets '
      'untouched instead of clearing them', () async {
    await fs
        .file('/pre-snippets.json')
        .writeAsString(
          jsonEncode({
            'format_version': 1,
            'custom_vocabulary': 'x',
            'hotkey': const HotkeySettings().toMap(),
            'replacements': <Object?>[],
          }),
        );

    final restored = await service.importFromFile('/pre-snippets.json');

    expect(restored.snippets, isNull);
  });

  test('importFromFile reads an export with an explicit empty "snippets" '
      'section as an empty (non-null) list — distinct from an absent '
      'section, so callers clear existing snippets when the user genuinely '
      'has none', () async {
    await fs
        .file('/empty-snippets.json')
        .writeAsString(
          jsonEncode({
            'format_version': 1,
            'custom_vocabulary': 'x',
            'hotkey': const HotkeySettings().toMap(),
            'replacements': <Object?>[],
            'snippets': <Object?>[],
          }),
        );

    final restored = await service.importFromFile('/empty-snippets.json');

    expect(restored.snippets, isNotNull);
    expect(restored.snippets, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Anti-obsolescence: every storage key AppSettings knows about must be
  // consciously sorted into either the deny list or the portable list. A
  // newly-added settings key that appears in neither fails this test — the
  // secure default (an unlisted key still travels at runtime) does not
  // change; this only forces a human decision once.
  // ---------------------------------------------------------------------------

  test(
    'every AppSettings.toStorageMap() key is accounted for in exactly one '
    'of settingsPortabilityDenyList / settingsPortabilityPortableKeysForTest',
    () {
      final allKeys = AppSettings.defaults.toStorageMap().keys.toSet();
      final accountedFor = {
        ...settingsPortabilityDenyList,
        ...settingsPortabilityPortableKeysForTest,
      };

      final unaccountedFor = allKeys.difference(accountedFor);
      expect(
        unaccountedFor,
        isEmpty,
        reason:
            'New AppSettings storage key(s) $unaccountedFor were added but '
            'not sorted into settingsPortabilityDenyList (excluded from '
            'export/import) or settingsPortabilityPortableKeysForTest '
            '(travels with export/import) in '
            'settings_portability_service.dart. Runtime behavior already '
            'defaults to portable — this test only forces a conscious '
            'choice to be recorded.',
      );

      final overlap = settingsPortabilityDenyList.intersection(
        settingsPortabilityPortableKeysForTest,
      );
      expect(
        overlap,
        isEmpty,
        reason:
            'Key(s) $overlap are listed in both the deny list and the '
            'portable list — pick exactly one.',
      );

      final stale = accountedFor.difference(allKeys);
      expect(
        stale,
        isEmpty,
        reason:
            'Key(s) $stale are listed here but no longer exist in '
            'AppSettings.toStorageMap() — remove the stale entry.',
      );
    },
  );
}

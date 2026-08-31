import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/locale_provider.dart';
import 'package:whispaste/core/onboarding/onboarding_revision.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/settings_portability_service.dart'
    show mergeImportedSettings;

/// [HistoryDatabase.writeAppSettings] that throws once [shouldThrow] is
/// flipped on — models a persist failure for the grandfathering-migration
/// tests below, which must prove the stamp stays at 0 (not silently
/// computed) when the write cannot land.
class _ThrowingSettingsDatabase extends HistoryDatabase {
  _ThrowingSettingsDatabase(super.e) : super.forTesting();

  bool shouldThrow = false;

  @override
  Future<void> writeAppSettings(Map<String, String> values) {
    if (shouldThrow) {
      throw Exception('simulated persist failure');
    }
    return super.writeAppSettings(values);
  }
}

/// In-memory fake for [SecureKeyStore] used in tests.
class FakeSecureKeyStore extends SecureKeyStore {
  final Map<String, String> store = {};

  @override
  Future<String?> readKey(String key) async => store[key];

  @override
  Future<void> writeKey(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAllApiKeys() async {
    final result = <String, String>{};
    for (final secureKey in apiKeyMapping.values) {
      final value = store[secureKey];
      if (value != null && value.isNotEmpty) {
        result[secureKey] = value;
      }
    }
    return result;
  }
}

void main() {
  late HistoryDatabase db;
  late FakeSecureKeyStore fakeSecureStore;
  late ProviderContainer container;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    fakeSecureStore = FakeSecureKeyStore();
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        secureKeyStoreProvider.overrideWithValue(fakeSecureStore),
      ],
    );
    await container.read(settingsProvider.future);
    // Wait for deferred secure store migration/merge to complete.
    await container.read(settingsProvider.notifier).secureKeysFuture;
  });

  tearDown(() {
    container.dispose();
  });

  test('loads defaults when no settings rows exist', () {
    final settings = container.read(settingsProvider).value;

    expect(settings, isNotNull);
    expect(settings!.locale, 'en');
    expect(settings.showOverlay, false);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('persists updates in drift and can reset to defaults', () async {
    await container
        .read(settingsProvider.notifier)
        .updateSettings(
          (settings) => settings.copyWith(
            locale: 'de',
            sttModel: 'Best Quality (Large)',
            showOverlay: true,
            recordStartSound: false,
          ),
        );

    expect(container.read(localeProvider), const Locale('de'));

    final persisted = AppSettings.fromStorageMap(await db.readAppSettings());
    expect(persisted.locale, 'de');
    expect(persisted.sttModel, 'whisper-large-v3-turbo');
    expect(persisted.showOverlay, true);
    expect(persisted.recordStartSound, false);

    await container.read(settingsProvider.notifier).resetToDefaults();

    final rowsAfterReset = await db.readAppSettings();
    final resetState = container.read(settingsProvider).value;

    expect(rowsAfterReset, isEmpty);
    expect(resetState, isNotNull);
    expect(resetState!.locale, 'en');
    expect(resetState.showOverlay, false);
  });

  group('secure API key storage', () {
    test('API keys written via updateSettings go to secure storage', () async {
      await container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(openAiApiKey: 'sk-test-123'));

      // In-memory state has the key.
      final settings = container.read(settingsProvider).value!;
      expect(settings.openAiApiKey, 'sk-test-123');

      // Secure storage has the key.
      final stored = await fakeSecureStore.readKey('wp_openai_api_key');
      expect(stored, 'sk-test-123');

      // SQLite does NOT have the key (empty string).
      final sqliteValues = await db.readAppSettings();
      expect(sqliteValues['openai_api_key'], '');
    });

    test('migrates plaintext keys from SQLite to secure storage', () async {
      // Simulate legacy data: write a key directly to SQLite.
      final legacyMap = const AppSettings(
        cloudProvider: CloudProviderSettings(openAiApiKey: 'sk-legacy'),
      ).toStorageMap();
      // Force the legacy key into the map (toStorageMap now writes '').
      legacyMap['openai_api_key'] = 'sk-legacy';
      await db.writeAppSettings(legacyMap);

      // Re-create the container to trigger a fresh build() + migration.
      container.dispose();
      fakeSecureStore = FakeSecureKeyStore();
      final db2 = HistoryDatabase.forTesting(NativeDatabase.memory());
      // Seed the legacy row into the new DB.
      await db2.writeAppSettings(legacyMap);

      final container2 = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db2.close);
            return db2;
          }),
          secureKeyStoreProvider.overrideWithValue(fakeSecureStore),
        ],
      );
      addTearDown(container2.dispose);

      await container2.read(settingsProvider.future);
      // Wait for deferred secure store migration/merge to complete.
      await container2.read(settingsProvider.notifier).secureKeysFuture;

      // Key is available in settings (re-read after deferred merge).
      final settings = container2.read(settingsProvider).value!;
      expect(settings.openAiApiKey, 'sk-legacy');

      // Key is now in secure storage.
      final secureValue = await fakeSecureStore.readKey('wp_openai_api_key');
      expect(secureValue, 'sk-legacy');

      // Key was cleared from SQLite.
      final sqliteValues = await db2.readAppSettings();
      expect(sqliteValues['openai_api_key'], '');
    });

    test('resetToDefaults clears API keys from secure storage', () async {
      await container
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) =>
                s.copyWith(openAiApiKey: 'sk-test', deepgramApiKey: 'dg-key'),
          );

      // Keys exist in secure storage.
      expect(await fakeSecureStore.readKey('wp_openai_api_key'), 'sk-test');

      await container.read(settingsProvider.notifier).resetToDefaults();

      // Keys are gone from secure storage.
      expect(await fakeSecureStore.readKey('wp_openai_api_key'), isNull);
      expect(await fakeSecureStore.readKey('wp_deepgram_api_key'), isNull);
    });
  });

  group('mergeImportedSettings API-key retention (settings-portability)', () {
    test(
      'importing a bundle merges settings without deleting existing API keys',
      () async {
        // Seed both API keys via a normal updateSettings call first — the
        // keys must be present in the *in-memory* AppSettings (not just the
        // secure store) before the import merge runs. If they were only in
        // the secure store, `_syncApiKeysToSecureStorage` would compare the
        // old in-memory '' against the merged result's '' and skip the
        // delete call trivially — proving nothing about re-injection.
        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(
                openAiApiKey: 'sk-existing',
                deepgramApiKey: 'dg-existing',
              ),
            );
        expect(
          container.read(settingsProvider).value!.openAiApiKey,
          'sk-existing',
        );
        expect(await fakeSecureStore.readKey('wp_openai_api_key'), isNotNull);

        // An imported settings map — as `CloudProviderSettings.toMap()`
        // always writes the two key fields as empty strings (they are
        // never persisted to SQLite), any gathered/exported map has empty
        // values here regardless of what the source device's keychain held.
        // `current.toStorageMap()` already reflects that.
        final current = container.read(settingsProvider).value!;
        final imported = current.toStorageMap();
        expect(imported['openai_api_key'], '');
        expect(imported['deepgram_api_key'], '');

        await container
            .read(settingsProvider.notifier)
            .updateSettings((s) => mergeImportedSettings(s, imported));

        final merged = container.read(settingsProvider).value!;
        expect(merged.openAiApiKey, 'sk-existing');
        expect(merged.deepgramApiKey, 'dg-existing');

        // No delete was triggered at the secure store.
        expect(
          await fakeSecureStore.readKey('wp_openai_api_key'),
          'sk-existing',
        );
        expect(
          await fakeSecureStore.readKey('wp_deepgram_api_key'),
          'dg-existing',
        );
      },
    );

    test(
      'imported settings that omit a key keep the current local value',
      () async {
        await container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(sttModel: 'whisper-small'));

        final current = container.read(settingsProvider).value!;
        final imported = current.toStorageMap()..remove('stt_model');

        await container
            .read(settingsProvider.notifier)
            .updateSettings((s) => mergeImportedSettings(s, imported));

        expect(
          container.read(settingsProvider).value!.sttModel,
          'whisper-small',
        );
      },
    );

    test(
      'deny-listed keys in the imported map are ignored, local value wins',
      () async {
        await container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(windowMaximized: false));

        final current = container.read(settingsProvider).value!;
        final imported = current.toStorageMap()
          ..['window_maximized'] = 'true'
          ..['onboarding_completed'] = 'true'
          ..['microphone'] = 'Some Foreign Device';

        await container
            .read(settingsProvider.notifier)
            .updateSettings((s) => mergeImportedSettings(s, imported));

        final merged = container.read(settingsProvider).value!;
        expect(merged.windowMaximized, false);
        expect(merged.onboardingCompleted, false);
        expect(merged.microphone, 'Default');
      },
    );
  });

  group('deprecated copyWith shim (portabilityPaths pass-through)', () {
    test(
      'a copyWith call that only touches an unrelated field keeps portabilityPaths',
      () {
        // Regression: the shim used to omit `portabilityPaths` from the
        // AppSettings(...) it rebuilds, so any call through this API —
        // app.dart's `copyWith(windowMaximized: true)` on every window
        // maximize is the one production call site — silently reset the
        // remembered export/import location back to empty.
        const settings = AppSettings(
          portabilityPaths: SettingsPortabilityPathSettings(
            exportPath: '/Users/x/backup.json',
            exportBookmark: 'bookmark-bytes',
          ),
        );

        final result = settings.copyWith(windowMaximized: true);

        expect(result.portabilityPaths.exportPath, '/Users/x/backup.json');
        expect(result.portabilityPaths.exportBookmark, 'bookmark-bytes');
        expect(result.windowMaximized, true);
      },
    );

    test(
      'a copyWith call that only touches an unrelated field keeps quickNoteHotkey',
      () {
        const settings = AppSettings(
          quickNoteHotkey: QuickNoteHotkeySettings(
            quickNoteHotkeyEnabled: true,
            quickNoteHotkeyKey: 'Y',
            quickNoteHotkeyModifiers: 'ctrl+shift',
          ),
        );

        final result = settings.copyWith(windowMaximized: true);

        expect(result.quickNoteHotkey.quickNoteHotkeyEnabled, true);
        expect(result.quickNoteHotkey.quickNoteHotkeyKey, 'Y');
        expect(result.windowMaximized, true);
      },
    );

    test(
      'a copyWith call that only touches an unrelated field keeps snippetPickerHotkey',
      () {
        const settings = AppSettings(
          snippetPickerHotkey: SnippetPickerHotkeySettings(
            snippetPickerHotkeyEnabled: true,
            snippetPickerHotkeyKey: 'E',
            snippetPickerHotkeyModifiers: 'ctrl+shift',
          ),
        );

        final result = settings.copyWith(windowMaximized: true);

        expect(result.snippetPickerHotkey.snippetPickerHotkeyEnabled, true);
        expect(result.snippetPickerHotkey.snippetPickerHotkeyKey, 'E');
        expect(result.windowMaximized, true);
      },
    );
  });

  group('quickNoteHotkey settings (ticket 20)', () {
    test('defaults: disabled, key N, platform-aware modifiers', () {
      final defaults = AppSettings.defaults;

      expect(defaults.quickNoteHotkey.quickNoteHotkeyEnabled, false);
      expect(defaults.quickNoteHotkey.quickNoteHotkeyKey, 'N');
      expect(
        defaults.quickNoteHotkey.quickNoteHotkeyModifiers,
        Platform.isMacOS ? 'meta+shift' : 'ctrl+shift',
      );
    });

    test('default key is layout-invariant (regression: Y/Z swap on QWERTZ made '
        'the shipped default show one key but register the other physical '
        'position — see hotkey_key_resolver.dart canonicalRecordableKey)', () {
      final defaults = AppSettings.defaults;

      expect(
        defaults.quickNoteHotkey.quickNoteHotkeyKey,
        isNot(anyOf('Y', 'Z')),
      );
    });

    test(
      'missing storage keys fall back to defaults (no migration needed)',
      () {
        final settings = AppSettings.fromStorageMap(const {});

        expect(settings.quickNoteHotkey, QuickNoteHotkeySettings.defaults);
      },
    );

    test('round-trips through toStorageMap/fromStorageMap', () {
      const original = QuickNoteHotkeySettings(
        quickNoteHotkeyEnabled: true,
        quickNoteHotkeyKey: 'N',
        quickNoteHotkeyKeyDisplay: 'N',
        quickNoteHotkeyModifiers: 'meta+shift',
      );
      const settings = AppSettings(quickNoteHotkey: original);

      final restored = AppSettings.fromStorageMap(settings.toStorageMap());

      expect(restored.quickNoteHotkey, original);
    });
  });

  group('snippetPickerHotkey settings (ticket 26)', () {
    test('defaults: disabled, key E, platform-aware modifiers', () {
      final defaults = AppSettings.defaults;

      expect(defaults.snippetPickerHotkey.snippetPickerHotkeyEnabled, false);
      expect(defaults.snippetPickerHotkey.snippetPickerHotkeyKey, 'E');
      expect(
        defaults.snippetPickerHotkey.snippetPickerHotkeyModifiers,
        Platform.isMacOS ? 'meta+shift' : 'ctrl+shift',
      );
    });

    test(
      'missing storage keys fall back to defaults (no migration needed)',
      () {
        final settings = AppSettings.fromStorageMap(const {});

        expect(
          settings.snippetPickerHotkey,
          SnippetPickerHotkeySettings.defaults,
        );
      },
    );

    test('round-trips through toStorageMap/fromStorageMap', () {
      const original = SnippetPickerHotkeySettings(
        snippetPickerHotkeyEnabled: true,
        snippetPickerHotkeyKey: 'E',
        snippetPickerHotkeyKeyDisplay: 'E',
        snippetPickerHotkeyModifiers: 'meta+shift',
      );
      const settings = AppSettings(snippetPickerHotkey: original);

      final restored = AppSettings.fromStorageMap(settings.toStorageMap());

      expect(restored.snippetPickerHotkey, original);
    });

    test(
      'does not affect quickNoteHotkey or the global hotkey when set independently',
      () {
        const settings = AppSettings(
          snippetPickerHotkey: SnippetPickerHotkeySettings(
            snippetPickerHotkeyEnabled: true,
            snippetPickerHotkeyKey: 'E',
            snippetPickerHotkeyModifiers: 'ctrl+shift',
          ),
        );

        expect(settings.quickNoteHotkey, QuickNoteHotkeySettings.defaults);
        expect(settings.hotkey, HotkeySettings.defaults);
      },
    );
  });

  group('smartMode settings (ticket 01 of smart-mode-v2)', () {
    test('defaults: standard preset is off', () {
      final defaults = AppSettings.defaults;
      expect(defaults.smartMode.standardPreset, 'off');
    });

    test('missing storage keys fall back to off (an update never silently '
        'turns Smart Mode on)', () {
      final settings = AppSettings.fromStorageMap(const {});
      expect(settings.smartMode.standardPreset, 'off');
    });

    test('round-trips through toStorageMap/fromStorageMap', () {
      const original = SmartModeSettings(
        standardPreset: 'translate',
        targetLanguage: 'de',
      );
      const settings = AppSettings(smartMode: original);

      final restored = AppSettings.fromStorageMap(settings.toStorageMap());

      expect(restored.smartMode, original);
    });

    test('copyWithSections replaces only smartMode', () {
      final base = AppSettings.defaults;
      final updated = base.copyWithSections(
        smartMode: base.smartMode.copyWith(standardPreset: 'cleanup'),
      );

      expect(updated.smartMode.standardPreset, 'cleanup');
      expect(updated.hotkey, base.hotkey);
      expect(updated.stt, base.stt);
    });

    test('targetLanguage (ticket 03) defaults to German', () {
      final defaults = AppSettings.defaults;
      expect(defaults.smartMode.targetLanguage, 'de');
    });

    test('missing targetLanguage storage key falls back to German', () {
      final settings = AppSettings.fromStorageMap(const {});
      expect(settings.smartMode.targetLanguage, 'de');
    });

    test('copyWith updates only targetLanguage, leaving standardPreset '
        'untouched', () {
      const original = SmartModeSettings(standardPreset: 'translate');
      final updated = original.copyWith(targetLanguage: 'en');

      expect(updated.targetLanguage, 'en');
      expect(updated.standardPreset, 'translate');
    });
  });

  group('sound mute migration (issue 12)', () {
    /// Helper: build a fresh container seeded with the given storage map.
    Future<(ProviderContainer, HistoryDatabase)> buildSeeded(
      Map<String, String> storageMap,
    ) async {
      final seedDb = HistoryDatabase.forTesting(NativeDatabase.memory());
      await seedDb.writeAppSettings(storageMap);
      final seedStore = FakeSecureKeyStore();
      final c = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(seedDb.close);
            return seedDb;
          }),
          secureKeyStoreProvider.overrideWithValue(seedStore),
        ],
      );
      await c.read(settingsProvider.future);
      await c.read(settingsProvider.notifier).secureKeysFuture;
      return (c, seedDb);
    }

    test(
      'all four bools false + soundVolume > 0 → volume set to 0 and persisted',
      () async {
        // Simulate a previously-muted user: all sound bools off, volume at default.
        final legacySettings = AppSettings.defaults.copyWithSections(
          sound: const SoundSettings(
            recordStartSound: false,
            recordStopSound: false,
            transcriptionCompleteSound: false,
            durationWarningSound: false,
            soundVolume: 80.0,
          ),
        );
        final (c, db) = await buildSeeded(legacySettings.toStorageMap());
        addTearDown(c.dispose);

        final loaded = c.read(settingsProvider).value!;
        expect(
          loaded.sound.soundVolume,
          0.0,
          reason: 'migration should set soundVolume to 0',
        );

        // Verify the migration is persisted (next load would also see 0).
        final persisted = AppSettings.fromStorageMap(
          await db.readAppSettings(),
        );
        expect(persisted.sound.soundVolume, 0.0);
      },
    );

    test('migration does not fire when at least one bool is true', () async {
      final settings = AppSettings.defaults.copyWithSections(
        sound: const SoundSettings(
          recordStartSound: true,
          recordStopSound: false,
          transcriptionCompleteSound: false,
          durationWarningSound: false,
          soundVolume: 80.0,
        ),
      );
      final (c, _) = await buildSeeded(settings.toStorageMap());
      addTearDown(c.dispose);

      final loaded = c.read(settingsProvider).value!;
      expect(
        loaded.sound.soundVolume,
        80.0,
        reason: 'migration must not fire when a bool is true',
      );
    });

    test('migration does not fire when soundVolume is already 0', () async {
      final settings = AppSettings.defaults.copyWithSections(
        sound: const SoundSettings(
          recordStartSound: false,
          recordStopSound: false,
          transcriptionCompleteSound: false,
          durationWarningSound: false,
          soundVolume: 0.0,
        ),
      );
      final (c, db) = await buildSeeded(settings.toStorageMap());
      addTearDown(c.dispose);

      final loaded = c.read(settingsProvider).value!;
      expect(loaded.sound.soundVolume, 0.0);
      // No extra write: persisted value is still 0 (no DB write needed).
      final persisted = AppSettings.fromStorageMap(await db.readAppSettings());
      expect(persisted.sound.soundVolume, 0.0);
    });

    test(
      'idempotent: after migration + user raises volume, restart keeps it (no re-fire)',
      () async {
        // Share ONE DB across two container lifecycles (= two app starts).
        final sharedDb = HistoryDatabase.forTesting(NativeDatabase.memory());
        addTearDown(sharedDb.close);

        // Seed a previously-muted user: all four bools false, volume 80.
        final legacy = AppSettings.defaults.copyWithSections(
          sound: const SoundSettings(
            recordStartSound: false,
            recordStopSound: false,
            transcriptionCompleteSound: false,
            durationWarningSound: false,
            soundVolume: 80.0,
          ),
        );
        await sharedDb.writeAppSettings(legacy.toStorageMap());

        // First start: migration fires → volume 0.
        final c1 = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) => sharedDb),
            secureKeyStoreProvider.overrideWithValue(FakeSecureKeyStore()),
          ],
        );
        await c1.read(settingsProvider.future);
        await c1.read(settingsProvider.notifier).secureKeysFuture;
        expect(c1.read(settingsProvider).value!.sound.soundVolume, 0.0);

        // User raises the volume to 50 (and the migration re-enabled the bools).
        await c1
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                sound: s.sound.copyWith(soundVolume: 50.0),
              ),
            );
        c1.dispose();

        // Second start with the SAME DB: migration must NOT re-fire.
        final c2 = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) => sharedDb),
            secureKeyStoreProvider.overrideWithValue(FakeSecureKeyStore()),
          ],
        );
        addTearDown(c2.dispose);
        await c2.read(settingsProvider.future);
        await c2.read(settingsProvider.notifier).secureKeysFuture;

        expect(
          c2.read(settingsProvider).value!.sound.soundVolume,
          50.0,
          reason: 'migration must not reset a volume the user raised later',
        );
      },
    );
  });

  group(
    'onboarding content-version grandfathering (onboarding-revisions issue 01)',
    () {
      OnboardingRevisionRegistry registryWithTarget(int version) => [
        OnboardingRevisionEntry(version: version, reason: (l10n) => 'r'),
      ];

      /// Same seeding idiom as the sound-mute migration group above, plus an
      /// overridable revision registry.
      Future<(ProviderContainer, HistoryDatabase)> buildSeeded(
        Map<String, String> storageMap,
        OnboardingRevisionRegistry registry,
      ) async {
        final seedDb = HistoryDatabase.forTesting(NativeDatabase.memory());
        await seedDb.writeAppSettings(storageMap);
        final c = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(seedDb.close);
              return seedDb;
            }),
            secureKeyStoreProvider.overrideWithValue(FakeSecureKeyStore()),
            onboardingRevisionRegistryProvider.overrideWithValue(registry),
          ],
        );
        await c.read(settingsProvider.future);
        await c.read(settingsProvider.notifier).secureKeysFuture;
        return (c, seedDb);
      }

      test('a fresh update from a bestand with no version key causes NO '
          'immediate re-onboarding', () async {
        // No registry entries ship yet — this is today's real shipped
        // state. A completed-onboarding bestand with no version key must
        // not be pushed back into onboarding the moment this feature
        // lands.
        final completed = AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        );
        final (c, _) = await buildSeeded(completed.toStorageMap(), const []);
        addTearDown(c.dispose);

        final loaded = c.read(settingsProvider).value!;
        expect(loaded.onboarding.onboardingContentVersion, 0);
        expect(
          onboardingRevisionDue(
            onboardingCompleted: loaded.onboarding.onboardingCompleted,
            seenContentVersion: loaded.onboarding.onboardingContentVersion,
            targetContentVersion: targetOnboardingContentVersion(
              const [],
              currentOnboardingPlatform(),
            ),
          ),
          isFalse,
        );
      });

      test('an unstamped, completed bestand is stamped to the target and '
          'persisted immediately', () async {
        final completed = AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        );
        final (c, db) = await buildSeeded(
          completed.toStorageMap(),
          registryWithTarget(1),
        );
        addTearDown(c.dispose);

        final loaded = c.read(settingsProvider).value!;
        expect(loaded.onboarding.onboardingContentVersion, 1);

        final persisted = AppSettings.fromStorageMap(
          await db.readAppSettings(),
        );
        expect(
          persisted.onboarding.onboardingContentVersion,
          1,
          reason: 'the stamp must be written, not merely held in memory',
        );
      });

      test(
        'a second load against a since-raised target correctly triggers a '
        'revision — proving the stamp is a write, not a recomputed value',
        () async {
          // Share ONE DB across two container lifecycles (= two app starts),
          // same idiom as the sound-mute migration's idempotency test.
          final sharedDb = HistoryDatabase.forTesting(NativeDatabase.memory());
          addTearDown(sharedDb.close);

          final completed = AppSettings.defaults.copyWithSections(
            onboarding: const OnboardingSettings(onboardingCompleted: true),
          );
          await sharedDb.writeAppSettings(completed.toStorageMap());

          // First start: registry only knows about v1 → grandfathered to 1.
          final c1 = ProviderContainer(
            overrides: [
              historyDatabaseProvider.overrideWith((ref) => sharedDb),
              secureKeyStoreProvider.overrideWithValue(FakeSecureKeyStore()),
              onboardingRevisionRegistryProvider.overrideWithValue(
                registryWithTarget(1),
              ),
            ],
          );
          await c1.read(settingsProvider.future);
          await c1.read(settingsProvider.notifier).secureKeysFuture;
          expect(
            c1
                .read(settingsProvider)
                .value!
                .onboarding
                .onboardingContentVersion,
            1,
          );
          c1.dispose();

          // Second start, same DB: the registry has since grown a v2 entry.
          final registryV2 = [
            OnboardingRevisionEntry(version: 1, reason: (l10n) => 'r1'),
            OnboardingRevisionEntry(version: 2, reason: (l10n) => 'r2'),
          ];
          final c2 = ProviderContainer(
            overrides: [
              historyDatabaseProvider.overrideWith((ref) => sharedDb),
              secureKeyStoreProvider.overrideWithValue(FakeSecureKeyStore()),
              onboardingRevisionRegistryProvider.overrideWithValue(registryV2),
            ],
          );
          addTearDown(c2.dispose);
          await c2.read(settingsProvider.future);
          await c2.read(settingsProvider.notifier).secureKeysFuture;

          final loaded = c2.read(settingsProvider).value!;
          expect(
            loaded.onboarding.onboardingContentVersion,
            1,
            reason:
                'must still read as the persisted stamp from the first '
                'start, not be silently re-grandfathered to 2',
          );
          expect(
            onboardingRevisionDue(
              onboardingCompleted: loaded.onboarding.onboardingCompleted,
              seenContentVersion: loaded.onboarding.onboardingContentVersion,
              targetContentVersion: targetOnboardingContentVersion(
                registryV2,
                currentOnboardingPlatform(),
              ),
            ),
            isTrue,
            reason:
                'a computed-on-read version would have swallowed this '
                'revision by silently re-grandfathering to 2 above',
          );
        },
      );

      test('a bestand with incomplete onboarding is not stamped', () async {
        final incomplete = AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(onboardingCompleted: false),
        );
        final (c, db) = await buildSeeded(
          incomplete.toStorageMap(),
          registryWithTarget(1),
        );
        addTearDown(c.dispose);

        expect(
          c.read(settingsProvider).value!.onboarding.onboardingContentVersion,
          0,
        );
        final persisted = AppSettings.fromStorageMap(
          await db.readAppSettings(),
        );
        expect(persisted.onboarding.onboardingContentVersion, 0);
      });

      test('an already-stamped bestand is left untouched', () async {
        final stamped = AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(
            onboardingCompleted: true,
            onboardingContentVersion: 1,
          ),
        );
        final (c, _) = await buildSeeded(
          stamped.toStorageMap(),
          registryWithTarget(3),
        );
        addTearDown(c.dispose);

        expect(
          c.read(settingsProvider).value!.onboarding.onboardingContentVersion,
          1,
          reason:
              'once stamped, a bestand must never be silently bumped to a '
              'later target on load — that is what onboardingRevisionDue '
              'is for',
        );
      });

      test('a failed persist leaves the bestand at 0 and the next start '
          'retries idempotently', () async {
        final completed = AppSettings.defaults.copyWithSections(
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        );
        final throwingDb = _ThrowingSettingsDatabase(NativeDatabase.memory());
        addTearDown(throwingDb.close);
        await throwingDb.writeAppSettings(completed.toStorageMap());
        throwingDb.shouldThrow = true;

        final c1 = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) => throwingDb),
            secureKeyStoreProvider.overrideWithValue(FakeSecureKeyStore()),
            onboardingRevisionRegistryProvider.overrideWithValue(
              registryWithTarget(1),
            ),
          ],
        );
        await c1.read(settingsProvider.future);
        await c1.read(settingsProvider.notifier).secureKeysFuture;

        expect(
          c1.read(settingsProvider).value!.onboarding.onboardingContentVersion,
          0,
          reason:
              'the write threw, so the in-memory value must stay at 0 too '
              '— session and disk must agree',
        );
        final persisted = AppSettings.fromStorageMap(
          await throwingDb.readAppSettings(),
        );
        expect(persisted.onboarding.onboardingContentVersion, 0);
        c1.dispose();

        // Next start: persistence works again → the deferred stamp lands.
        throwingDb.shouldThrow = false;
        final c2 = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) => throwingDb),
            secureKeyStoreProvider.overrideWithValue(FakeSecureKeyStore()),
            onboardingRevisionRegistryProvider.overrideWithValue(
              registryWithTarget(1),
            ),
          ],
        );
        addTearDown(c2.dispose);
        await c2.read(settingsProvider.future);
        await c2.read(settingsProvider.notifier).secureKeysFuture;

        expect(
          c2.read(settingsProvider).value!.onboarding.onboardingContentVersion,
          1,
          reason: 'idempotent retry: no crash, no loop, eventually stamped',
        );
      });
    },
  );

  group('effectiveOverlayMode', () {
    test('passes through floating as valid mode', () {
      const s = AppSettings(overlay: OverlaySettings(overlayMode: 'floating'));
      expect(s.effectiveOverlayMode, OverlayMode.floating);
    });

    test('migrates inWindow to floating', () {
      const s = AppSettings(overlay: OverlaySettings(overlayMode: 'in-window'));
      expect(s.effectiveOverlayMode, OverlayMode.floating);
    });

    test('preserves off as-is', () {
      const s = AppSettings(overlay: OverlaySettings(overlayMode: 'off'));
      expect(s.effectiveOverlayMode, OverlayMode.off);
    });

    test('persisted floating does not crash settings load', () async {
      // Simulate a user who had "floating" persisted from before the migration.
      await container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(overlayMode: 'floating'));

      final settings = container.read(settingsProvider).value!;
      // Raw value is still 'floating' in storage
      expect(settings.overlayMode, 'floating');
      // Floating is now a valid mode (native overlay)
      expect(settings.effectiveOverlayMode, OverlayMode.floating);
    });
  });

  group('transcriptionModelId', () {
    test('on-device + whisper engine returns effectiveModelId', () {
      const s = AppSettings(
        stt: SttSettings(
          provider: 'On Device',
          engine: 'whisper',
          model: 'whisper-small',
        ),
      );
      expect(s.transcriptionModelId, 'whisper-small');
      expect(s.transcriptionModelId, s.effectiveModelId);
    });

    test('on-device + parakeet engine returns the parakeet model ID', () {
      const s = AppSettings(
        stt: SttSettings(
          provider: 'On Device',
          engine: 'parakeet',
          model: 'whisper-small',
        ),
      );
      expect(s.transcriptionModelId, 'parakeet-tdt-0.6b-v3');
      expect(
        s.transcriptionModelId,
        isNot(s.effectiveModelId),
        reason:
            'effectiveModelId must stay whisper-only — it also resolves '
            'whisper model paths (preflight/reload/benchmark)',
      );
    });

    test('cloud provider ignores engine and returns effectiveModelId', () {
      const s = AppSettings(
        stt: SttSettings(
          provider: 'OpenAI',
          engine: 'parakeet', // irrelevant when provider isn't onDevice
          model: 'whisper-medium',
        ),
      );
      expect(s.transcriptionModelId, 'whisper-medium');
    });
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/locale_provider.dart';
import 'package:whispaste/core/theme/theme_provider.dart';
import 'package:whispaste/core/data/database.dart';

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
    expect(settings!.themeMode, ThemeMode.dark);
    expect(settings.locale, 'en');
    expect(settings.showOverlay, false);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('persists updates in drift and can reset to defaults', () async {
    await container
        .read(settingsProvider.notifier)
        .updateSettings(
          (settings) => settings.copyWith(
            themeMode: ThemeMode.light,
            locale: 'de',
            sttModel: 'Best Quality (Large)',
            showOverlay: true,
            recordStartSound: false,
          ),
        );

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(container.read(localeProvider), const Locale('de'));

    final persisted = AppSettings.fromStorageMap(await db.readAppSettings());
    expect(persisted.themeMode, ThemeMode.light);
    expect(persisted.locale, 'de');
    expect(persisted.sttModel, 'whisper-large-v3-turbo');
    expect(persisted.showOverlay, true);
    expect(persisted.recordStartSound, false);

    await container.read(settingsProvider.notifier).resetToDefaults();

    final rowsAfterReset = await db.readAppSettings();
    final resetState = container.read(settingsProvider).value;

    expect(rowsAfterReset, isEmpty);
    expect(resetState, isNotNull);
    expect(resetState!.themeMode, ThemeMode.dark);
    expect(resetState.locale, 'en');
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
}

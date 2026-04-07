import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
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
    expect(settings.showOverlay, true);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('persists updates in drift and can reset to defaults', () async {
    await container.read(settingsProvider.notifier).updateSettings(
          (settings) => settings.copyWith(
            themeMode: ThemeMode.light,
            locale: 'de',
            sttModel: 'Best Quality (Large)',
            showOverlay: false,
            recordStartSound: false,
          ),
        );

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(container.read(localeProvider), const Locale('de'));

    final persisted = AppSettings.fromStorageMap(await db.readAppSettings());
    expect(persisted.themeMode, ThemeMode.light);
    expect(persisted.locale, 'de');
    expect(persisted.sttModel, 'whisper-large-v3');
    expect(persisted.showOverlay, false);
    expect(persisted.recordStartSound, false);

    await container.read(settingsProvider.notifier).resetToDefaults();

    final rowsAfterReset = await db.readAppSettings();
    final resetState = container.read(settingsProvider).value;

    expect(rowsAfterReset, isEmpty);
    expect(resetState, isNotNull);
    expect(resetState!.themeMode, ThemeMode.dark);
    expect(resetState.locale, 'en');
    expect(resetState.showOverlay, true);
  });

  group('secure API key storage', () {
    test('API keys written via updateSettings go to secure storage', () async {
      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(openAiApiKey: 'sk-test-123'),
          );

      // In-memory state has the key.
      final settings = container.read(settingsProvider).value!;
      expect(settings.openAiApiKey, 'sk-test-123');

      // Secure storage has the key.
      final stored =
          await fakeSecureStore.readKey('wp_openai_api_key');
      expect(stored, 'sk-test-123');

      // SQLite does NOT have the key (empty string).
      final sqliteValues = await db.readAppSettings();
      expect(sqliteValues['openai_api_key'], '');
    });

    test('migrates plaintext keys from SQLite to secure storage', () async {
      // Simulate legacy data: write a key directly to SQLite.
      final legacyMap =
          const AppSettings(groqApiKey: 'gsk-legacy').toStorageMap();
      // Force the legacy key into the map (toStorageMap now writes '').
      legacyMap['groq_api_key'] = 'gsk-legacy';
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
      expect(settings.groqApiKey, 'gsk-legacy');

      // Key is now in secure storage.
      final secureValue =
          await fakeSecureStore.readKey('wp_groq_api_key');
      expect(secureValue, 'gsk-legacy');

      // Key was cleared from SQLite.
      final sqliteValues = await db2.readAppSettings();
      expect(sqliteValues['groq_api_key'], '');
    });

    test('resetToDefaults clears API keys from secure storage', () async {
      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(
              anthropicApiKey: 'ant-key',
              geminiApiKey: 'gem-key',
            ),
          );

      // Keys exist in secure storage.
      expect(
        await fakeSecureStore.readKey('wp_anthropic_api_key'),
        'ant-key',
      );

      await container.read(settingsProvider.notifier).resetToDefaults();

      // Keys are gone from secure storage.
      expect(
        await fakeSecureStore.readKey('wp_anthropic_api_key'),
        isNull,
      );
      expect(
        await fakeSecureStore.readKey('wp_gemini_api_key'),
        isNull,
      );
    });
  });
}

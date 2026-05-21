import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';

void main() {
  group('AppSettings round-trip serialisation', () {
    test('defaults survive toStorageMap → fromStorageMap unchanged', () {
      final original = AppSettings.defaults;
      final restored = AppSettings.fromStorageMap(original.toStorageMap());

      expect(restored.themeMode, original.themeMode);
      expect(restored.locale, original.locale);
      expect(restored.microphone, original.microphone);
      expect(restored.sttProvider, original.sttProvider);
      expect(restored.sttModel, original.sttModel);
      expect(restored.sttLanguage, original.sttLanguage);
      expect(restored.historyMaxEntries, original.historyMaxEntries);
      expect(restored.historyAutoTrashDays, original.historyAutoTrashDays);
      expect(restored.autoPasteDelay, original.autoPasteDelay);
      expect(restored.autoPasteBlocklist, original.autoPasteBlocklist);
      expect(restored.hotkeyEnabled, original.hotkeyEnabled);
      expect(restored.checkUpdates, original.checkUpdates);
      expect(restored.onboardingCompleted, original.onboardingCompleted);
      expect(restored.gpuAcceleration, original.gpuAcceleration);
      expect(restored.customVocabulary, original.customVocabulary);
      expect(
        restored.textReplacementsEnabled,
        original.textReplacementsEnabled,
      );
      expect(restored.trimSilence, original.trimSilence);
      expect(restored.inputGain, original.inputGain);
    });

    test('schema_version key is present in toStorageMap', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('schema_version'), isTrue);
      expect(map['schema_version'], '2');
    });

    test('API keys are serialised as empty strings (not stored in SQLite)', () {
      final settings = AppSettings.defaults.copyWith(
        openAiApiKey: 'sk-secret',
        deepgramApiKey: 'dg-secret',
      );
      final map = settings.toStorageMap();
      // API keys must NOT appear in the SQLite map as plaintext
      expect(map['openai_api_key'] ?? '', isEmpty);
      expect(map['deepgram_api_key'] ?? '', isEmpty);
    });

    test('unknown keys in map are ignored (forward-compat)', () {
      final map = Map<String, String>.from(AppSettings.defaults.toStorageMap())
        ..['unknown_future_key'] = 'some_value';

      // Should not throw
      expect(() => AppSettings.fromStorageMap(map), returnsNormally);
    });

    test('missing keys fall back to defaults (backward-compat)', () {
      // Empty map = old DB with no settings
      final restored = AppSettings.fromStorageMap({});

      expect(restored.themeMode, AppSettings.defaults.themeMode);
      expect(restored.sttModel, AppSettings.defaults.sttModel);
      expect(
        restored.historyMaxEntries,
        AppSettings.defaults.historyMaxEntries,
      );
    });

    test('non-default values survive round-trip', () {
      final custom = AppSettings.defaults.copyWith(
        historyMaxEntries: 500,
        autoPasteDelay: 300,
        autoPasteBlocklist: 'com.example.app,other.app',
        customVocabulary: 'Flutter Riverpod',
        textReplacementsEnabled: true,
        onboardingCompleted: true,
      );

      final restored = AppSettings.fromStorageMap(custom.toStorageMap());

      expect(restored.historyMaxEntries, 500);
      expect(restored.autoPasteDelay, 300);
      expect(restored.autoPasteBlocklist, 'com.example.app,other.app');
      expect(restored.customVocabulary, 'Flutter Riverpod');
      expect(restored.textReplacementsEnabled, isTrue);
      expect(restored.onboardingCompleted, isTrue);
    });
  });
}

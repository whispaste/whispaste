/// Unit tests for individual [AppSettings] section classes — see
/// `settings_round_trip_test.dart` for the flat `AppSettings` roundtrip.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  group('SttSettings.numericOnlyMode', () {
    test('defaults to false', () {
      expect(SttSettings.defaults.numericOnlyMode, isFalse);
    });

    test('toMap -> fromMap round-trip preserves true', () {
      const settings = SttSettings(numericOnlyMode: true);
      final restored = SttSettings.fromMap(settings.toMap());
      expect(restored.numericOnlyMode, isTrue);
    });

    test('toMap -> fromMap round-trip preserves false', () {
      const settings = SttSettings(numericOnlyMode: false);
      final restored = SttSettings.fromMap(settings.toMap());
      expect(restored.numericOnlyMode, isFalse);
    });

    test('missing key in map falls back to the default (false)', () {
      final map = Map<String, String>.from(SttSettings.defaults.toMap())
        ..remove('stt_numeric_only_mode');
      final restored = SttSettings.fromMap(map);
      expect(restored.numericOnlyMode, isFalse);
    });

    test('copyWith(numericOnlyMode: true) changes no other field', () {
      const original = SttSettings();
      final updated = original.copyWith(numericOnlyMode: true);

      expect(updated.numericOnlyMode, isTrue);
      expect(updated.provider, original.provider);
      expect(updated.model, original.model);
      expect(updated.language, original.language);
      expect(updated.idleTimeoutMinutes, original.idleTimeoutMinutes);
      expect(updated.customVocabulary, original.customVocabulary);
      expect(updated.engine, original.engine);
      expect(updated.punctuationPriming, original.punctuationPriming);
      expect(updated.stripPunctuation, original.stripPunctuation);
      expect(updated.vadEnabled, original.vadEnabled);
    });

    test('copyWith() without arguments keeps the previous value', () {
      const original = SttSettings(numericOnlyMode: true);
      final updated = original.copyWith();
      expect(updated.numericOnlyMode, isTrue);
    });

    test('two instances differing only in numericOnlyMode are unequal', () {
      const a = SttSettings(numericOnlyMode: true);
      const b = SttSettings(numericOnlyMode: false);
      expect(a == b, isFalse);
    });
  });
}

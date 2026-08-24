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

  group('OnboardingSettings.seenFeatureSpotlightIds', () {
    test('defaults to the empty string', () {
      expect(OnboardingSettings.defaults.seenFeatureSpotlightIds, '');
    });

    test('toMap -> fromMap round-trip preserves a comma-separated id list', () {
      const settings = OnboardingSettings(seenFeatureSpotlightIds: 'a,b,c');
      final restored = OnboardingSettings.fromMap(settings.toMap());
      expect(restored.seenFeatureSpotlightIds, 'a,b,c');
    });

    test('toMap -> fromMap round-trip preserves the empty default', () {
      const settings = OnboardingSettings();
      final restored = OnboardingSettings.fromMap(settings.toMap());
      expect(restored.seenFeatureSpotlightIds, '');
    });

    test('missing key in map falls back to the default (empty string)', () {
      final map = Map<String, String>.from(OnboardingSettings.defaults.toMap())
        ..remove('seen_feature_spotlight_ids');
      final restored = OnboardingSettings.fromMap(map);
      expect(restored.seenFeatureSpotlightIds, '');
    });

    test('copyWith(seenFeatureSpotlightIds: ...) changes no other field', () {
      const original = OnboardingSettings();
      final updated = original.copyWith(seenFeatureSpotlightIds: 'x');

      expect(updated.seenFeatureSpotlightIds, 'x');
      expect(updated.onboardingCompleted, original.onboardingCompleted);
      expect(
        updated.autoPasteOffHintDismissed,
        original.autoPasteOffHintDismissed,
      );
      expect(updated.onboardingCurrentStep, original.onboardingCurrentStep);
      expect(updated.onboardingFlowVersion, original.onboardingFlowVersion);
      expect(
        updated.onboardingContentVersion,
        original.onboardingContentVersion,
      );
    });

    test('copyWith() without arguments keeps the previous value', () {
      const original = OnboardingSettings(seenFeatureSpotlightIds: 'x');
      final updated = original.copyWith();
      expect(updated.seenFeatureSpotlightIds, 'x');
    });

    test(
      'two instances differing only in seenFeatureSpotlightIds are unequal',
      () {
        const a = OnboardingSettings(seenFeatureSpotlightIds: 'a');
        const b = OnboardingSettings(seenFeatureSpotlightIds: 'b');
        expect(a == b, isFalse);
      },
    );
  });
}

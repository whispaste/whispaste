/// Round-trip tests for `BehaviorSettings.correctionLearningEnabled` (ticket
/// 01 `.scratch/vocab-learning-corrections/`) — the global on/off switch for
/// vocabulary-learning-from-corrections. Uses the section-based
/// `copyWithSections` API (new fields go through this, not the legacy flat
/// `copyWith` locked in by `appsettings_behavior_snapshot_test.dart`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';

void main() {
  group('BehaviorSettings.correctionLearningEnabled', () {
    test('defaults to true', () {
      expect(AppSettings.defaults.behavior.correctionLearningEnabled, isTrue);
    });

    test('storage key is present in toStorageMap', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('correction_learning_enabled'), isTrue);
    });

    test('false survives a toStorageMap → fromStorageMap round-trip', () {
      final settings = AppSettings.defaults.copyWithSections(
        behavior: AppSettings.defaults.behavior.copyWith(
          correctionLearningEnabled: false,
        ),
      );

      final restored = AppSettings.fromStorageMap(settings.toStorageMap());

      expect(restored.behavior.correctionLearningEnabled, isFalse);
    });

    test('true survives a toStorageMap → fromStorageMap round-trip', () {
      final settings = AppSettings.defaults.copyWithSections(
        behavior: AppSettings.defaults.behavior.copyWith(
          correctionLearningEnabled: true,
        ),
      );

      final restored = AppSettings.fromStorageMap(settings.toStorageMap());

      expect(restored.behavior.correctionLearningEnabled, isTrue);
    });

    test('missing key falls back to the default (backward-compat)', () {
      final map = Map<String, String>.from(AppSettings.defaults.toStorageMap())
        ..remove('correction_learning_enabled');

      final restored = AppSettings.fromStorageMap(map);

      expect(restored.behavior.correctionLearningEnabled, isTrue);
    });
  });
}

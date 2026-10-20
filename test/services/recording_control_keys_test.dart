/// Settings and key mapping for the configurable recording controls (WP-39,
/// matrix 9.1): double-tap hands-free and the cancel-dictation key.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/hotkey_service.dart';

void main() {
  group('AudioInputSettings recording controls', () {
    test('defaults: double tap off, cancel key Escape', () {
      expect(AudioInputSettings.defaults.doubleTapHandsFree, isFalse);
      expect(AudioInputSettings.defaults.cancelDictationKey, 'escape');
    });

    test('round-trip through the string map', () {
      const original = AudioInputSettings(
        doubleTapHandsFree: true,
        cancelDictationKey: 'f12',
      );
      final restored = AudioInputSettings.fromMap(original.toMap());
      expect(restored.doubleTapHandsFree, isTrue);
      expect(restored.cancelDictationKey, 'f12');
      expect(restored, original);
    });

    test('an unknown cancel key falls back to Escape', () {
      final restored = AudioInputSettings.fromMap(const {
        'cancel_dictation_key': 'ctrl+space',
      });
      expect(restored.cancelDictationKey, 'escape');
    });
  });

  group('logicalKeyForCancelDictation', () {
    test('maps the stored names to their keys', () {
      expect(logicalKeyForCancelDictation('escape'), LogicalKeyboardKey.escape);
      expect(logicalKeyForCancelDictation('f12'), LogicalKeyboardKey.f12);
    });

    test('every offered choice maps to a distinct key', () {
      final keys = {
        for (final name in cancelDictationKeyChoices)
          logicalKeyForCancelDictation(name),
      };
      expect(keys, hasLength(cancelDictationKeyChoices.length));
    });
  });
}

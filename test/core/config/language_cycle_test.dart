import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/language_cycle.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  group('nextFavoriteLanguage', () {
    test('returns null without favorites', () {
      expect(nextFavoriteLanguage(current: 'de', favorites: const []), isNull);
    });

    test('walks the favorites in order and wraps around', () {
      const favorites = ['de', 'en', 'ru'];
      expect(nextFavoriteLanguage(current: 'de', favorites: favorites), 'en');
      expect(nextFavoriteLanguage(current: 'en', favorites: favorites), 'ru');
      expect(nextFavoriteLanguage(current: 'ru', favorites: favorites), 'de');
    });

    test('a non-favorite current language jumps to the first favorite', () {
      expect(
        nextFavoriteLanguage(current: 'auto', favorites: const ['en', 'ru']),
        'en',
      );
    });

    test('a single favorite stays on itself', () {
      expect(
        nextFavoriteLanguage(current: 'de', favorites: const ['de']),
        'de',
      );
    });
  });

  group('language-cycle hotkey settings', () {
    test('are off and unassigned by default', () {
      const stt = SttSettings();
      expect(stt.languageCycleHotkeyEnabled, isFalse);
      expect(stt.languageCycleHotkeyKey, 'L');
    });

    test('round-trip through the stored map', () {
      final stt = const SttSettings().copyWith(
        languageCycleHotkeyEnabled: true,
        languageCycleHotkeyKey: 'J',
        languageCycleHotkeyKeyDisplay: 'J',
        languageCycleHotkeyModifiers: 'meta+shift',
      );
      final restored = SttSettings.fromMap(stt.toMap());
      expect(restored.languageCycleHotkeyEnabled, isTrue);
      expect(restored.languageCycleHotkeyKey, 'J');
      expect(restored.languageCycleHotkeyKeyDisplay, 'J');
      expect(restored.languageCycleHotkeyModifiers, 'meta+shift');
      expect(restored, stt);
    });

    test('a change alone makes the settings unequal', () {
      const base = SttSettings();
      expect(base.copyWith(languageCycleHotkeyEnabled: true) == base, isFalse);
    });
  });
}

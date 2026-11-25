import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/favorite_language_hotkeys.dart';
import 'package:whispaste/core/config/settings_sections.dart';

const _ctrlAlt1 = FavoriteLanguageHotkey(key: '1', modifiers: 'ctrl+alt');
const _ctrlAlt2 = FavoriteLanguageHotkey(
  key: '2',
  modifiers: 'ctrl+alt',
  keyDisplay: '2',
);

void main() {
  group('stored favorite-language hotkeys (#2137)', () {
    test('survive a save and load of the settings', () {
      const stt = SttSettings(
        favoriteLanguages: ['de', 'fa'],
        favoriteLanguageHotkeys: {'de': _ctrlAlt1, 'fa': _ctrlAlt2},
      );
      final restored = SttSettings.fromMap(stt.toMap());
      expect(restored.favoriteLanguageHotkeys, {
        'de': _ctrlAlt1,
        'fa': _ctrlAlt2,
      });
      expect(restored, stt);
    });

    test('an existing install without the setting has no keys', () {
      expect(SttSettings.fromMap(const {}).favoriteLanguageHotkeys, isEmpty);
      expect(SttSettings.defaults.toMap()['stt_favorite_language_hotkeys'], '');
    });

    test('a damaged value costs the keys, never the start', () {
      expect(parseFavoriteLanguageHotkeys('{not json'), isEmpty);
      expect(parseFavoriteLanguageHotkeys('[1,2]'), isEmpty);
      expect(
        parseFavoriteLanguageHotkeys(
          '{"de":{"key":"1","modifiers":"ctrl+alt"},'
          '"en":{"key":"","modifiers":"ctrl"},'
          '"auto":{"key":"3","modifiers":"ctrl"},'
          '"fr":"x"}',
        ),
        {'de': _ctrlAlt1},
      );
    });

    test('only current favorites are active, in their order', () {
      final active = activeFavoriteLanguageHotkeys(
        favorites: const ['fa', 'en', 'de'],
        hotkeys: const {'de': _ctrlAlt1, 'fa': _ctrlAlt2, 'ru': _ctrlAlt1},
      );
      expect(active.map((a) => a.code), ['fa', 'de']);
    });

    test('removing a key keeps the others', () {
      final next = withFavoriteLanguageHotkey(
        const {'de': _ctrlAlt1, 'fa': _ctrlAlt2},
        'de',
        null,
      );
      expect(next, {'fa': _ctrlAlt2});
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  group('SttSettings.favoriteLanguages', () {
    test('defaults to none', () {
      expect(SttSettings.defaults.favoriteLanguages, isEmpty);
      expect(SttSettings.fromMap(const {}).favoriteLanguages, isEmpty);
    });

    test('round-trips through the persisted map', () {
      const stt = SttSettings(favoriteLanguages: ['de', 'en', 'ru']);
      final map = stt.toMap();
      expect(map['stt_favorite_languages'], 'de,en,ru');
      expect(SttSettings.fromMap(map).favoriteLanguages, ['de', 'en', 'ru']);
    });

    test('caps the persisted list at three and drops duplicates', () {
      expect(SttSettings.parseFavoriteLanguages('de,de, en ,,fr,ru'), [
        'de',
        'en',
        'fr',
      ]);
    });

    test('copyWith replaces the list and equality follows it', () {
      const base = SttSettings.defaults;
      final starred = base.copyWith(favoriteLanguages: ['de']);
      expect(starred.favoriteLanguages, ['de']);
      expect(starred, isNot(equals(base)));
      expect(starred, equals(base.copyWith(favoriteLanguages: ['de'])));
    });
  });
}

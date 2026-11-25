import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/stt/whisper/whisper_language_probe.dart';

void main() {
  test('old settings retain language and favorites without a restriction', () {
    final s = SttSettings.fromMap({
      'stt_language': 'de',
      'stt_favorite_languages': 'fr,en',
    });
    expect(s.expectedLanguages, isEmpty);
    expect(s.language, 'de');
    expect(s.favoriteLanguages, ['fr', 'en']);
  });
  test('restriction round trips and clears independently of favorites', () {
    final s = SttSettings.defaults.copyWith(expectedLanguages: ['de', 'en']);
    expect(SttSettings.fromMap(s.toMap()), s);
    expect(s.copyWith(expectedLanguages: []).expectedLanguages, isEmpty);
    expect(s.copyWith(favoriteLanguages: ['fr']).expectedLanguages, [
      'de',
      'en',
    ]);
    expect(
      SttSettings.fromMap({
        'stt_expected_languages': 'de,auto,en,de,invalid',
      }).expectedLanguages,
      ['de', 'en'],
    );
  });
  test(
    'DE+EN never picks a third language, including short ambiguous speech',
    () {
      for (var de = 0; de <= 10; de++) {
        for (var en = 0; en <= 10; en++) {
          final selected = mostLikelyExpectedLanguage(
            {'de': de / 100, 'en': en / 100, 'fr': 0.99},
            ['de', 'en'],
          );
          expect(selected, de >= en ? 'de' : 'en');
        }
      }
    },
  );
  test(
    'unusable probabilities fail instead of falling back to an outside language',
    () {
      expect(
        () => mostLikelyExpectedLanguage(
          {'fr': 1, 'de': double.nan},
          ['de', 'en'],
        ),
        throwsStateError,
      );
    },
  );
  group('automatic detection without expected languages (#2015)', () {
    test('two or more favorites restrict it', () {
      final s = SttSettings.defaults.copyWith(favoriteLanguages: ['de', 'en']);
      expect(s.autoDetectLanguages, ['de', 'en']);
    });
    test('expected languages win over favorites', () {
      final s = SttSettings.defaults.copyWith(
        favoriteLanguages: ['de', 'en'],
        expectedLanguages: ['fr', 'it'],
      );
      expect(s.autoDetectLanguages, ['fr', 'it']);
    });
    test('no or a single favorite keeps detection open as before', () {
      expect(SttSettings.defaults.autoDetectLanguages, isEmpty);
      expect(
        SttSettings.defaults
            .copyWith(favoriteLanguages: ['de'])
            .autoDetectLanguages,
        isEmpty,
      );
    });
    test('favorites Whisper does not know are left out', () {
      expect(
        SttSettings.defaults
            .copyWith(favoriteLanguages: ['de', 'xx'])
            .autoDetectLanguages,
        isEmpty,
      );
      expect(
        SttSettings.defaults
            .copyWith(favoriteLanguages: ['de', 'xx', 'en'])
            .autoDetectLanguages,
        ['de', 'en'],
      );
    });
    test('short, ambiguous speech stays within the favorites', () {
      final allowed = SttSettings.defaults
          .copyWith(favoriteLanguages: ['de', 'en'])
          .autoDetectLanguages;
      for (var de = 0; de <= 10; de++) {
        for (var en = 0; en <= 10; en++) {
          final selected = mostLikelyExpectedLanguage({
            'de': de / 100,
            'en': en / 100,
            'nl': 0.6,
            'af': 0.3,
          }, allowed);
          expect(selected, de >= en ? 'de' : 'en');
        }
      }
    });
  });
}

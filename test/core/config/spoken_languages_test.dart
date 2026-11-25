/// One "Sprachen" choice (#2045) over the stored fixed language and expected
/// languages: existing settings read back as before, and a selection maps to
/// the values the engines already read.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/spoken_languages.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_de.dart';

AppSettings _with({
  String language = 'auto',
  List<String> expected = const [],
}) => AppSettings.defaults.copyWithSections(
  stt: AppSettings.defaults.stt.copyWith(
    language: language,
    expectedLanguages: expected,
  ),
);

void main() {
  group('existing settings', () {
    test('a fixed language is the selection and wins over expected ones', () {
      expect(spokenLanguagesOf(_with(language: 'de')), ['de']);
      expect(spokenLanguagesOf(_with(language: 'de', expected: ['en', 'fr'])), [
        'de',
      ]);
    });
    test('auto with expected languages selects those', () {
      expect(spokenLanguagesOf(_with(expected: ['de', 'en'])), ['de', 'en']);
    });
    test('auto without expected languages selects none', () {
      expect(spokenLanguagesOf(_with()), isEmpty);
    });
    test('the summary names the favorites that restrict auto (#2015)', () {
      final s = _with().copyWithSections(
        stt: _with().stt.copyWith(favoriteLanguages: ['de', 'en']),
      );
      expect(spokenLanguagesOf(s), isEmpty);
      expect(effectiveSpokenLanguagesOf(s), ['de', 'en']);
      expect(effectiveSpokenLanguagesOf(_with(language: 'fr')), ['fr']);
      expect(effectiveSpokenLanguagesOf(_with()), isEmpty);
    });
    test('a legacy display value still reads as its code', () {
      expect(spokenLanguagesOf(_with(language: 'German')), ['de']);
    });
  });

  group('selection to engine settings', () {
    test('one language is the fixed language', () {
      final s = withSpokenLanguages(_with(expected: ['en', 'fr']), ['ru']);
      expect(s.sttLanguageCode, 'ru');
      expect(s.stt.expectedLanguages, isEmpty);
    });
    test('several restrict automatic detection', () {
      final s = withSpokenLanguages(_with(language: 'de'), ['de', 'en']);
      expect(s.sttLanguageCode, 'auto');
      expect(s.stt.expectedLanguages, ['de', 'en']);
    });
    test('none detects every language', () {
      final s = withSpokenLanguages(_with(expected: ['de', 'en']), []);
      expect(s.sttLanguageCode, 'auto');
      expect(s.stt.expectedLanguages, isEmpty);
    });
    test('round trip keeps the selection', () {
      for (final codes in [
        <String>[],
        ['de'],
        ['de', 'en'],
      ]) {
        expect(spokenLanguagesOf(withSpokenLanguages(_with(), codes)), codes);
      }
    });
  });

  test('summary reads auto, one name, or names marked automatic', () {
    final l10n = L10nDe();
    String name(String c) => {'de': 'Deutsch', 'en': 'Englisch'}[c]!;
    expect(spokenLanguagesSummary(l10n, [], name), 'Automatisch erkennen');
    expect(spokenLanguagesSummary(l10n, ['de'], name), 'Deutsch');
    expect(
      spokenLanguagesSummary(l10n, ['de', 'en'], name),
      'Deutsch, Englisch (automatisch)',
    );
  });

  test('engines that detect the language themselves are named', () {
    AppSettings engine(OnDeviceEngine e) =>
        AppSettings.defaults.copyWithSections(
          stt: AppSettings.defaults.stt.copyWith(
            provider: SttProviderType.onDevice.value,
            engine: e.value,
          ),
        );
    expect(spokenLanguagesIgnored(engine(OnDeviceEngine.whisper)), isFalse);
    expect(spokenLanguagesIgnored(engine(OnDeviceEngine.parakeet)), isTrue);
    expect(spokenLanguagesIgnored(engine(OnDeviceEngine.system)), isTrue);
  });
}

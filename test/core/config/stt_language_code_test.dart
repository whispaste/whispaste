/// Behavior tests for the STT recognition-language setting.
///
/// Store-review regression (June 2026): the app advertised 99 Whisper
/// languages but the settings layer only knew four — every other language
/// (e.g. Russian) silently collapsed to the UI locale and produced English
/// transcripts. These tests pin the contract of [AppSettings.sttLanguageCode]:
///
///  - legacy display values persisted by ≤1.2.x ('Auto-detect', 'English',
///    'German', 'French', 'Spanish') keep resolving to their short codes;
///  - any canonical Whisper language code stored as-is passes through;
///  - unknown/corrupt values degrade to 'auto', never crash;
///  - the bundled catalog covers the full 99-language Whisper set.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/whisper_languages.dart';

AppSettings _withSttLanguage(String value) =>
    AppSettings.defaults.copyWith(sttLanguage: value);

void main() {
  group('AppSettings.sttLanguageCode', () {
    test('legacy display values from ≤1.2.x resolve to short codes', () {
      expect(_withSttLanguage('Auto-detect').sttLanguageCode, 'auto');
      expect(_withSttLanguage('English').sttLanguageCode, 'en');
      expect(_withSttLanguage('German').sttLanguageCode, 'de');
      expect(_withSttLanguage('French').sttLanguageCode, 'fr');
      expect(_withSttLanguage('Spanish').sttLanguageCode, 'es');
    });

    test('canonical Whisper codes pass through unchanged', () {
      expect(_withSttLanguage('ru').sttLanguageCode, 'ru');
      expect(_withSttLanguage('he').sttLanguageCode, 'he');
      expect(_withSttLanguage('uk').sttLanguageCode, 'uk');
      expect(_withSttLanguage('ja').sttLanguageCode, 'ja');
      expect(_withSttLanguage('auto').sttLanguageCode, 'auto');
    });

    test('every catalog code round-trips through sttLanguageCode', () {
      for (final code in whisperLanguages.keys) {
        expect(
          _withSttLanguage(code).sttLanguageCode,
          code,
          reason: 'catalog code "$code" must not be remapped',
        );
      }
    });

    test('unknown or corrupt stored values degrade to auto', () {
      expect(_withSttLanguage('Klingon').sttLanguageCode, 'auto');
      expect(_withSttLanguage('').sttLanguageCode, 'auto');
      expect(_withSttLanguage('EN').sttLanguageCode, 'auto');
    });
  });

  group('AppSettings.fromGoConfig transcription language', () {
    test('keeps any catalog code from the legacy Go config', () {
      final s = AppSettings.fromGoConfig({'transcription_language': 'ru'});
      expect(s.sttLanguageCode, 'ru');
    });

    test('legacy four still migrate', () {
      final s = AppSettings.fromGoConfig({'transcription_language': 'de'});
      expect(s.sttLanguageCode, 'de');
    });

    test('unknown or missing values degrade to auto', () {
      expect(
        AppSettings.fromGoConfig({
          'transcription_language': 'xx',
        }).sttLanguageCode,
        'auto',
      );
      expect(
        AppSettings.fromGoConfig(<String, dynamic>{}).sttLanguageCode,
        'auto',
      );
    });
  });

  group('whisperLanguages catalog', () {
    test('covers the full 99-language Whisper set', () {
      expect(whisperLanguages, hasLength(99));
    });

    test('contains the languages the store review called out', () {
      expect(whisperLanguages['ru'], 'Russian');
      expect(whisperLanguages['he'], 'Hebrew');
      expect(whisperLanguages['zh'], 'Chinese');
      expect(whisperLanguages['hi'], 'Hindi');
      expect(whisperLanguages['ar'], 'Arabic');
    });

    test('codes are lowercase Whisper short codes with display names', () {
      for (final entry in whisperLanguages.entries) {
        expect(entry.key, matches(RegExp(r'^[a-z]{2,3}$')));
        expect(entry.value.trim(), isNotEmpty);
      }
    });

    test('does not contain the auto sentinel — auto is not a language', () {
      expect(whisperLanguages.containsKey('auto'), isFalse);
    });
  });
}

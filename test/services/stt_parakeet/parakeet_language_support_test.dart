import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_language_support.dart';

AppSettings _settings({
  String provider = 'On Device',
  String engine = 'parakeet',
  String language = 'ar',
}) => AppSettings(
  stt: SttSettings(provider: provider, engine: engine, language: language),
);

void main() {
  group('parakeetUnsupportedLanguage (SW-05)', () {
    test('reports a language Parakeet cannot transcribe', () {
      expect(parakeetUnsupportedLanguage(_settings()), 'ar');
    });

    test('is silent for a language Parakeet supports', () {
      expect(parakeetUnsupportedLanguage(_settings(language: 'de')), isNull);
      expect(parakeetUnsupportedLanguage(_settings(language: 'ru')), isNull);
    });

    test('is silent for automatic detection', () {
      expect(parakeetUnsupportedLanguage(_settings(language: 'auto')), isNull);
    });

    test('is silent when Whisper is the active engine', () {
      expect(parakeetUnsupportedLanguage(_settings(engine: 'whisper')), isNull);
    });

    test('is silent for a cloud provider', () {
      expect(
        parakeetUnsupportedLanguage(_settings(provider: 'OpenAI')),
        isNull,
      );
    });

    test('a per-call language override is checked instead of the setting', () {
      final settings = _settings(language: 'de');
      expect(
        parakeetUnsupportedLanguage(settings, languageOverride: 'ar'),
        'ar',
      );
      expect(
        parakeetUnsupportedLanguage(
          _settings(language: 'ar'),
          languageOverride: 'en',
        ),
        isNull,
      );
    });
  });
}

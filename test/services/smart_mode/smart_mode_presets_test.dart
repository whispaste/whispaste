import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

void main() {
  group('Smart Mode v2 ticket 09: target-language validation gate', () {
    test('smartModeValidatedTargetLanguages contains all seven '
        'PRODUCT-SPEC languages — each passed its own ticket-09 '
        'validation spike against the real local Gemma-4-E2B-it model '
        '(.scratch/smart-mode-v2/spike-test-results*.md)', () {
      expect(smartModeValidatedTargetLanguages, [
        SmartModeTargetLanguage.german,
        SmartModeTargetLanguage.english,
        SmartModeTargetLanguage.spanish,
        SmartModeTargetLanguage.french,
        SmartModeTargetLanguage.portuguese,
        SmartModeTargetLanguage.mandarin,
        SmartModeTargetLanguage.russian,
      ]);
    });

    test('an unrecognized settings code falls back to English rather than '
        'throwing', () {
      expect(
        smartModeTargetLanguageFromSettingsValue('xx'),
        SmartModeTargetLanguage.english,
      );
    });

    test('all seven official PRODUCT-SPEC languages are modeled', () {
      expect(SmartModeTargetLanguage.values, hasLength(7));
      expect(SmartModeTargetLanguage.values.map((l) => l.code).toSet(), {
        'de',
        'en',
        'es',
        'fr',
        'pt',
        'zh',
        'ru',
      });
    });
  });
}

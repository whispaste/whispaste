import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

void main() {
  group('Smart Mode dictionary prompt', () {
    test(
      'all active presets include normalized terms after the base prompt',
      () {
        for (final preset in SmartModePreset.values.where(
          (preset) => preset != SmartModePreset.off,
        )) {
          final base = smartModeSystemPromptFor(preset);
          expect(smartModeSystemPromptFor(preset, vocabulary: ' , \n '), base);
          final prompt = smartModeSystemPromptFor(
            preset,
            vocabulary: ' WhisPaste, PostgreSQL\n Müller ',
          );
          expect(prompt, startsWith(base));
          expect(
            prompt,
            contains(jsonEncode(['WhisPaste', 'PostgreSQL', 'Müller'])),
          );
        }
      },
    );

    test(
      'budget includes JSON overhead and preserves priority, whole terms',
      () {
        final first = 'a' * (smartModeDictionaryByteBudget - 4);
        expect(smartModeDictionaryJson(first), jsonEncode([first]));
        expect(smartModeDictionaryJson('$first, next'), jsonEncode([first]));
        expect(smartModeDictionaryJson('${first}a, short'), isEmpty);
      },
    );

    test('UTF-8 bytes and escaped data count against the separate budget', () {
      final vocabulary = List.filled(300, 'ä"\\').join(',');
      final dictionary = smartModeDictionaryJson(vocabulary);
      final terms = (jsonDecode(dictionary) as List).cast<String>();
      expect(terms, isNotEmpty);
      expect(terms.toSet(), {'ä"\\'});
      expect(
        utf8.encode(dictionary).length,
        lessThanOrEqualTo(smartModeDictionaryByteBudget),
      );
      expect(
        utf8.encode(jsonEncode([...terms, terms.first])).length,
        greaterThan(smartModeDictionaryByteBudget),
      );
    });
  });

  group('Smart Mode v2 ticket 09: target-language validation gate', () {
    test('smartModeValidatedTargetLanguages contains all seven '
        'PRODUCT-SPEC languages — each passed its own ticket-09 '
        'validation spike against the real local Gemma-4-E2B-it model', () {
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

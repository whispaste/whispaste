import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

void main() {
  group('Smart Mode v2 ticket 09: target-language validation gate', () {
    test('smartModeValidatedTargetLanguages currently contains only German — '
        'the other six PRODUCT-SPEC languages each need their own ticket-09 '
        'validation spike (real local-model or cloud inference, unavailable '
        'in this sandbox) before being added here', () {
      expect(smartModeValidatedTargetLanguages, [
        SmartModeTargetLanguage.german,
      ]);
    });

    test(
      'every SmartModeTargetLanguage other than the validated subset falls '
      'back to German rather than being resolvable from its settings code',
      () {
        final unvalidated = SmartModeTargetLanguage.values.where(
          (lang) => !smartModeValidatedTargetLanguages.contains(lang),
        );

        expect(unvalidated, isNotEmpty);
        for (final lang in unvalidated) {
          expect(
            smartModeTargetLanguageFromSettingsValue(lang.code),
            SmartModeTargetLanguage.german,
            reason:
                '${lang.name} (${lang.code}) has not passed its ticket-09 '
                'validation spike and must not be selectable yet',
          );
        }
      },
    );

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

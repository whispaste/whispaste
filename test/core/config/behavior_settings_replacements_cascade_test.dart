/// #1004: "Build replacements on each other" — on by default, stored, and
/// carried into the text steps a parked dictation keeps.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/dictation_text_steps.dart';

void main() {
  test('defaults to on', () {
    expect(AppSettings.defaults.behavior.replacementsCascade, isTrue);
  });

  test('off survives a storage round-trip', () {
    final settings = AppSettings.defaults.copyWithSections(
      behavior: AppSettings.defaults.behavior.copyWith(
        replacementsCascade: false,
      ),
    );
    final map = settings.toStorageMap();
    expect(map['text_replacements_cascade'], 'false');
    expect(
      AppSettings.fromStorageMap(map).behavior.replacementsCascade,
      isFalse,
    );
  });

  test('a store from before the setting keeps the cascade on', () {
    final map = Map<String, String>.from(AppSettings.defaults.toStorageMap())
      ..remove('text_replacements_cascade');
    expect(
      AppSettings.fromStorageMap(map).behavior.replacementsCascade,
      isTrue,
    );
  });

  group('DictationTextSteps', () {
    test('takes the setting and keeps it through JSON', () {
      final settings = AppSettings.defaults.copyWithSections(
        behavior: AppSettings.defaults.behavior.copyWith(
          replacementsCascade: false,
        ),
      );
      final steps = DictationTextSteps.fromSettings(settings);
      expect(steps.replacementsCascade, isFalse);
      expect(
        DictationTextSteps.tryParse(steps.toJson())!.replacementsCascade,
        isFalse,
      );
    });

    test('a record parked before the setting runs the cascade', () {
      final json = <String, Object?>{
        'removeFillerWords': false,
        'spokenPunctuation': false,
        'voiceLineBreaks': false,
        'textReplacements': true,
      };
      expect(DictationTextSteps.tryParse(json)!.replacementsCascade, isTrue);
    });

    test('apply passes the mode to the replacements', () async {
      bool? seen;
      const steps = DictationTextSteps(
        removeFillerWords: false,
        spokenPunctuation: false,
        voiceLineBreaks: false,
        textReplacements: true,
        replacementsCascade: false,
      );
      await steps.apply(
        'x',
        languageCode: 'de',
        applyReplacements: (text, {cascade = true}) async {
          seen = cascade;
          return text;
        },
      );
      expect(seen, isFalse);
    });
  });
}

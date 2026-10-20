import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Visible labels the maintainer chose on 2026-10-17 after comparing them
/// with a rename series (CONTEXT.md §5.3a). Proofreading or terminology
/// passes must not replace them; a deliberate change updates CONTEXT.md and
/// this table in the same commit.
const _fixedTerms = <String, Map<String, String>>{
  'de': {
    'navHistory': 'Aufnahmen',
    'navReplacements': 'Wörterbuch',
    'navSnippets': 'Textbausteine',
    'navAnalytics': 'Statistik',
    'sidePanelTranscriptionsTitle': 'Transkriptionen',
    'dockDictate': 'Diktieren',
    'settingsAreaShortcuts': 'Tastenkürzel',
    // The section keeps its name; the row inside it is the speech model.
    'settingsSpeechRecognition': 'Spracherkennung',
    'settingsSttEngine': 'Sprachmodell',
  },
  'en': {
    'navHistory': 'Recordings',
    'navReplacements': 'Dictionary',
    'navSnippets': 'Snippets',
    'navAnalytics': 'Statistics',
    'sidePanelTranscriptionsTitle': 'Transcriptions',
    'dockDictate': 'Dictate',
    'settingsAreaShortcuts': 'Keyboard shortcuts',
    'settingsSpeechRecognition': 'Speech recognition',
    'settingsSttEngine': 'Speech model',
  },
  'es': {'dockDictate': 'Dictar', 'settingsSttEngine': 'Modelo de voz'},
  'pt': {'dockDictate': 'Ditar', 'settingsSttEngine': 'Modelo de voz'},
  'ru': {
    'dockDictate': 'Диктовка',
    'settingsSttEngine': 'Модель распознавания речи',
  },
  'he': {'dockDictate': 'הכתבה', 'settingsSttEngine': 'מודל זיהוי דיבור'},
};

void main() {
  for (final MapEntry(key: locale, value: terms) in _fixedTerms.entries) {
    test('fixed UI terms keep their wording in app_$locale.arb', () {
      final arb =
          jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, Object?>;
      for (final MapEntry(:key, :value) in terms.entries) {
        expect(
          arb[key],
          value,
          reason: '$key is a fixed UI term (CONTEXT.md §5.3a)',
        );
      }
    });
  }

  // The German texts about the speech model say "Sprachmodell" (CONTEXT.md
  // §5.3a). "Sprachdienst", "Spracherkennungs-Modell(le)" and "Engine" are
  // not used for it, and Smart Mode's model is no "Engine" either.
  test('German STT texts never say "Sprachdienst", "Spracherkennungs-Modell" '
      'or "Engine"', () {
    final arb =
        jsonDecode(File('lib/core/l10n/app_de.arb').readAsStringSync())
            as Map<String, Object?>;
    final banned = RegExp(
      r'Sprachdienst|Spracherkennungs-?modell|Engine',
      caseSensitive: false,
    );
    final offenders = [
      for (final MapEntry(:key, :value) in arb.entries)
        if (!key.startsWith('@') && value is String && banned.hasMatch(value))
          key,
    ];
    expect(offenders, isEmpty, reason: 'use "Sprachmodell" for the STT model');
  });

  // The German navigation says "Textbausteine", so every other German text
  // names the feature the same way (maintainer decision 2026-10-17).
  test('German texts never say "Snippet"', () {
    final arb =
        jsonDecode(File('lib/core/l10n/app_de.arb').readAsStringSync())
            as Map<String, Object?>;
    final offenders = [
      for (final MapEntry(:key, :value) in arb.entries)
        if (!key.startsWith('@') &&
            value is String &&
            value.toLowerCase().contains('snippet'))
          key,
    ];
    expect(offenders, isEmpty, reason: 'say "Textbaustein" in German');
  });

  // The German spelling of the factory reset is one word, "Werksreset"
  // (title, toast and manual all use it).
  test('German texts spell the factory reset "Werksreset"', () {
    final arb =
        jsonDecode(File('lib/core/l10n/app_de.arb').readAsStringSync())
            as Map<String, Object?>;
    final offenders = [
      for (final MapEntry(:key, :value) in arb.entries)
        if (!key.startsWith('@') &&
            value is String &&
            value.toLowerCase().contains('werks-reset'))
          key,
    ];
    expect(offenders, isEmpty, reason: 'write "Werksreset" in German');
  });

  // Smart Mode's model is the "Textmodell" (CONTEXT.md §5.3a). Its German
  // texts never call it "Sprachmodell", "Smart-Mode-Modell" or a standalone
  // "Modell"; the speech model keeps "Sprachmodell". A text may name the
  // speech model too, but only next to "Textmodell", so the two stay told
  // apart (e.g. the RAM note: the text model shares memory with it).
  test('German Smart Mode texts call its model "Textmodell"', () {
    final arb =
        jsonDecode(File('lib/core/l10n/app_de.arb').readAsStringSync())
            as Map<String, Object?>;
    // A standalone "Modell" (compounds like "Textmodell" or "STT-Modell" are
    // not matched by this rule; "Sprachmodell" and "Smart-Mode-Modell" are
    // checked explicitly below).
    final bareModel = RegExp(
      r'(?<![\wäöüß-])modell(?![\wäöüß])',
      caseSensitive: false,
    );
    final offenders = [
      for (final MapEntry(:key, :value) in arb.entries)
        if (!key.startsWith('@') &&
            (key.contains('smartMode') || key.contains('SmartMode')) &&
            value is String &&
            ((value.contains('Sprachmodell') &&
                    !value.contains('Textmodell')) ||
                value.contains('Smart-Mode-Modell') ||
                bareModel.hasMatch(value)))
          key,
    ];
    expect(offenders, isEmpty, reason: 'write "Textmodell" (CONTEXT.md §5.3a)');
  });

  // UIA-ANA-04: the time saved is two thirds of the recording time, not a
  // measurement, so its label says so in every app language.
  test('the time-saved label marks itself as an estimate', () {
    const markers = {
      'de': 'geschätzt',
      'en': 'estimate',
      'es': 'estimación',
      'pt': 'estimativa',
      'he': 'הערכה',
      'ru': 'оценка',
    };
    for (final MapEntry(key: lang, value: marker) in markers.entries) {
      final arb =
          jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
              as Map<String, Object?>;
      expect(arb['analyticsTimeSaved'], contains(marker), reason: lang);
    }
  });
}

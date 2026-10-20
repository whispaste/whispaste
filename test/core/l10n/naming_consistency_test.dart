import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Naming guards for the model names and the area / overlay / hotkey terms
/// (UI audit 2026-10, NAM-01 to NAM-17). Each guard names the rule it protects
/// so a later text pass cannot quietly bring an old term back.

Map<String, Object?> _arb(String locale) =>
    jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

Iterable<MapEntry<String, String>> _values(String locale) sync* {
  for (final MapEntry(:key, :value) in _arb(locale).entries) {
    if (key.startsWith('@') || value is! String) continue;
    yield MapEntry(key, value);
  }
}

void main() {
  // NAM-01 / NAM-07 / NAM-11: one fixed vocabulary for the three quality
  // tiers. The family name ("Whisper") is a proper noun and not translated.
  const tierWords = <String, Map<String, String>>{
    'de': {
      'qualityTierCompactLabel': 'Schnell',
      'qualityTierBalancedLabel': 'Ausgewogen',
      'qualityTierPremiumLabel': 'Genau',
    },
    'en': {
      'qualityTierCompactLabel': 'Fast',
      'qualityTierBalancedLabel': 'Balanced',
      'qualityTierPremiumLabel': 'Accurate',
    },
    'es': {
      'qualityTierCompactLabel': 'Rápido',
      'qualityTierBalancedLabel': 'Equilibrado',
      'qualityTierPremiumLabel': 'Preciso',
    },
    'pt': {
      'qualityTierCompactLabel': 'Rápido',
      'qualityTierBalancedLabel': 'Equilibrado',
      'qualityTierPremiumLabel': 'Preciso',
    },
    'he': {
      'qualityTierCompactLabel': 'מהיר',
      'qualityTierBalancedLabel': 'מאוזן',
      'qualityTierPremiumLabel': 'מדויק',
    },
    'ru': {
      'qualityTierCompactLabel': 'Быстрый',
      'qualityTierBalancedLabel': 'Сбалансированный',
      'qualityTierPremiumLabel': 'Точный',
    },
  };

  group('quality tier vocabulary (NAM-01, NAM-11)', () {
    for (final MapEntry(key: locale, value: words) in tierWords.entries) {
      test('app_$locale.arb uses the fixed tier words', () {
        final arb = _arb(locale);
        for (final MapEntry(:key, :value) in words.entries) {
          expect(arb[key], value, reason: '$key must be "$value" in $locale');
        }
      });
    }
  });

  // NAM-01 / NAM-03 / NAM-07 / NAM-10: the retired labels must not survive in
  // any language, so the old three-word names cannot reappear in a UI string.
  group('retired model labels are gone (NAM-01, NAM-03, NAM-07)', () {
    const retired = [
      'Schnell & Kompakt',
      'Quick & compact',
      'Beste Qualität',
      'Best quality',
      'Schnell & europäisch',
      'Fast & European',
      'Alle 99 Sprachen',
      'All 99 languages',
      'Parakeet-TDT-Modell',
      'Parakeet TDT model',
      'Gemma-4-E2B-it',
      'Large v3 Turbo',
    ];
    for (final locale in tierWords.keys) {
      test('app_$locale.arb contains none of them', () {
        final offenders = [
          for (final e in _values(locale))
            for (final old in retired)
              if (e.value.contains(old)) '${e.key}: "${e.value}"',
        ];
        expect(offenders, isEmpty, reason: 'use the model display name');
      });
    }
  });

  // NAM-11: the setting is about speed and accuracy, not about "quality".
  test('German texts say "Stufe", not "Qualitätsstufe" (NAM-11)', () {
    final offenders = [
      for (final e in _values('de'))
        if (e.value.contains('Qualitätsstufe')) e.key,
    ];
    expect(offenders, isEmpty);
  });

  // NAM-06: the speech recognition is called "Spracherkennung" everywhere in
  // German UI text. "Sprachdienst" stays only as a search synonym, so that
  // users who type the old word still find the section.
  group('German UI says "Spracherkennung", not "Sprachdienst" (NAM-06)', () {
    const searchSynonyms = {'settingsSearchKeywordsStt'};
    test('no German UI value contains "Sprachdienst"', () {
      final offenders = [
        for (final e in _values('de'))
          if (!searchSynonyms.contains(e.key) &&
              e.value.toLowerCase().contains('sprachdienst'))
            e.key,
      ];
      expect(offenders, isEmpty, reason: 'write "Spracherkennung" instead');
    });
  });

  // NAM-13 / NAM-14: fixed area names (CONTEXT.md §5.3a). The page title of
  // an area must match its navigation label.
  group('area page titles match the navigation label (NAM-13, NAM-14)', () {
    for (final locale in tierWords.keys) {
      test('app_$locale.arb: Wörterbuch / Dictionary page title', () {
        final arb = _arb(locale);
        expect(arb['pageReplacementsTitle'], arb['navReplacements']);
      });
      test('app_$locale.arb: history page title matches its nav label', () {
        final arb = _arb(locale);
        expect(arb['pageHistoryTitle'], arb['navHistory']);
      });
    }
  });

  // NAM-16: the hotkey fields say "Hotkey" like the rest of the app, using the
  // same word as the existing "current hotkey" label of each language.
  group('hotkey field labels match settingsCurrentHotkey (NAM-16)', () {
    const fields = [
      'settingsQuickNoteCurrentHotkey',
      'settingsSnippetPickerCurrentHotkey',
      'settingsSmartModeCurrentHotkey',
    ];
    for (final locale in tierWords.keys) {
      test('app_$locale.arb', () {
        final arb = _arb(locale);
        for (final field in fields) {
          expect(
            arb[field],
            arb['settingsCurrentHotkey'],
            reason: '$field should use the settingsCurrentHotkey wording',
          );
        }
      });
    }
  });

  // NAM-17: "Floating button" is the systemwide microphone button, the
  // "Overlay" is the waveform. Neither is called a "window" or "Floating-Button
  // menu" in the German or English UI.
  group('overlay and floating button names (NAM-17)', () {
    test('German UI has no "Floating-Button", "schwebendes Fenster" or '
        '"schwebender Aufnahmebutton"', () {
      final offenders = [
        for (final e in _values('de'))
          if (RegExp(
            r'Floating-Button|Floating Button|schwebendes Fenster|'
            r'schwebende[rnsm]? Aufnahme-?button',
            caseSensitive: false,
          ).hasMatch(e.value))
            e.key,
      ];
      expect(offenders, isEmpty);
    });

    test(
      'English UI has no "Floating window" or "Floating recording button"',
      () {
        final offenders = [
          for (final e in _values('en'))
            if (RegExp(
              r'Floating window|Floating recording button',
              caseSensitive: false,
            ).hasMatch(e.value))
              e.key,
        ];
        expect(offenders, isEmpty);
      },
    );
  });
}

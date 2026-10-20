import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

/// The factory-reset dialog names what is deleted. The core terms must stay in
/// the list in every language, so a rename or a dropped category shows up here
/// (BIZ-26, DEV-80). "Notizen"/"Notes" must be named because notes are deleted
/// (GS-025).
const _coreTermsByLanguage = <String, List<String>>{
  'de': [
    'Transkriptionen',
    'Notizen',
    'Wörterbuch',
    'Textbausteine',
    'Statistik',
    'API-Schlüssel',
  ],
  'en': [
    'Transcriptions',
    'Notes',
    'Dictionary',
    'Snippets',
    'Statistics',
    'API keys',
  ],
  'es': [
    'Transcripciones',
    'Notas',
    'Diccionario',
    'Snippets',
    'Estadísticas',
    'claves de API',
  ],
  'pt': [
    'transcrições',
    'Notas',
    'Dicionário',
    'Snippets',
    'Estatísticas',
    'chaves de API',
  ],
  'he': ['תמלולים', 'פתקים', 'מילון', 'קטעים', 'סטטיסטיקה', 'מפתחות API'],
  'ru': [
    'транскрипции',
    'заметк', // word stem: the message uses the instrumental 'заметками'
    'Словарь',
    'Сниппеты',
    'Статистика',
    'ключи API',
  ],
};

void main() {
  for (final entry in _coreTermsByLanguage.entries) {
    test('${entry.key} reset message names the core categories', () {
      final text = lookupL10n(Locale(entry.key)).settingsFactoryResetMessage;
      for (final term in entry.value) {
        expect(text.toLowerCase(), contains(term.toLowerCase()));
      }
    });
  }

  test('German reset message avoids the ambiguous "Anmerkungen" (DEV-81)', () {
    final text = lookupL10n(const Locale('de')).settingsFactoryResetMessage;
    expect(text, isNot(contains('Anmerkung')));
  });
}

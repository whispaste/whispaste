/// The handbook quotes UI labels („Auto-Paste“, “PIN protection”) so readers
/// recognise them on screen. A renamed label silently leaves the handbook
/// pointing at a word the app no longer shows — this guard fails instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Quoted text in every typographic style the six ARB files use.
final _quoted = RegExp(r'„([^“]+)“|“([^”]+)”|«([^»]+)»|"([^"]+)"');

/// Spoken voice-note commands; the app matches these literally.
final _voiceCommand = RegExp(r'^(tag|correct|korrektur):');

/// Quotes that are not UI labels, with the reason they stay.
const _notLabels = <String, String>{
  'OpenAI': 'provider name, not a label',
  'äh': 'example filler word',
  'um': 'example filler word',
  'eh': 'example filler word',
  'é': 'example filler word',
  'Универсальный доступ': 'macOS system settings pane name',
  'Secure Keyboard Entry': 'Terminal/iTerm2 menu item, not a WhisPaste label',
  'Sichere Tastatureingabe': 'Terminal menu item, not a WhisPaste label',
  'Entrada segura del teclado': 'Terminal menu item, not a WhisPaste label',
  'Безопасный ввод с клавиатуры': 'Terminal menu item, not a WhisPaste label',
  // macOS System Settings strings the globe-key and Input Monitoring steps
  // quote verbatim; the labels belong to macOS, not to WhisPaste.
  '🌐-Taste drücken für': 'macOS System Settings label (globe key), not ours',
  'Keine Aktion': 'macOS System Settings option (globe key), not ours',
  'Press 🌐 key to': 'macOS System Settings label (globe key), not ours',
  'Do Nothing': 'macOS System Settings option (globe key), not ours',
  'Pulsar la tecla 🌐 para':
      'macOS System Settings label (globe key), not ours',
  'לחיצה על מקש 🌐': 'macOS System Settings label (globe key), not ours',
  'אל תעשה כלום': 'macOS System Settings option (globe key), not ours',
  'Pressionar a tecla 🌐 para':
      'macOS System Settings label (globe key), not ours',
  'Não Fazer Nada': 'macOS System Settings option (globe key), not ours',
  'Нажатие клавиши 🌐': 'macOS System Settings label (globe key), not ours',
  'Мониторинг ввода': 'macOS System Settings pane (Input Monitoring), not ours',
  // Example snippet name spoken after the picker trigger word (C06S2B2I1).
  'Signatur': 'example snippet name the user says, not a label',
  'signature': 'example snippet name the user says, not a label',
  'firma': 'example snippet name the user says, not a label',
  'חתימה': 'example snippet name the user says, not a label',
  'assinatura': 'example snippet name the user says, not a label',
  'подпись': 'example snippet name the user says, not a label',
};

String _trim(String text) => text.trim().replaceAll(RegExp(r'[.…:]+$'), '');

void main() {
  final arbs = Directory('lib/core/l10n')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'app_[a-z]+\.arb$').hasMatch(f.path))
      .toList();

  test('finds the app languages', () {
    expect(arbs.length, greaterThanOrEqualTo(6));
  });

  for (final arb in arbs) {
    final lang = RegExp(r'app_([a-z]+)\.arb$').firstMatch(arb.path)!.group(1);
    test('every label the $lang handbook quotes exists in the $lang UI', () {
      final values = (jsonDecode(arb.readAsStringSync()) as Map)
          .cast<String, Object?>();
      final ui = {
        for (final MapEntry(:key, :value) in values.entries)
          if (!key.startsWith('@') &&
              !key.startsWith('manual') &&
              value is String)
            _trim(value),
      };
      final stale = <String>[];
      for (final MapEntry(:key, :value) in values.entries) {
        if (!key.startsWith('manual') || value is! String) continue;
        for (final match in _quoted.allMatches(value)) {
          final quote = _trim(
            match.groups([1, 2, 3, 4]).firstWhere((g) => g != null)!,
          );
          if (quote.contains('{') ||
              _voiceCommand.hasMatch(quote) ||
              _notLabels.containsKey(quote) ||
              ui.contains(quote)) {
            continue;
          }
          stale.add('$key: „$quote“');
        }
      }
      expect(
        stale,
        isEmpty,
        reason:
            'Quoted text must match a UI string of the same language exactly '
            '(case included). Update the handbook text, or list a quote that '
            'is not a label in _notLabels with a reason.',
      );
    });
  }
}

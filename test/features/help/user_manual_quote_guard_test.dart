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
  // The Siri step of the hotkey section (#1607) quotes macOS System Settings
  // verbatim: the pane names and the keyboard shortcut row belong to macOS.
  'Siri': 'Apple product name, not a WhisPaste label',
  'Apple Intelligence & Siri': 'macOS System Settings pane, not ours',
  'Apple Intelligence y Siri': 'macOS System Settings pane, not ours',
  'Apple Intelligence e Siri': 'macOS System Settings pane, not ours',
  'Apple Intelligence и Siri': 'macOS System Settings pane, not ours',
  'Siri & Spotlight': 'macOS System Settings pane (older macOS), not ours',
  'Siri y Spotlight': 'macOS System Settings pane (older macOS), not ours',
  'Siri e Spotlight': 'macOS System Settings pane (older macOS), not ours',
  'Siri и Spotlight': 'macOS System Settings pane (older macOS), not ours',
  'Tastaturkurzbefehl': 'macOS System Settings row (Siri), not ours',
  'Keyboard shortcut': 'macOS System Settings row (Siri), not ours',
  'Función rápida de teclado': 'macOS System Settings row (Siri), not ours',
  'Atalho de teclado': 'macOS System Settings row (Siri), not ours',
  'Сочетание клавиш': 'macOS System Settings row (Siri), not ours',
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
  // The file-manager entry (#1684): the verb the installer registers and the
  // menu names of Explorer, Finder and the Linux file managers.
  // Only the NSIS installer's verb (DE/EN) shows in Explorer; the Store
  // package is reached through "Open With" (#1701). The parity test holds
  // each handbook quote to the installer verb.
  'Mit WhisPaste transkribieren': 'Explorer menu verb the installer writes',
  'Transcribe with WhisPaste': 'Explorer menu verb the installer writes',
  'Weitere Optionen anzeigen': 'Windows 11 Explorer menu, not ours',
  'Show more options': 'Windows 11 Explorer menu, not ours',
  'Mostrar más opciones': 'Windows 11 Explorer menu, not ours',
  'Mostrar mais opções': 'Windows 11 Explorer menu, not ours',
  'Показать дополнительные параметры': 'Windows 11 Explorer menu, not ours',
  'הצג אפשרויות נוספות': 'Windows 11 Explorer menu, not ours',
  'Öffnen mit': 'Finder/file manager menu, not ours',
  'Open With': 'Finder/file manager menu, not ours',
  'Abrir con': 'Finder/file manager menu, not ours',
  'Abrir com': 'Finder/file manager menu, not ours',
  'Открыть в программе': 'Finder menu, not ours',
  'Открыть с помощью': 'Linux file manager menu, not ours',
  'פתח באמצעות': 'Finder/file manager menu, not ours',
  // Handbook examples of runtime-composed values (C14S20B3, C14S23B1): the
  // mic suggestion has a {mic} placeholder in the UI, the paste status words
  // are built from state. Tracked in #1014.
  'Vorschlag: Gerät': 'mic suggestion with the device name as a placeholder',
  'Suggestion: device': 'mic suggestion with the device name as a placeholder',
  'Sugerencia: dispositivo':
      'mic suggestion with the device name as a placeholder',
  'Sugestão: dispositivo':
      'mic suggestion with the device name as a placeholder',
  'Предложение: устройство':
      'mic suggestion with the device name as a placeholder',
  'הצעה: מכשיר': 'mic suggestion with the device name as a placeholder',
  'aus': 'paste status word shown by the test-recording step',
  'nur über die Zwischenablage':
      'paste status word shown by the test-recording step',
  'off': 'paste status word shown by the test-recording step',
  'via clipboard only': 'paste status word shown by the test-recording step',
  'desactivado': 'paste status word shown by the test-recording step',
  'solo por el portapapeles':
      'paste status word shown by the test-recording step',
  'desligada': 'paste status word shown by the test-recording step',
  'só pela área de transferência':
      'paste status word shown by the test-recording step',
  'выключена': 'paste status word shown by the test-recording step',
  'только через буфер обмена':
      'paste status word shown by the test-recording step',
  'כבויה': 'paste status word shown by the test-recording step',
  'דרך הלוח בלבד': 'paste status word shown by the test-recording step',
  // Example snippet name spoken after the picker trigger word (C06S2B2I1).
  'Signatur': 'example snippet name the user says, not a label',
  'signature': 'example snippet name the user says, not a label',
  'firma': 'example snippet name the user says, not a label',
  'חתימה': 'example snippet name the user says, not a label',
  'assinatura': 'example snippet name the user says, not a label',
  'подпись': 'example snippet name the user says, not a label',
  // Example word forms in the replacement match-mode item (C05S2B1I2).
  'Projekte': 'example word form, not a label',
  'Projekt': 'example trigger word, not a label',
  'projects': 'example word form, not a label',
  'project': 'example trigger word, not a label',
  'proyectos': 'example word form, not a label',
  'proyecto': 'example trigger word, not a label',
  'projetos': 'example word form, not a label',
  'projeto': 'example trigger word, not a label',
  'проекты': 'example word form, not a label',
  'проект': 'example trigger word, not a label',
  'פרויקטים': 'example word form, not a label',
  'פרויקט': 'example trigger word, not a label',
  // Fragment of the key footer while dictating (overlayNoticeFooterDictating);
  // the full string carries the {hotkey} placeholder.
  'beenden und einfügen':
      'key-footer fragment, see overlayNoticeFooterDictating',
  'finish and paste': 'key-footer fragment, see overlayNoticeFooterDictating',
  'terminar y pegar': 'key-footer fragment, see overlayNoticeFooterDictating',
  'terminar e colar': 'key-footer fragment, see overlayNoticeFooterDictating',
  'закончить и вставить':
      'key-footer fragment, see overlayNoticeFooterDictating',
  // Cascade example in the replacements chapter (C05S1B4): spoken trigger and
  // replacement texts the reader makes up, not labels.
  'mfg': 'example replacement trigger, not a label',
  'mit freundlichen Grüßen': 'example replacement text, not a label',
  'Grüßen': 'example replacement trigger, not a label',
  'Grüßen 👋': 'example replacement text, not a label',
  // Preset name the reader makes up in the custom-presets item (C04S2B2I5).
  'Als höfliche E-Mail formulieren': 'example preset name, not a label',
  'Write it as a polite e-mail': 'example preset name, not a label',
  'Redáctalo como un correo amable': 'example preset name, not a label',
  'Escreve como um e-mail cordial': 'example preset name, not a label',
  'Оформи как вежливое письмо': 'example preset name, not a label',
  'לנסח כמייל מנומס': 'example preset name, not a label',
  // The "…" overflow button of the tray panel (C01S1B3Panel); _trim strips the
  // ellipsis, which leaves an empty quote.
  '': 'ellipsis glyph of the tray panel overflow button, not a text label',
  // Overflow-menu glyph (C06S2B4), an icon rather than a text label.
  '⋮': 'overflow menu icon glyph, not a text label',
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

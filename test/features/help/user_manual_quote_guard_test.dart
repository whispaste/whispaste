/// The handbook quotes UI labels („Auto-Paste“, “PIN protection”) so readers
/// recognise them on screen. A renamed label silently leaves the handbook
/// pointing at a word the app no longer shows — this guard fails instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Quoted text in every typographic style the ARB files use.
final _quoted = RegExp(r'„([^“]+)“|“([^”]+)”|«([^»]+)»|"([^"]+)"');

/// Spoken voice-note commands; the app matches these literally.
final _voiceCommand = RegExp(r'^(tag|correct|korrektur):');

/// Quotes that are not UI labels, with the reason they stay.
const _notLabels = <String, String>{
  'OpenAI': 'provider name, not a label',
  'history_set_aside': 'data folder name of a set-aside history (#1023)',
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
  // French, Italian and Simplified Chinese (#1951): the same kinds of
  // quotes as above, in the new handbook languages.
  'termina e incolla': 'key-footer fragment, see overlayNoticeFooterDictating',
  'ehm': 'example filler word',
  "Scrivilo come un'e-mail cortese": 'example preset name, not a label',
  'cmq': 'example replacement trigger, not a label',
  'comunque': 'example replacement text, not a label',
  'comunque 👋': 'example replacement text, not a label',
  'progetti': 'example word form, not a label',
  'progetto': 'example trigger word, not a label',
  '呃': 'example filler word',
  '写成一封礼貌的邮件': 'example preset name, not a label',
  '签名': 'example snippet name the user says, not a label',
  'Mostra altre opzioni': 'Windows 11 Explorer menu, not ours',
  'Apri con': 'Finder/file manager menu, not ours',
  'Abbreviazione da tastiera': 'macOS System Settings row (Siri), not ours',
  'Inserimento sicuro da tastiera': 'Terminal menu item, not a WhisPaste label',
  'Premi il tasto 🌐 per': 'macOS System Settings label (globe key), not ours',
  'Suggerimento: dispositivo':
      'mic suggestion with the device name as a placeholder',
  '显示更多选项': 'Windows 11 Explorer menu, not ours',
  '打开方式': 'Finder/file manager menu, not ours',
  'Apple 智能与 Siri': 'macOS System Settings pane, not ours',
  'Siri 与聚焦': 'macOS System Settings pane (older macOS), not ours',
  '键盘快捷键': 'macOS System Settings row (Siri), not ours',
  '安全键盘输入': 'Terminal menu item, not a WhisPaste label',
  '按下 🌐 键时': 'macOS System Settings label (globe key), not ours',
  '无操作': 'macOS System Settings option (globe key), not ours',
  '建议：设备': 'mic suggestion with the device name as a placeholder',
  '仅通过剪贴板': 'paste status word shown by the test-recording step',
  'terminer et coller': 'key-footer fragment, see overlayNoticeFooterDictating',
  'euh': 'example filler word',
  'Formuler comme un e-mail poli': 'example preset name, not a label',
  'projets': 'example word form, not a label',
  'projet': 'example trigger word, not a label',
  "Afficher plus d'options": 'Windows 11 Explorer menu, not ours',
  'Ouvrir avec': 'Finder/file manager menu, not ours',
  'Apple Intelligence et Siri': 'macOS System Settings pane, not ours',
  'Siri et Spotlight': 'macOS System Settings pane (older macOS), not ours',
  'Raccourci clavier': 'macOS System Settings row (Siri), not ours',
  'Entrée clavier sécurisée': 'Terminal menu item, not a WhisPaste label',
  'Appuyer sur la touche 🌐 pour':
      'macOS System Settings label (globe key), not ours',
  'Suggestion\u00a0: appareil':
      'mic suggestion with the device name as a placeholder',
  // The macOS contacts paragraph (#2037) quotes the Contacts app and the
  // System Settings path verbatim; both belong to macOS.
  '\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u044b':
      'Contacts app name (macOS, GNOME), not ours',
  '\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u044b\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u2192 \u041a\u043e\u043d\u0444\u0438\u0434\u0435\u043d\u0446\u0438\u0430\u043b\u044c\u043d\u043e\u0441\u0442\u044c \u0438 \u0431\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u043e\u0441\u0442\u044c \u2192 \u041a\u043e\u043d\u0442\u0430\u043a\u0442\u044b':
      'macOS System Settings path (Contacts), not ours',
  '\u901a\u8baf\u5f55': 'macOS Contacts app name, not ours',
  '\u7cfb\u7edf\u8bbe\u7f6e': 'macOS System Settings app name, not ours',
  '\u7cfb\u7edf\u8bbe\u7f6e \u2192 \u9690\u79c1\u4e0e\u5b89\u5168\u6027 \u2192 \u901a\u8baf\u5f55':
      'macOS System Settings path (Contacts), not ours',
  // The Windows and GNOME contacts paragraphs (C05S4B7, C05S4B8) quote the
  // Windows Settings path and the GNOME Contacts app; both belong to the OS.
  '\u041f\u0430\u0440\u0430\u043c\u0435\u0442\u0440\u044b \u2192 \u041a\u043e\u043d\u0444\u0438\u0434\u0435\u043d\u0446\u0438\u0430\u043b\u044c\u043d\u043e\u0441\u0442\u044c \u0438 \u0437\u0430\u0449\u0438\u0442\u0430 \u2192 \u041a\u043e\u043d\u0442\u0430\u043a\u0442\u044b':
      'Windows Settings path (Contacts), not ours',
  '\u8bbe\u7f6e \u2192 \u9690\u79c1\u548c\u5b89\u5168\u6027 \u2192 \u8054\u7cfb\u4eba':
      'Windows Settings path (Contacts), not ours',
  '\u8054\u7cfb\u4eba': 'GNOME Contacts app name, not ours',
  // The overlay hide item (C02S3B2I5, #194): the tray entry reads
  // trayOverlayShowAgain, "<label> (hidden until {time})"; the handbook
  // quotes the fixed part, the time is only known at runtime.
  'Overlay wieder einblenden': 'tray item, see trayOverlayShowAgain ({time})',
  'Show overlay again': 'tray item, see trayOverlayShowAgain ({time})',
  'Mostrar de nuevo el overlay': 'tray item, see trayOverlayShowAgain ({time})',
  "R\u00e9afficher l'overlay": 'tray item, see trayOverlayShowAgain ({time})',
  "Mostra di nuovo l'overlay": 'tray item, see trayOverlayShowAgain ({time})',
  'Mostrar overlay novamente': 'tray item, see trayOverlayShowAgain ({time})',
  '\u0421\u043d\u043e\u0432\u0430 \u043f\u043e\u043a\u0430\u0437\u0430\u0442\u044c \u043e\u0432\u0435\u0440\u043b\u0435\u0439':
      'tray item, see trayOverlayShowAgain ({time})',
  '\u91cd\u65b0\u663e\u793a\u6d6e\u5c42':
      'tray item, see trayOverlayShowAgain ({time})',
  // Example position of the find bar (manualEditorFindB1); the UI string is
  // findReplaceMatchCount, "{current} of {total}".
  '3 von 12': 'example value of findReplaceMatchCount',
  '3 of 12': 'example value of findReplaceMatchCount',
  '3 de 12': 'example value of findReplaceMatchCount',
  '3 sur 12': 'example value of findReplaceMatchCount',
  '3 di 12': 'example value of findReplaceMatchCount',
  '3 \u0438\u0437 12': 'example value of findReplaceMatchCount',
  '3/12': 'example value of findReplaceMatchCount',
  // The back link after following an entry link (manualEditorLinksB1) is
  // entryLinkBack, "Back to {title}"; the handbook writes the title as "\u2026",
  // which _trim strips, leaving the fixed part with its trailing space.
  'Zur\u00fcck zu ': 'fixed part of entryLinkBack ({title})',
  'Back to ': 'fixed part of entryLinkBack ({title})',
  'Volver a ': 'fixed part of entryLinkBack ({title})',
  'Retour \u00e0 ': 'fixed part of entryLinkBack ({title})',
  'Torna a ': 'fixed part of entryLinkBack ({title})',
  'Voltar para ': 'fixed part of entryLinkBack ({title})',
  '\u041d\u0430\u0437\u0430\u0434 \u043a ':
      'fixed part of entryLinkBack ({title})',
  '\u8fd4\u56de\u5230 ': 'fixed part of entryLinkBack ({title})',
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

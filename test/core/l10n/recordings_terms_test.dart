import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The history area is labelled "Aufnahmen" / "Recordings" (navHistory,
/// CONTEXT.md §5.3a). Its visible follow-up texts must use that label instead
/// of the former "Verlauf" / "history". Keys below keep the old word on
/// purpose; each one is listed with its reason and must still contain it.
const _exceptions = <String, String>{
  'sidePanelClipboardHistoryTitle':
      'Clipboard history of the side panel (operating-system clipboard, not the area)',
  'settingsSidePanelEnabledSubtitle':
      'Mentions the clipboard history of the side panel, not the area',
  'manualC02S4B8':
      'Manual: names the clipboard history tab of the side panel, not the area',
  'hotkeyConflictNoteWindowsClipboardHistory':
      'Name of the Windows clipboard history (operating system, not the area)',
  'settingsSearchKeywordsHistory':
      'Search synonym: the old word keeps matching for users who type it',
};

/// Old domain term per locale. Stems keep inflections matching (Russian and
/// Hebrew genitive/possessive forms, Spanish/Portuguese "historial" vs
/// "histórico").
final _oldTerm = <String, RegExp>{
  'de': RegExp('verlauf', caseSensitive: false),
  'en': RegExp(r'\bhistory\b', caseSensitive: false),
  'es': RegExp('historial|hist[óo]ric', caseSensitive: false),
  'pt': RegExp('hist[óo]ric', caseSensitive: false),
  'ru': RegExp('истори', caseSensitive: false),
  'he': RegExp('היסטורי'),
};

void main() {
  for (final MapEntry(key: locale, value: oldTerm) in _oldTerm.entries) {
    test('area texts in app_$locale.arb use the nav label, not the old term', () {
      final arb =
          jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, Object?>;
      final violations = <String>[];
      for (final MapEntry(:key, :value) in arb.entries) {
        if (key.startsWith('@') || value is! String) continue;
        if (_exceptions.containsKey(key)) continue;
        if (oldTerm.hasMatch(value)) violations.add('$key: "$value"');
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Use the nav label (CONTEXT.md §5.3a) or add a reasoned exception:\n'
            '${violations.join('\n')}',
      );
    });

    test('exceptions in app_$locale.arb still contain the old term', () {
      final arb =
          jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, Object?>;
      for (final key in _exceptions.keys) {
        final value = arb[key];
        expect(
          value is String && oldTerm.hasMatch(value),
          isTrue,
          reason:
              '$key is an exception but no longer uses the old term; '
              'remove it from _exceptions',
        );
      }
    });
  }
}

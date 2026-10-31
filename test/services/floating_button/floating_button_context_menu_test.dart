/// AC3 (issue 08): the floating-button right-click context menu appears in the
/// UI language (DE/EN/HE) via L10n keys — no hard-coded English — with the same
/// actions and order as before. Also pins the action-id back-channel contract
/// (AC5) the service routes on.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/floating_button/floating_button_context_menu.dart';

List<Map<String, String>> _menu(Locale locale, {int historyCount = 0}) {
  final entries = List.generate(
    historyCount,
    (i) => (id: 'entry-$i', content: 'note $i'),
  );
  return buildFloatingButtonContextMenu(
    l10n: lookupL10n(locale),
    entries: entries,
  );
}

void main() {
  group('action-id back-channel contract (AC5)', () {
    test('action ids and order are stable and locale-independent', () {
      for (final locale in const [Locale('en'), Locale('de'), Locale('he')]) {
        final ids = _menu(locale).map((m) => m['id']).toList();
        expect(ids, [
          '__open__',
          '__new_recording__',
          '__history__',
          '__settings__',
          '__sep1__',
          '__quit__',
        ]);
      }
    });

    test('history entries become items keyed by their id, with separator', () {
      final menu = _menu(const Locale('en'), historyCount: 2);
      final ids = menu.map((m) => m['id']).toList();
      expect(ids, [
        '__open__',
        '__new_recording__',
        '__history__',
        '__settings__',
        '__sep1__',
        'entry-0',
        'entry-1',
        '__sep2__',
        '__quit__',
      ]);
    });

    test('long history labels are ellipsized to 50 chars', () {
      final long = 'x' * 80;
      final menu = buildFloatingButtonContextMenu(
        l10n: lookupL10n(const Locale('en')),
        entries: [(id: 'e', content: long)],
      );
      final item = menu.firstWhere((m) => m['id'] == 'e');
      expect(item['label']!.length, 50);
      expect(item['label'], endsWith('...'));
    });
  });

  group('labels are localized (AC3) — no hard-coded English', () {
    test('English labels', () {
      final menu = _menu(const Locale('en'));
      expect(_label(menu, '__open__'), 'Open WhisPaste');
      expect(_label(menu, '__new_recording__'), '⏺  Start Recording');
      expect(_label(menu, '__history__'), 'Show History');
      expect(_label(menu, '__settings__'), 'Settings');
      expect(_label(menu, '__quit__'), 'Quit WhisPaste');
    });

    test('German labels', () {
      final menu = _menu(const Locale('de'));
      expect(_label(menu, '__open__'), 'WhisPaste öffnen');
      expect(_label(menu, '__new_recording__'), '⏺  Aufnahme starten');
      expect(_label(menu, '__history__'), 'Verlauf anzeigen');
      expect(_label(menu, '__settings__'), 'Einstellungen');
      expect(_label(menu, '__quit__'), 'WhisPaste beenden');
    });

    test('Hebrew labels differ from English (real translation present)', () {
      final he = _menu(const Locale('he'));
      final en = _menu(const Locale('en'));
      for (final id in const [
        '__open__',
        '__history__',
        '__settings__',
        '__quit__',
      ]) {
        expect(_label(he, id), isNot(_label(en, id)));
      }
      expect(_label(he, '__settings__'), 'הגדרות');
    });
  });
}

String _label(List<Map<String, String>> menu, String id) =>
    menu.firstWhere((m) => m['id'] == id)['label']!;

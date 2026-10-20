// Every menu bar title exists in all six app languages and is not a copy of
// the English text in another language (MZ-04).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

const _locales = ['de', 'en', 'es', 'he', 'pt', 'ru'];

Map<String, dynamic> _arb(String code) =>
    jsonDecode(File('lib/core/l10n/app_$code.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final menuKeys = [
    for (final key in _arb('en').keys)
      if (key.startsWith('menuBar')) key,
  ];

  test('the menu bar has ARB keys', () {
    expect(menuKeys, isNotEmpty);
  });

  test('every menu bar key has a non-empty text in every language', () {
    for (final code in _locales) {
      final arb = _arb(code);
      for (final key in menuKeys) {
        expect(arb[key], isA<String>(), reason: 'app_$code.arb misses $key');
        expect(
          (arb[key] as String).trim(),
          isNotEmpty,
          reason: 'app_$code.arb has an empty $key',
        );
      }
    }
  });

  test('the generated titles follow the app language', () {
    for (final code in _locales) {
      final l10n = lookupL10n(Locale(code));
      final arb = _arb(code);
      expect(l10n.menuBarMenuEdit, arb['menuBarMenuEdit']);
      expect(l10n.menuBarEditSelectAll, arb['menuBarEditSelectAll']);
      expect(l10n.menuBarAppQuit, arb['menuBarAppQuit']);
    }
  });

  test('non-English titles are translated, not copied from English', () {
    final en = _arb('en');
    for (final code in ['de', 'es', 'he', 'pt', 'ru']) {
      final arb = _arb(code);
      for (final key in menuKeys) {
        if (key == 'menuBarAppQuit') continue; // contains the app name
        expect(
          arb[key],
          isNot(en[key]),
          reason: 'app_$code.arb repeats the English $key',
        );
      }
    }
  });
}

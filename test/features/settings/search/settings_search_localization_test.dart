/// Section-picker labels and search titles must read in every app UI language,
/// not only in German and English. Expected strings are the section headings
/// the page renders for each locale (the same ARB keys), so the picker never
/// drifts from them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_navigation.dart';

import '../../../fixtures/test_helpers.dart';
import 'settings_legacy_row_ids.dart';

/// The ARB value of [key] in [locale], read from the source file so the test
/// does not copy translations.
String _arb(String locale, String key) =>
    (jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
            as Map<String, dynamic>)[key]
        as String;

SettingsSearchEntry _entry(String rowId) =>
    kSettingsSearchTable.singleWhere((e) => e.rowId == rowId);

List<String> _keysFor(String query, String locale) => matchSettingsEntries(
  kSettingsSearchTable,
  query,
  locale,
).map((e) => e.rowId).toList();

void main() {
  group('SettingsSearchEntry localisation (ru, he)', () {
    test('every row title resolves to its ARB value in ru and he', () {
      for (final row in kSettingsSearchTable) {
        for (final locale in ['ru', 'he']) {
          expect(
            row.title(locale),
            _arb(locale, row.labelKey),
            reason: '${row.rowId} title in $locale',
          );
        }
      }
    });

    test('an unsupported language tag falls back to English', () {
      final english = _arb('en', _entry(legacyRowId('interface')).labelKey);
      expect(_entry(legacyRowId('interface')).title('fr'), english);
      expect(_entry(legacyRowId('interface')).title('en-US'), english);
    });
  });

  group('matchSettingsEntries matches the localised title', () {
    test('Russian title matches in ru', () {
      expect(_keysFor(_arb('ru', 'settingsSttEngine'), 'ru'), ['stt-model']);
    });

    test('Hebrew title matches in he', () {
      expect(
        _keysFor(_arb('he', 'settingsSttEngine'), 'he'),
        contains('stt-model'),
      );
    });

    test('English keywords still match in ru', () {
      expect(
        _keysFor('microphone', 'ru'),
        containsAnyOf(legacyRowIds('audio')),
      );
    });
  });

  group('Settings navigation in ru', () {
    testWidgets('the navigation shows Russian area labels, not English', (
      tester,
    ) async {
      // Wide enough for the side navigation (content width of at least 760).
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('ru'),
          size: const Size(1280, 800),
        ),
      );
      await tester.pumpAndSettle();

      final ruL10n = await L10n.delegate.load(const Locale('ru'));
      final nav = find.byType(SettingsNavigation);
      expect(nav, findsOneWidget);
      for (final label in [
        ruL10n.settingsAreaGeneral,
        ruL10n.settingsAreaSpeech,
        ruL10n.settingsAreaTextInsert,
      ]) {
        expect(
          find.descendant(of: nav, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('Speech recognition'), findsNothing);
    });
  });
}

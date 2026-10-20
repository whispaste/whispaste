/// Settings search as a jump (WP-23c): a suggestion switches the page to the
/// area that holds the row and highlights its section. The search no longer
/// filters the page, so the area you are in stays put while you type.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

import '../../../fixtures/test_helpers.dart';
import '../../../fixtures/record_device_listing_stub.dart';

late L10n l10n;

Finder _searchInput() => find.descendant(
  of: find.byType(SettingsSearchField),
  matching: find.byType(EditableText),
);

/// Title of the page header, i.e. the area currently shown.
String _pageTitle(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(WpPageHeader),
        matching: find.byType(Text),
      ),
    )
    .data!;

Future<void> _pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(
      const SettingsPage(),
      locale: const Locale('en'),
      size: const Size(1280, 800),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.tap(_searchInput());
  await tester.enterText(_searchInput(), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  stubRecordDeviceListing();
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Settings search jumps to the matching area', () {
    testWidgets('choosing a suggestion switches to the row’s area', (
      tester,
    ) async {
      await _pumpSettings(tester);
      expect(_pageTitle(tester), l10n.settingsAreaGeneral);

      await _search(tester, 'microphone');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_pageTitle(tester), l10n.settingsAreaRecording);
    });

    testWidgets('a match in another area jumps there, across area borders', (
      tester,
    ) async {
      await _pumpSettings(tester);

      // "dock" lives in the appearance card (panel and dock rows).
      await _search(tester, 'dock');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_pageTitle(tester), l10n.settingsAreaAppearance);
    });

    testWidgets('a hotkey search jumps to the keyboard shortcuts area', (
      tester,
    ) async {
      await _pumpSettings(tester);
      expect(_pageTitle(tester), l10n.settingsAreaGeneral);

      await _search(tester, 'global hotkey');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_pageTitle(tester), l10n.settingsAreaShortcuts);
    });

    testWidgets('typing alone does not filter or leave the current area', (
      tester,
    ) async {
      await _pumpSettings(tester);

      await _search(tester, 'microphone');

      expect(_pageTitle(tester), l10n.settingsAreaGeneral);
      expect(find.byType(WpPageHeader), findsOneWidget);
    });
  });
}

/// The "Keyboard shortcuts" settings area (maintainer decision 19a/20a,
/// 2026-10-19): every global hotkey row lives there, first in the dictation
/// group; General keeps only interface and updates; the Smart Mode section
/// links to the area with one compact row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

import '../../fixtures/test_helpers.dart';

/// Keys of the rows that must render in the shortcuts area.
const _shortcutRowKeys = [
  'settings-row-general-hotkey-dictation',
  'settings-row-general-hotkey-combo',
  'settings-row-general-hold-to-record',
  'settings-row-general-hold-or-tap',
  'settings-row-general-hotkey-quick-note',
  'settings-row-general-hotkey-snippet-picker',
  'settings-row-general-hotkey-smart-mode',
  'settings-row-general-hotkey-smart-mode-preset',
  'settings-row-general-hotkey-smart-mode-combination',
  'settings-row-general-hotkey-selection-edit',
];

class _FixedArea extends SettingsAreaNotifier {
  _FixedArea(this._area);

  final SettingsArea _area;

  @override
  SettingsArea build() => _area;
}

Future<void> _pumpArea(WidgetTester tester, SettingsArea area) async {
  await tester.pumpWidget(
    makeTestable(
      const SettingsPage(),
      locale: const Locale('en'),
      size: const Size(1280, 800),
      overrides: [settingsAreaProvider.overrideWith(() => _FixedArea(area))],
    ),
  );
  await tester.pumpAndSettle();
}

String _pageTitle(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(WpPageHeader),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  late L10n en;

  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  test('shortcuts is the first area of the dictation group', () {
    expect(
      settingsAreasIn(SettingsGroup.dictation).first,
      SettingsArea.shortcuts,
    );
  });

  test('General keeps only interface and updates', () {
    expect(kSettingsAreaSections[SettingsArea.general], [
      'interface',
      'updates',
    ]);
    expect(kSettingsAreaSections[SettingsArea.shortcuts], ['hotkey']);
  });

  testWidgets('General no longer renders the hotkey rows', (tester) async {
    await _pumpArea(tester, SettingsArea.general);

    expect(_pageTitle(tester), en.settingsAreaGeneral);
    expect(
      find.byKey(const ValueKey('settings-row-general-hotkey-dictation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-row-general-hotkey-selection-edit')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-row-general-updates-auto')),
      findsOneWidget,
    );
  });

  testWidgets('the shortcuts area renders every global hotkey row', (
    tester,
  ) async {
    await _pumpArea(tester, SettingsArea.shortcuts);

    expect(_pageTitle(tester), en.settingsAreaShortcuts);
    for (final key in _shortcutRowKeys) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('the Smart Mode section links to the shortcuts area', (
    tester,
  ) async {
    await _pumpArea(tester, SettingsArea.textInsert);
    expect(_pageTitle(tester), en.settingsAreaTextInsert);

    final link = find.byKey(const Key('smartModeShortcutChange'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(_pageTitle(tester), en.settingsAreaShortcuts);
    expect(
      find.byKey(const ValueKey('settings-row-general-hotkey-smart-mode')),
      findsOneWidget,
    );
  });
}

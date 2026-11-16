/// The "Keyboard shortcuts" settings area (maintainer decision 19a/20a,
/// 2026-10-19): every global hotkey row lives there, first in the dictation
/// group; General keeps only interface and updates; the Smart Mode section
/// links to the area with one compact row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/smart_mode/smart_mode_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/deploy_channel_service.dart';

import '../../fixtures/test_helpers.dart';

/// Keys of the rows that must render in the shortcuts area with default
/// settings. The Smart Mode combination row is folded away while its hotkey
/// is off (the default), so it is checked separately.
const _shortcutRowKeys = [
  'settings-row-general-hotkey-dictation',
  'settings-row-general-hotkey-combo',
  'settings-row-general-hold-to-record',
  'settings-row-general-double-tap',
  'settings-row-general-hotkey-quick-note',
  'settings-row-general-hotkey-snippet-picker',
  'settings-row-general-hotkey-smart-mode',
  'settings-row-general-hotkey-smart-mode-preset',
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

SettingsArea _currentArea(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(SettingsPage)),
).read(settingsAreaProvider);

void main() {
  // A Homebrew cask on the host makes detectDeployChannel() report a package
  // manager, which hides the update rows General still shows (same pin as
  // settings_search_areas_test.dart).
  setUpAll(() => deployChannelOverride = DeployChannel.portable);
  tearDownAll(() => deployChannelOverride = null);
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

    expect(_currentArea(tester), SettingsArea.general);
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

    expect(_currentArea(tester), SettingsArea.shortcuts);
    for (final key in _shortcutRowKeys) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(
      find.byKey(
        const ValueKey('settings-row-general-hotkey-smart-mode-combination'),
      ),
      findsNothing,
    );
  });

  testWidgets('the Smart Mode page links to the shortcuts area', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const SmartModePage(),
        locale: const Locale('en'),
        size: const Size(1280, 800),
      ),
    );
    await tester.pumpAndSettle();

    final link = find.byKey(const Key('smartModeShortcutChange'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    // The link hands the hotkey row over to the Settings page, which then
    // switches to the shortcuts area (jump logic: settings_search_areas_test).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SmartModePage)),
    );
    expect(container.read(activePageProvider), 'settings');
    expect(
      container.read(settingsScrollTargetProvider),
      'general-hotkey-smart-mode',
    );
  });
}

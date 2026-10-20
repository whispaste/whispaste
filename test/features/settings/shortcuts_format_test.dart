// UIA-KBD-02: one format for every hotkey row, three purpose cards, no
// "global" in any visible title, dependent options indented.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';

import '../../fixtures/record_device_listing_stub.dart';
import '../../fixtures/test_helpers.dart';

Future<void> _pump(WidgetTester tester, {String locale = 'en'}) async {
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: KeyboardShortcutSection()),
      locale: Locale(locale),
      overrides: [snippetPickerAvailabilityProvider.overrideWithValue(true)],
    ),
  );
  await tester.pumpAndSettle();
}

late L10n l10n;

void main() {
  stubRecordDeviceListing();
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('the hotkeys sit in three purpose cards', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('settings-group-card')), findsNWidgets(3));
    expect(find.text('Dictate'), findsOneWidget);
    expect(find.text('Notes & snippets'), findsOneWidget);
    expect(find.text('Smart Mode & edit selection'), findsOneWidget);
  });

  testWidgets('no visible text calls a hotkey "global" (en and de)', (
    tester,
  ) async {
    for (final locale in ['en', 'de']) {
      await _pump(tester, locale: locale);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => RegExp('global', caseSensitive: false).hasMatch(s))
          .toList();
      expect(texts, isEmpty, reason: 'locale $locale');
    }
  });

  testWidgets('every hotkey is one block: switch, then combination with its '
      'Change button below it', (tester) async {
    await _pump(tester);
    const blocks = [
      'shortcutBlock-dictation',
      'shortcutBlock-quickNote',
      'shortcutBlock-snippetPicker',
      'shortcutBlock-smartMode',
      'shortcutBlock-selectionEdit',
    ];
    for (final block in blocks) {
      final finder = find.byKey(ValueKey(block));
      expect(finder, findsOneWidget, reason: block);
      final switchRect = tester.getRect(
        find.descendant(of: finder, matching: find.byType(Switch)).first,
      );
      final buttonRect = tester.getRect(
        find
            .descendant(
              of: finder,
              matching: find.text(l10n.settingsChangeHotkey),
            )
            .first,
      );
      expect(
        buttonRect.top,
        greaterThanOrEqualTo(switchRect.bottom - 1),
        reason: '$block: Change button must sit below its switch',
      );
    }
  });

  testWidgets('dependent options are indented under their hotkey', (
    tester,
  ) async {
    await _pump(tester);
    double x(String text) => tester.getTopLeft(find.text(text)).dx;

    expect(
      x(l10n.settingsHoldOrTap),
      greaterThan(x(l10n.settingsHoldToRecord)),
      reason: 'hold-or-tap belongs to push-to-talk',
    );
    expect(
      x(l10n.settingsQuickNoteOpenInMainWindow),
      greaterThan(x(l10n.settingsQuickNoteHotkeyEnabled)),
      reason: 'open-in-main-window belongs to the quick note',
    );
    expect(
      x(l10n.settingsSmartModeHotkeyPreset),
      greaterThan(x(l10n.settingsSmartModeHotkeyEnabled)),
      reason: 'preset belongs to the Smart Mode hotkey',
    );
  });

  testWidgets('hold-or-tap is dimmed and inert while push-to-talk is off', (
    tester,
  ) async {
    await _pump(tester);
    final opacities = tester
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.text(l10n.settingsHoldOrTap),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .map((w) => w.opacity);
    expect(
      opacities.any((o) => o < 1),
      isTrue,
      reason:
          'a disabled dependent option must look disabled, like the '
          'Smart Mode preset under its switched-off hotkey',
    );
  });
}

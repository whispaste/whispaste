/// Live conflict check of the hotkey recorder: a combination that another
/// WhisPaste action already holds is named while it is recorded, and Save stays
/// disabled until the user picks a free one.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../fixtures/test_helpers.dart';

/// Records Ctrl+Shift+R, as the user would press it.
Future<void> _pressCtrlShiftR(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
  await tester.pumpAndSettle();
}

void main() {
  group('WpHotkeyRecorderDialog holder check', () {
    testWidgets('a held combination is named and Save is disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpHotkeyRecorderDialog(
            initialKey: 'R',
            initialModifiers: 'ctrl+shift',
            holderOf: (modifiers, key) => 'Snippets',
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();
      // The holder is named once a combination is recorded (38695f76f).
      await _pressCtrlShiftR(tester);

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);
      expect(
        find.text(l10n.settingsDictationHotkeyCollision('Snippets')),
        findsOneWidget,
      );
      final save = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('a free combination shows no holder and Save is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpHotkeyRecorderDialog(
            initialKey: 'R',
            initialModifiers: 'ctrl+shift',
            holderOf: (modifiers, key) => null,
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();
      await _pressCtrlShiftR(tester);

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);
      expect(find.textContaining('already used'), findsNothing);
      final save = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets('recording a held combination keeps Save disabled', (
      tester,
    ) async {
      final submitted = <WpHotkeyResult>[];
      await tester.pumpWidget(
        makeTestable(
          WpHotkeyRecorderDialog(
            initialKey: 'R',
            initialModifiers: 'ctrl+shift',
            holderOf: (modifiers, key) => key == 'F5' ? 'Quick note' : null,
            onSubmit: submitted.add,
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);
      expect(
        find.text(l10n.settingsDictationHotkeyCollision('Quick note')),
        findsOneWidget,
      );
      final save = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
      );
      expect(save.onPressed, isNull);
      expect(submitted, isEmpty);
    });
  });
}

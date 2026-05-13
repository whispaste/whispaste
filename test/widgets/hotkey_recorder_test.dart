import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('HotkeyRecorderDialog', () {
    testWidgets('renders modifier hint text', (tester) async {
      await tester.pumpWidget(
        makeTestable(const HotkeyRecorderDialog(), size: const Size(800, 600)),
      );
      await tester.pump();

      // The l10n key settingsHotkeyRecorderModifierHint must be visible.
      // We match a substring that is stable in both locales.
      expect(find.textContaining('Alt'), findsWidgets);
    });

    testWidgets('modifier hint is present in the widget tree', (tester) async {
      await tester.pumpWidget(
        makeTestable(const HotkeyRecorderDialog(), size: const Size(800, 600)),
      );
      await tester.pump();

      final context = tester.element(find.byType(HotkeyRecorderDialog));
      final l10n = L10n.of(context);

      expect(
        find.text(l10n.settingsHotkeyRecorderModifierHint),
        findsOneWidget,
      );
    });

    testWidgets('displays initial key combo from parameters', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(
            initialKey: 'R',
            initialModifiers: 'ctrl+shift',
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      // Initial key label visible as key cap
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('clear button resets the combo display', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(
            initialKey: 'D',
            initialModifiers: 'ctrl+shift',
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(HotkeyRecorderDialog));
      final l10n = L10n.of(context);

      // Tap clear
      await tester.tap(find.text(l10n.settingsHotkeyRecorderClear));
      await tester.pump();

      // After clear the placeholder '—' should appear
      expect(find.text('—'), findsOneWidget);
    });
  });
}

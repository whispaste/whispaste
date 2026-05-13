import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

import '../fixtures/test_helpers.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Unit tests — singleKeyWhitelist content
  // ---------------------------------------------------------------------------

  group('singleKeyWhitelist', () {
    test('contains all F1–F12 function keys', () {
      final fKeys = [
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7,
        LogicalKeyboardKey.f8,
        LogicalKeyboardKey.f9,
        LogicalKeyboardKey.f10,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.f12,
      ];
      for (final key in fKeys) {
        expect(
          singleKeyWhitelist.contains(key),
          isTrue,
          reason: '${key.debugName} should be whitelisted',
        );
      }
    });

    test('contains the required media keys', () {
      expect(
        singleKeyWhitelist.contains(LogicalKeyboardKey.mediaPlayPause),
        isTrue,
      );
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.mediaStop), isTrue);
      expect(
        singleKeyWhitelist.contains(LogicalKeyboardKey.audioVolumeMute),
        isTrue,
      );
    });

    test('does not contain letter keys', () {
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.keyA), isFalse);
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.keyZ), isFalse);
    });

    test('does not contain digit keys', () {
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.digit1), isFalse);
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.digit0), isFalse);
    });

    test('does not contain navigation or editing keys', () {
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.space), isFalse);
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.enter), isFalse);
      expect(
        singleKeyWhitelist.contains(LogicalKeyboardKey.backspace),
        isFalse,
      );
      expect(singleKeyWhitelist.contains(LogicalKeyboardKey.escape), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — key recording behaviour
  // ---------------------------------------------------------------------------

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

    // ── Whitelist key recording ──────────────────────────────────────────

    testWidgets('whitelisted F-key (F5) is recorded without any modifier', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      // Simulate F5 key down (no modifiers held).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
      await tester.pump();

      // 'F5' label should now be visible as a key cap.
      expect(find.text('F5'), findsOneWidget);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.pump();
    });

    testWidgets('non-whitelisted letter key is ignored without modifier', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      // Simulate pressing 'A' with no modifiers.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      // Placeholder should still be visible — 'A' must not be recorded.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('A'), findsNothing);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
    });

    testWidgets(
      'non-whitelisted key is recorded when combined with a modifier',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const HotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        // Hold Ctrl, then press 'A'.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.pump();

        // 'A' should now be recorded.
        expect(find.text('A'), findsOneWidget);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets(
      'initial whitelisted single-key combo enables Save immediately',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const HotkeyRecorderDialog(initialKey: 'F5', initialModifiers: ''),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(HotkeyRecorderDialog));
        final l10n = L10n.of(context);

        // Save button must be enabled (onPressed != null).
        final saveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, l10n.settingsHotkeyRecorderSave),
        );
        expect(saveButton.onPressed, isNotNull);
      },
    );
  });
}

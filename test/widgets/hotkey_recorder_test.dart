import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';
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

    // ── Conflict warning ────────────────────────────────────────────────

    testWidgets('conflict warning is NOT shown when no conflict exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(
            // ctrl+shift+D is not a known system conflict on any platform.
            initialKey: 'D',
            initialModifiers: 'ctrl+shift',
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('hotkeyConflictWarning')), findsNothing);
    });

    testWidgets(
      'conflict warning is shown for a known system shortcut via findConflict',
      (tester) async {
        // Use findConflict with a known fixture to verify widget-level display.
        // We build a dialog whose initial combo is set to a combo that IS in
        // the fixture list, then verify the warning container appears.
        //
        // On any platform, we pick a combo that matches the *platform* list.
        // Since the test runner may be macOS, Windows, or Linux, we pick
        // meta+L which is a conflict on ALL three lists.
        final platformList = platformConflicts;
        final hasMetaL = platformList.any(
          (e) => e.modifiers == 'meta' && e.key == 'L',
        );

        if (!hasMetaL) {
          // Guard: only assert when the platform actually has this conflict.
          return;
        }

        await tester.pumpWidget(
          makeTestable(
            const HotkeyRecorderDialog(
              initialKey: 'L',
              initialModifiers: 'meta',
            ),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('hotkeyConflictWarning')),
          findsOneWidget,
          reason:
              'Warning container must be visible for a known system conflict',
        );
      },
    );

    testWidgets('save button remains enabled when conflict warning is shown', (
      tester,
    ) async {
      final platformList = platformConflicts;
      final hasMetaL = platformList.any(
        (e) => e.modifiers == 'meta' && e.key == 'L',
      );

      if (!hasMetaL) return;

      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(initialKey: 'L', initialModifiers: 'meta'),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(HotkeyRecorderDialog));
      final l10n = L10n.of(context);

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, l10n.settingsHotkeyRecorderSave),
      );
      expect(
        saveButton.onPressed,
        isNotNull,
        reason: 'Save must remain enabled even when a conflict warning shows',
      );
    });

    // ── Save returns storage-format modifiers, NOT localized display labels ──
    //
    // Regression for the cross-platform modifier serialization bug: the
    // recorder must persist canonical storage tokens (`alt`, `ctrl`, `shift`,
    // `meta`), never the user-facing display strings (`Option`, `Strg`,
    // `Umschalt`, `Befehl`). Otherwise the global hotkey registrar drops the
    // modifier on read and the user's hotkey silently fires without it.

    Future<HotkeyResult?> openRecorderAndCapture(
      WidgetTester tester, {
      required List<LogicalKeyboardKey> keys,
      Locale? locale,
    }) async {
      HotkeyResult? captured;

      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (ctx) => ElevatedButton(
              key: const Key('open-recorder'),
              onPressed: () async {
                captured = await HotkeyRecorderDialog.show(ctx);
              },
              child: const Text('open'),
            ),
          ),
          locale: locale,
          size: const Size(1280, 800),
        ),
      );

      await tester.tap(find.byKey(const Key('open-recorder')));
      await tester.pumpAndSettle();

      for (final k in keys) {
        await tester.sendKeyDownEvent(k);
        await tester.pump();
      }

      final context = tester.element(find.byType(HotkeyRecorderDialog));
      final l10n = L10n.of(context);
      await tester.tap(
        find.widgetWithText(ElevatedButton, l10n.settingsHotkeyRecorderSave),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      for (final k in keys.reversed) {
        await tester.sendKeyUpEvent(k);
      }
      await tester.pump();

      return captured;
    }

    testWidgets(
      'reporter case: Alt + ArrowLeft → modifiers="alt", key="←" (NOT "option")',
      (tester) async {
        final result = await openRecorderAndCapture(
          tester,
          keys: [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft],
        );

        expect(result, isNotNull);
        expect(result!.key, '←');
        expect(
          result.modifiers,
          'alt',
          reason:
              'Storage MUST be canonical token "alt", not the macOS display '
              'label "option" — otherwise the resolver drops the modifier.',
        );
      },
    );

    testWidgets('Meta+Shift+D → canonical "shift+meta" (not "shift+cmd")', (
      tester,
    ) async {
      final result = await openRecorderAndCapture(
        tester,
        keys: [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.keyD,
        ],
      );

      expect(result, isNotNull);
      expect(result!.key, 'D');
      expect(
        result.modifiers,
        'shift+meta',
        reason: 'serializeModifiers canonical order is ctrl-shift-alt-meta',
      );
    });

    testWidgets('Ctrl+Alt+D → canonical "ctrl+alt" (cross-platform)', (
      tester,
    ) async {
      final result = await openRecorderAndCapture(
        tester,
        keys: [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.keyD,
        ],
      );

      expect(result, isNotNull);
      expect(result!.modifiers, 'ctrl+alt');
    });

    testWidgets(
      'DE locale: Strg+Umschalt+E still stores canonical "ctrl+shift"',
      (tester) async {
        // E avoids the system-shortcut conflict warning, which would render
        // a long localized banner that overflows the 420 px-wide dialog and
        // pushes the Save button off the hit-test area.
        final result = await openRecorderAndCapture(
          tester,
          locale: const Locale('de'),
          keys: [
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.keyE,
          ],
        );

        expect(result, isNotNull);
        expect(
          result!.modifiers,
          'ctrl+shift',
          reason:
              'German locale must NOT leak display labels (strg/umschalt) into '
              'storage; canonical tokens are language-agnostic.',
        );
      },
    );

    testWidgets(
      'HE locale: Alt+D → modifiers="alt" (storage is locale-independent)',
      (tester) async {
        final result = await openRecorderAndCapture(
          tester,
          locale: const Locale('he'),
          keys: [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyD],
        );

        expect(result, isNotNull);
        expect(result!.modifiers, 'alt');
      },
    );

    testWidgets(
      'whitelisted single key (F5) → modifiers="" (empty), key="F5"',
      (tester) async {
        final result = await openRecorderAndCapture(
          tester,
          keys: [LogicalKeyboardKey.f5],
        );

        expect(result, isNotNull);
        expect(result!.key, 'F5');
        expect(result.modifiers, '');
      },
    );

    // ── Filter: non-recordable keys are rejected ────────────────────────

    testWidgets(
      'AC-rec-1: Ctrl + non-recordable key leaves _keyLabel unchanged '
      'and shows invalid-key hint',
      (tester) async {
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

        // Hold Ctrl, press Ö (Unicode 0xF6) — must NOT replace the initial
        // key label and the invalid-key hint must appear.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.semicolon);
        await tester.pump();

        // Initial key 'D' is still rendered as a key cap.
        expect(
          find.text('D'),
          findsOneWidget,
          reason: 'non-recordable key must not overwrite the initial label',
        );
        // Hint message is visible.
        expect(
          find.text(l10n.settingsHotkeyRecorderInvalidKey),
          findsOneWidget,
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.semicolon);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets('AC-rec-2: Ctrl + digit5 is recorded (digits are recordable)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
      await tester.pump();

      // '5' should now be rendered as a key cap.
      expect(find.text('5'), findsOneWidget);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    });

    testWidgets(
      'AC-rec-3: invalid-key hint disappears after a valid key is recorded',
      (tester) async {
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

        // Trigger hint with non-recordable key.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.semicolon);
        await tester.pump();
        expect(
          find.text(l10n.settingsHotkeyRecorderInvalidKey),
          findsOneWidget,
        );

        // Now press a valid key — hint should clear.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
        await tester.pump();
        expect(find.text(l10n.settingsHotkeyRecorderInvalidKey), findsNothing);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.semicolon);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets('AC-rec-4: invalid-key hint disappears after 2 seconds', (
      tester,
    ) async {
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

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.semicolon);
      await tester.pump();

      expect(find.text(l10n.settingsHotkeyRecorderInvalidKey), findsOneWidget);

      // Advance past the 2-second auto-hide window.
      await tester.pump(const Duration(milliseconds: 2100));

      expect(find.text(l10n.settingsHotkeyRecorderInvalidKey), findsNothing);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.semicolon);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    });

    testWidgets(
      'AC-rec-5: Save stays disabled while only non-recordable keys were pressed',
      (tester) async {
        // Start with an empty initial combo so Save begins disabled.
        await tester.pumpWidget(
          makeTestable(
            const HotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(HotkeyRecorderDialog));
        final l10n = L10n.of(context);

        // Press Ctrl+Ö — non-recordable key.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.semicolon);
        await tester.pump();

        final saveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, l10n.settingsHotkeyRecorderSave),
        );
        expect(
          saveButton.onPressed,
          isNull,
          reason:
              'Save must stay disabled until a recordable key has been entered',
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.semicolon);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets('conflict warning disappears after clear is pressed', (
      tester,
    ) async {
      final platformList = platformConflicts;
      final hasMetaL = platformList.any(
        (e) => e.modifiers == 'meta' && e.key == 'L',
      );

      if (!hasMetaL) return;

      await tester.pumpWidget(
        makeTestable(
          const HotkeyRecorderDialog(initialKey: 'L', initialModifiers: 'meta'),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      // Verify warning is visible first.
      expect(find.byKey(const Key('hotkeyConflictWarning')), findsOneWidget);

      final context = tester.element(find.byType(HotkeyRecorderDialog));
      final l10n = L10n.of(context);

      // Tap Clear.
      await tester.tap(find.text(l10n.settingsHotkeyRecorderClear));
      await tester.pump();

      // Warning must be gone after clearing.
      expect(find.byKey(const Key('hotkeyConflictWarning')), findsNothing);
    });
  });
}

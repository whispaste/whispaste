import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';
import 'package:whispaste/widgets/wp_button.dart';

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

  group('WpHotkeyRecorderDialog', () {
    testWidgets('displays initial key combo from parameters', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpHotkeyRecorderDialog(
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
          const WpHotkeyRecorderDialog(
            initialKey: 'D',
            initialModifiers: 'ctrl+shift',
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);

      // Tap clear
      await tester.tap(find.text(l10n.settingsHotkeyRecorderClear));
      await tester.pump();

      // After clear the field waits for keys again.
      expect(
        find.byKey(const ValueKey('hotkey-recorder-listening')),
        findsOneWidget,
      );
    });

    testWidgets('inline mode: Escape discards the recorded combo and restores '
        'the initial one without submitting (UIA-ONB-08)', (tester) async {
      final submitted = <WpHotkeyResult>[];
      await tester.pumpWidget(
        makeTestable(
          WpHotkeyRecorderDialog(
            initialKey: 'R',
            initialModifiers: 'ctrl+shift',
            onSubmit: submitted.add,
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(find.text('F5'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // "R" is back in the field and in the "current keys" row (38695f76f).
      expect(find.text('F5'), findsNothing);
      expect(find.text('R'), findsWidgets);
      expect(submitted, isEmpty);
      expect(tester.takeException(), isNull);
    });

    // ── Whitelist key recording ──────────────────────────────────────────

    testWidgets('whitelisted F-key (F5) is recorded without any modifier', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
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
          const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      // Simulate pressing 'A' with no modifiers.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      // The field still waits — 'A' must not be recorded.
      expect(
        find.byKey(const ValueKey('hotkey-recorder-listening')),
        findsOneWidget,
      );
      expect(find.text('A'), findsNothing);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
    });

    testWidgets(
      'non-whitelisted key is recorded when combined with a modifier',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
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

    testWidgets('Save enables once a whitelisted single key is pressed', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpHotkeyRecorderDialog(initialKey: 'F5', initialModifiers: ''),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);
      WpButton saveButton() => tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
      );

      // The field waits for a press: nothing recorded yet, nothing to save.
      expect(saveButton().onPressed, isNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(saveButton().onPressed, isNotNull);
    });

    // ── Conflict warning ────────────────────────────────────────────────

    testWidgets('conflict warning is NOT shown when no conflict exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpHotkeyRecorderDialog(
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

        // The warning is shown for a recorded combination (38695f76f): the
        // user presses Meta+L, which the platform reserves.
        await tester.pumpWidget(
          makeTestable(
            const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
        await tester.pumpAndSettle();

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
          const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);

      final saveButton = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
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

    Future<WpHotkeyResult?> openRecorderAndCapture(
      WidgetTester tester, {
      required List<LogicalKeyboardKey> keys,
      Locale? locale,
    }) async {
      WpHotkeyResult? captured;

      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (ctx) => ElevatedButton(
              key: const Key('open-recorder'),
              onPressed: () async {
                captured = await WpHotkeyRecorderDialog.show(ctx);
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

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);
      await tester.tap(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
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
      'Windows AltGr (RightAlt) → "altgr" token (registers as Ctrl+Alt) (#39)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          // Windows injects a synthetic LeftCtrl right before RightAlt for
          // AltGr. The recorder stores the distinct `altgr` token, which
          // resolves to Ctrl+Alt for registration (so the hotkey fires) and
          // displays as a localized "AltGr".
          final result = await openRecorderAndCapture(
            tester,
            keys: [
              LogicalKeyboardKey.controlLeft,
              LogicalKeyboardKey.altRight,
              LogicalKeyboardKey.keyD,
            ],
          );

          expect(result, isNotNull);
          expect(result!.key, 'D');
          expect(
            result.modifiers,
            'altgr',
            reason:
                'AltGr is stored as its own token so it survives a save and '
                'registers as Ctrl+Alt (not a non-firing plain Alt).',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'non-Windows: LeftCtrl+RightAlt stays "ctrl+alt" (AltGr guard is gated)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          // Linux AltGr injects no control key, so a held LeftCtrl+RightAlt is a
          // genuine combo and must survive — proving the guard is Windows-only.
          final result = await openRecorderAndCapture(
            tester,
            keys: [
              LogicalKeyboardKey.controlLeft,
              LogicalKeyboardKey.altRight,
              LogicalKeyboardKey.keyD,
            ],
          );

          expect(result, isNotNull);
          expect(result!.modifiers, 'ctrl+alt');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

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
            const WpHotkeyRecorderDialog(
              initialKey: 'D',
              initialModifiers: 'ctrl+shift',
            ),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(WpHotkeyRecorderDialog));
        final l10n = L10n.of(context);

        // Hold Ctrl, press a non-recordable key (numLock has a physical
        // mapping for KeyEventSimulator but is intentionally outside the
        // recordable whitelist — earlier this slot was held by semicolon,
        // which is now recordable as a US-layout punctuation token).
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.numLock);
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

        await tester.sendKeyUpEvent(LogicalKeyboardKey.numLock);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets('AC-rec-2: Ctrl + digit5 is recorded (digits are recordable)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
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
            const WpHotkeyRecorderDialog(
              initialKey: 'D',
              initialModifiers: 'ctrl+shift',
            ),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(WpHotkeyRecorderDialog));
        final l10n = L10n.of(context);

        // Trigger hint with a key that has a physical mapping but is not
        // recordable (numLock has a physical mapping for KeyEventSimulator
        // but is intentionally outside the recordable set).
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.numLock);
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
        await tester.sendKeyUpEvent(LogicalKeyboardKey.numLock);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets(
      'AC-rec-4: invalid-key hint persists until a valid key is pressed',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpHotkeyRecorderDialog(
              initialKey: 'D',
              initialModifiers: 'ctrl+shift',
            ),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(WpHotkeyRecorderDialog));
        final l10n = L10n.of(context);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.numLock);
        await tester.pump();

        expect(
          find.text(l10n.settingsHotkeyRecorderInvalidKey),
          findsOneWidget,
        );

        // Time alone must not clear the hint — the earlier auto-hide was too
        // short to read. Hint stays until a valid key replaces it.
        await tester.pump(const Duration(milliseconds: 2100));

        expect(
          find.text(l10n.settingsHotkeyRecorderInvalidKey),
          findsOneWidget,
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.numLock);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets(
      'AC-rec-5: Save stays disabled while only non-recordable keys were pressed',
      (tester) async {
        // Start with an empty initial combo so Save begins disabled.
        await tester.pumpWidget(
          makeTestable(
            const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(WpHotkeyRecorderDialog));
        final l10n = L10n.of(context);

        // Press Ctrl+numLock — a key with a physical mapping that is
        // intentionally outside the recordable whitelist.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.numLock);
        await tester.pump();

        final saveButton = tester.widget<WpButton>(
          find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
        );
        expect(
          saveButton.onPressed,
          isNull,
          reason:
              'Save must stay disabled until a recordable key has been entered',
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.numLock);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    // ── Phase B: punctuation + physical-key fallback ─────────────────────

    Future<WpHotkeyResult?> openAndCapture(
      WidgetTester tester, {
      required Future<void> Function() driveKeys,
      String initialKey = '',
      String initialDisplayKey = '',
      String initialModifiers = '',
    }) async {
      WpHotkeyResult? captured;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (ctx) => ElevatedButton(
              key: const Key('open-recorder-pb'),
              onPressed: () async {
                captured = await WpHotkeyRecorderDialog.show(
                  ctx,
                  initialKey: initialKey,
                  initialDisplayKey: initialDisplayKey,
                  initialModifiers: initialModifiers,
                );
              },
              child: const Text('open'),
            ),
          ),
          size: const Size(1280, 800),
        ),
      );

      await tester.tap(find.byKey(const Key('open-recorder-pb')));
      await tester.pumpAndSettle();

      await driveKeys();

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);
      await tester.tap(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      return captured;
    }

    testWidgets(
      'AC-pb-1: Ctrl+semicolon (US-layout) saves canonical ";" without '
      'displayKey override',
      (tester) async {
        final result = await openAndCapture(
          tester,
          driveKeys: () async {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.pump();
            await tester.sendKeyDownEvent(LogicalKeyboardKey.semicolon);
            await tester.pump();
            await tester.sendKeyUpEvent(LogicalKeyboardKey.semicolon);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            await tester.pump();
          },
        );

        expect(result, isNotNull);
        expect(result!.key, ';');
        expect(result.modifiers, 'ctrl');
        expect(
          result.displayKey,
          '',
          reason: 'canonical match leaves displayKey empty',
        );
      },
    );

    testWidgets(
      'AC-pb-1b: Ctrl+backslash on Windows corrects to the key the live '
      'layout actually registers (#108 — German driver assigns the '
      'physical "#" key to VK_OEM_2, not VK_OEM_5)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        const channel = MethodChannel('com.whispaste.keyboard_monitor');
        try {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (call) async {
              final args = call.arguments as Map;
              switch (call.method) {
                case 'resolveLiveVirtualKey':
                  // The physical key at scan code 0x2B (Flutter's `backslash`
                  // position) is VK_OEM_2 under the German layout — not
                  // VK_OEM_5, which is what hotkey_manager's static US-based
                  // conversion would register for that physical position.
                  return args['scanCode'] == 0x2B ? 0xBF : 0;
                case 'resolveLayoutLabel':
                  return args['vk'] == 0xBF ? '#' : '';
                default:
                  return null;
              }
            },
          );

          final result = await openAndCapture(
            tester,
            driveKeys: () async {
              await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
              await tester.pump();
              await tester.sendKeyDownEvent(LogicalKeyboardKey.backslash);
              await tester.pump();
              // Let the async live-layout correction (chained platform-
              // channel round trips) resolve before the combo is released
              // and saved.
              await tester.pumpAndSettle();
              await tester.sendKeyUpEvent(LogicalKeyboardKey.backslash);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
              await tester.pump();
            },
          );

          expect(result, isNotNull);
          expect(
            result!.key,
            '/',
            reason:
                'Must store the physical key the German layout actually '
                'assigns VK_OEM_2 to (canonical "slash"), not the raw '
                '"backslash" position that was physically pressed — '
                'otherwise RegisterHotKey binds the wrong physical key.',
          );
          expect(result.displayKey, '#');
          expect(result.modifiers, 'ctrl');
        } finally {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    // AC-pb-2 (DE-layout Ö capture) is covered at the resolver level in
    // test/services/hotkey_key_resolver_test.dart — driving a KeyDownEvent
    // with a non-Flutter-known logicalKey from a widget test would require
    // injecting it through KeyEventManager APIs that vary between Flutter
    // versions, while the recorder's behaviour reduces to
    // [canonicalRecordableKey] + display-label derivation. Those two pieces
    // are unit-tested.

    testWidgets(
      'AC-pb-3: initState with a non-resolvable initialKey ("Ö") starts '
      'with Save disabled',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpHotkeyRecorderDialog(
              initialKey: 'Ö',
              initialModifiers: 'meta',
            ),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(WpHotkeyRecorderDialog));
        final l10n = L10n.of(context);
        final saveButton = tester.widget<WpButton>(
          find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
        );
        expect(
          saveButton.onPressed,
          isNull,
          reason:
              'unresolvable persisted key must not be accepted as a valid combo',
        );
      },
    );

    testWidgets(
      'AC-pb-4: initialDisplayKey "Ö" + initialKey ";" renders "Ö" in the '
      'key cap',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpHotkeyRecorderDialog(
              initialKey: ';',
              initialDisplayKey: 'Ö',
              initialModifiers: 'meta',
            ),
            size: const Size(800, 600),
          ),
        );
        await tester.pump();

        expect(find.text('Ö'), findsOneWidget);
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
          const WpHotkeyRecorderDialog(initialKey: '', initialModifiers: ''),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();

      // Verify warning is visible first.
      expect(find.byKey(const Key('hotkeyConflictWarning')), findsOneWidget);

      final context = tester.element(find.byType(WpHotkeyRecorderDialog));
      final l10n = L10n.of(context);

      // Tap Clear.
      await tester.tap(find.text(l10n.settingsHotkeyRecorderClear));
      await tester.pump();

      // Warning must be gone after clearing.
      expect(find.byKey(const Key('hotkeyConflictWarning')), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Intrinsic height at the card's own fixed width, not the offered width
  // ---------------------------------------------------------------------------
  //
  // The dialog always renders at a fixed 420-px card width regardless of how
  // much width it is offered. Before the fix, `getMaxIntrinsicHeight(width)`
  // answered with the *offered* width instead of clamping to the card's own
  // 420 px — at a 640-px offered width (the hotkey onboarding page's content
  // width) that under-measured the card's true height by 17 px, which let the
  // conflict branch clip invisibly (`RenderFlex` overflow without a scroll
  // affordance) at 800×621.

  // UX-084: Enter saves a recorded free combination, like the default button.
  // R14-2: Enter on a focused button of the card belongs to that button.
  const enterPlatforms = <(String, TargetPlatform)>[
    ('macOS', TargetPlatform.macOS),
    ('Windows', TargetPlatform.windows),
    ('Linux', TargetPlatform.linux),
  ];
  for (final (name, platform) in enterPlatforms) {
    group('Enter confirms (UX-084) on $name', () {
      testWidgets(
        'Enter saves a valid combination in inline mode',
        (tester) => _withPlatform(platform, () async {
          final submitted = <WpHotkeyResult>[];
          await tester.pumpWidget(
            makeTestable(
              WpHotkeyRecorderDialog(
                initialKey: 'D',
                initialModifiers: 'ctrl+shift',
                onSubmit: submitted.add,
              ),
              size: const Size(800, 600),
            ),
          );
          await tester.pump();

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();

          expect(submitted, hasLength(1));
          expect(submitted.single.key, 'D');
          expect(submitted.single.modifiers, 'ctrl+shift');
          expect(tester.takeException(), isNull);
        }),
      );

      testWidgets(
        'Enter does not save while another action holds the combo',
        (tester) => _withPlatform(platform, () async {
          final submitted = <WpHotkeyResult>[];
          await tester.pumpWidget(
            makeTestable(
              WpHotkeyRecorderDialog(
                initialKey: 'D',
                initialModifiers: 'ctrl+shift',
                onSubmit: submitted.add,
                holderOf: (_, _) => 'Schnellnotiz',
              ),
              size: const Size(800, 600),
            ),
          );
          await tester.pump();

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();

          expect(submitted, isEmpty);
          expect(tester.takeException(), isNull);
        }),
      );

      testWidgets(
        'Enter on a focused Clear button clears, never saves',
        (tester) => _withPlatform(platform, () async {
          final submitted = <WpHotkeyResult>[];
          await tester.pumpWidget(
            makeTestable(
              WpHotkeyRecorderDialog(
                initialKey: 'D',
                initialModifiers: 'ctrl+shift',
                onSubmit: submitted.add,
              ),
              size: const Size(800, 600),
            ),
          );
          await tester.pump();

          final clear = find.ancestor(
            of: find.text(
              lookupL10n(const Locale('en')).settingsHotkeyRecorderClear,
            ),
            matching: find.byType(WpButton),
          );
          for (var i = 0; i < 20 && !_focusWithin(tester, clear); i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(_focusWithin(tester, clear), isTrue);

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();

          expect(submitted, isEmpty, reason: 'Enter activates Clear only');
          expect(tester.takeException(), isNull);
        }),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // The dictation key: one recorder for a combination or a single key
  // ---------------------------------------------------------------------------

  group('single keys (dictation trigger)', () {
    /// Opens the recorder with [singleKeys], plays [events] (true = down,
    /// false = up) and taps Save. Returns what the dialog delivered.
    Future<WpHotkeyResult?> record(
      WidgetTester tester, {
      required Set<ModifierHotkey> singleKeys,
      required List<(LogicalKeyboardKey, bool)> events,
    }) async {
      WpHotkeyResult? captured;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (ctx) => ElevatedButton(
              key: const Key('open-recorder'),
              onPressed: () async {
                captured = await WpHotkeyRecorderDialog.show(
                  ctx,
                  singleKeys: singleKeys,
                );
              },
              child: const Text('open'),
            ),
          ),
          size: const Size(1280, 800),
        ),
      );
      await tester.tap(find.byKey(const Key('open-recorder')));
      await tester.pumpAndSettle();
      for (final (key, down) in events) {
        if (down) {
          await tester.sendKeyDownEvent(key);
        } else {
          await tester.sendKeyUpEvent(key);
        }
        await tester.pump();
      }
      final l10n = L10n.of(tester.element(find.byType(WpHotkeyRecorderDialog)));
      await tester.tap(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('a modifier pressed and let go alone is the single key, '
        'left and right apart', (tester) async {
      final result = await record(
        tester,
        singleKeys: ModifierHotkey.values.toSet(),
        events: [
          (LogicalKeyboardKey.metaRight, true),
          (LogicalKeyboardKey.metaRight, false),
        ],
      );
      expect(result?.singleKey, 'rightMeta');
      expect(result?.key, isEmpty);
      expect(result?.modifiers, isEmpty);
    });

    testWidgets('a modifier with a key is a combination, not a single key', (
      tester,
    ) async {
      final result = await record(
        tester,
        singleKeys: ModifierHotkey.values.toSet(),
        events: [
          (LogicalKeyboardKey.controlLeft, true),
          (LogicalKeyboardKey.keyK, true),
          (LogicalKeyboardKey.keyK, false),
          (LogicalKeyboardKey.controlLeft, false),
        ],
      );
      expect(result?.singleKey, isEmpty);
      expect(result?.modifiers, 'ctrl');
      expect(result?.key, 'K');
    });

    testWidgets('two modifiers released without a key record nothing', (
      tester,
    ) async {
      final result = await record(
        tester,
        singleKeys: ModifierHotkey.values.toSet(),
        events: [
          (LogicalKeyboardKey.shiftLeft, true),
          (LogicalKeyboardKey.metaLeft, true),
          (LogicalKeyboardKey.metaLeft, false),
          (LogicalKeyboardKey.shiftLeft, false),
        ],
      );
      // Save delivers the combination the dialog opened with (Shift+D
      // default), never one of the two modifiers alone.
      expect(result?.singleKey ?? '', isEmpty);
    });

    testWidgets('a single key this action cannot use is not saved', (
      tester,
    ) async {
      final result = await record(
        tester,
        singleKeys: const {},
        events: [
          (LogicalKeyboardKey.metaRight, true),
          (LogicalKeyboardKey.metaRight, false),
        ],
      );
      expect(result?.singleKey ?? '', isEmpty);
      expect(
        find.byKey(const ValueKey('hotkey-recorder-single-unsupported')),
        findsNothing, // the dialog closed with the opening combination
      );
    });

    testWidgets('without single keys a lone modifier records nothing', (
      tester,
    ) async {
      WpHotkeyResult? captured;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (ctx) => ElevatedButton(
              key: const Key('open-recorder'),
              onPressed: () async {
                captured = await WpHotkeyRecorderDialog.show(ctx);
              },
              child: const Text('open'),
            ),
          ),
          size: const Size(1280, 800),
        ),
      );
      await tester.tap(find.byKey(const Key('open-recorder')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaRight);
      await tester.pump();
      final l10n = L10n.of(tester.element(find.byType(WpHotkeyRecorderDialog)));
      // Nothing was recorded, so Save stays disabled and delivers nothing.
      final save = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
      );
      expect(save.onPressed, isNull);
      await tester.tap(
        find.widgetWithText(WpButton, l10n.settingsHotkeyRecorderSave),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(captured, isNull);
    });
  });
}

/// True when the primary focus sits inside the widget [target].
bool _focusWithin(WidgetTester tester, Finder target) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final root = tester.element(target);
  var found = false;
  focused.visitAncestorElements((element) {
    found = element == root;
    return !found;
  });
  return found;
}

/// Runs [body] with [platform] as the default target platform (AltGr and
/// platform branches read it). Reset in `finally`, inside the test body, so
/// the framework's invariant check sees it unset.
Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

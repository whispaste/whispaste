/// Tests for [ReplacementsPage].
///
/// Covers: sample data on empty DB, Add dialog, dialog validation,
/// Edit pre-fill, search filter, no-results state, enable/disable toggle,
/// hover → delete confirmation.
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_widgets.dart'
    show SettingRow;
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake settings notifier — captures updateSettings calls without touching
// SQLite (the real notifier reads/writes the DB).
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('ReplacementsPage', () {
    // -------------------------------------------------------------------------
    // 1. Sample data
    // -------------------------------------------------------------------------

    testWidgets('renders sample entries on first load (empty DB)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // ReplacementsNotifier auto-inserts three sample replacements when DB
      // is empty. Trigger phrases are rendered as chips (no surrounding
      // quotes).
      expect(find.text('mfg'), findsOneWidget);
      expect(find.text('lg'), findsOneWidget);
      expect(find.text('tel'), findsOneWidget);

      // Arrow icon present once per row
      expect(find.byIcon(LucideIcons.arrowRightLeft), findsNWidgets(3));
    });

    // -------------------------------------------------------------------------
    // 2. Add dialog
    // -------------------------------------------------------------------------

    testWidgets('Add button opens dialog with correct labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Tap the toolbar Add button (contains the plus icon)
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // Dialog title
      expect(find.text(l10n.replacementsNewShortcut), findsOneWidget);
      // Field labels
      expect(find.text(l10n.replacementsTriggerLabel), findsOneWidget);
      expect(find.text(l10n.replacementsReplacementLabel), findsOneWidget);
      // Hint text in dialog body — now supplied by WpFormDialogShell
      expect(find.text(l10n.replacementsDialogHint), findsOneWidget);
    });

    testWidgets('the dialog stays whole at a 2x system text size', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text(l10n.replacementsNewShortcut), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the dialog body scrolls instead of overflowing',
      );
    });

    testWidgets('save button is disabled while both fields are empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // When _isValid == false the dialog's save button has onPressed == null,
      // while the toolbar Add button always has one — so a single disabled
      // button in the tree can only be the dialog's.
      final buttons = tester.widgetList<WpButton>(find.byType(WpButton));
      expect(
        buttons.any((b) => b.onPressed == null),
        isTrue,
        reason: 'Dialog save button should be disabled with empty fields',
      );
    });

    testWidgets('adding a second trigger phrase saves both triggers', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // TextFields in tree order: [0] page search, [1] trigger, [2] replacement
      await tester.enterText(find.byType(TextField).at(1), 'omw');

      // Add a second trigger row
      await tester.tap(find.text(l10n.replacementsAddTrigger));
      await tester.pumpAndSettle();

      // Now: [1] trigger 1, [2] trigger 2, [3] replacement
      await tester.enterText(find.byType(TextField).at(2), 'otw');
      await tester.enterText(find.byType(TextField).at(3), 'on my way');
      await tester.pumpAndSettle();

      // Save via the dialog button (the toolbar Add button shares the same
      // label but is rendered earlier in the tree).
      await tester.tap(find.text(l10n.replacementsAdd).last);
      await tester.pumpAndSettle();

      // One new tile carrying both trigger chips (3 samples + 1 new).
      expect(find.text('omw'), findsOneWidget);
      expect(find.text('otw'), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowRightLeft), findsNWidgets(4));
    });

    testWidgets('the last remaining trigger cannot be removed', (tester) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // A single trigger row shows no remove button at all
      expect(find.byIcon(LucideIcons.x), findsNothing);

      // With two rows, both get a remove button
      await tester.tap(find.text(l10n.replacementsAddTrigger));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.x), findsNWidgets(2));

      // Removing one row hides the remove button on the survivor again
      await tester.tap(find.byIcon(LucideIcons.x).first);
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    // -------------------------------------------------------------------------
    // 3. Edit (click tile)
    // -------------------------------------------------------------------------

    testWidgets('tapping a tile opens edit dialog with pre-filled trigger', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Tap the mfg tile (via its trigger chip)
      await tester.tap(find.text('mfg'));
      await tester.pumpAndSettle();

      // Edit dialog title
      expect(find.text(l10n.replacementsEditShortcut), findsOneWidget);
      // Pre-filled trigger value visible inside the dialog text field
      expect(find.text('mfg'), findsWidgets);
    });

    // -------------------------------------------------------------------------
    // 4. Search filter
    // -------------------------------------------------------------------------

    testWidgets('search field filters visible replacements', (tester) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // All three visible initially
      expect(find.text('mfg'), findsOneWidget);
      expect(find.text('lg'), findsOneWidget);
      expect(find.text('tel'), findsOneWidget);

      // Search for "mfg" — only the mfg row should remain. The search field
      // itself also contains the text 'mfg', so expect two matches.
      await tester.enterText(find.byType(TextField).first, 'mfg');
      await tester.pumpAndSettle();

      expect(find.text('mfg'), findsNWidgets(2));
      expect(find.text('lg'), findsNothing);
      expect(find.text('tel'), findsNothing);
    });

    testWidgets('search with no match shows no-results empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'zzzznonexistent');
      await tester.pumpAndSettle();

      expect(find.text(l10n.replacementsNoMatches), findsOneWidget);
    });

    testWidgets('the no-results empty state clears the search', (tester) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'zzzznonexistent');
      await tester.pumpAndSettle();

      // The shared no-matches state offers the same action as Verlauf and
      // Notizen, worded through the generic l10n key.
      expect(find.text(l10n.actionClearSearch), findsOneWidget);

      await tester.tap(find.text(l10n.actionClearSearch));
      await tester.pumpAndSettle();

      // Both the query and the field's text are back to empty.
      expect(find.text(l10n.replacementsNoMatches), findsNothing);
      expect(find.text('zzzznonexistent'), findsNothing);
      expect(find.text('mfg'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 5. Enable / disable toggle
    // -------------------------------------------------------------------------

    testWidgets('toggle switch updates textReplacementsEnabled in provider', (
      tester,
    ) async {
      // BehaviorSettings defaults textReplacementsEnabled = false.
      // Override with true so the switch starts ON, then verify toggling to OFF.
      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWith(textReplacementsEnabled: true),
      );
      await tester.pumpWidget(
        makeTestable(
          const ReplacementsPage(),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Starts enabled — switch is ON and the header card says so in words.
      final switchOn = tester.widget<Switch>(find.byType(Switch));
      expect(switchOn.value, isTrue);
      expect(find.text(l10n.replacementsToggleLabel), findsOneWidget);
      expect(find.text(l10n.replacementsToggleEnabled), findsOneWidget);

      // Tap toggle to disable
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        notifier.state.value?.behavior.textReplacementsEnabled,
        isFalse,
        reason: 'Provider should reflect the new disabled state',
      );
    });

    testWidgets('the master switch is announced with a name and its state', (
      tester,
    ) async {
      // In the toolbar this switch was an unnamed node: measured on the
      // semantics tree it carried an empty label while its visible caption
      // merged into the page-level focus node, so a screen reader read
      // "switch, on" with nothing to say what it switches.
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            const ReplacementsPage(),
            overrides: [
              settingsProvider.overrideWith(
                () => _FakeSettingsNotifier(
                  AppSettings.defaults.copyWith(textReplacementsEnabled: true),
                ),
              ),
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSemantics(find.byType(SettingRow)),
          isSemantics(
            label: l10n.replacementsToggleLabel,
            hint: l10n.replacementsToggleEnabled,
            hasToggledState: true,
            isToggled: true,
          ),
        );
      } finally {
        handle.dispose();
      }
    });

    // -------------------------------------------------------------------------
    // 6. Delete via hover
    // -------------------------------------------------------------------------

    testWidgets('hover shows delete icon; tapping it opens confirm dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Simulate mouse hover over the "mfg" tile
      final mfgTile = find.text('mfg');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(mfgTile));
      await tester.pumpAndSettle();

      // Delete icon should appear on hover
      expect(find.byIcon(LucideIcons.trash2), findsOneWidget);

      // Tap delete
      await tester.tap(find.byIcon(LucideIcons.trash2));
      await tester.pumpAndSettle();

      // Confirm dialog should appear with the correct title
      expect(find.text(l10n.replacementsDeleteTitle), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 7. Keyboard
    // -------------------------------------------------------------------------

    testWidgets('Ctrl/Cmd+N opens the add dialog', (tester) async {
      // Notizen bound this from the start, its two sibling list screens did
      // not — so "create the next one without leaving the keyboard" only
      // paid off on one of the three. Now bound once on the shared shell.
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.replacementsNewShortcut), findsNothing);

      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.meta
          : LogicalKeyboardKey.control;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();

      expect(find.text(l10n.replacementsNewShortcut), findsOneWidget);
    });

    testWidgets('Delete on the focused row opens the delete confirmation', (
      tester,
    ) async {
      // Notizen deletes the focused row from the keyboard; its two siblings
      // could only do it by mouse. Same keys now, different consequence by
      // necessity: no trash exists here, so the confirmation is the undo.
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Tab lands on the first row (the search field and Add button come
      // first in traversal order, so walk past them).
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (find.byIcon(LucideIcons.trash2).evaluate().isNotEmpty) break;
      }
      expect(
        find.byIcon(LucideIcons.trash2),
        findsOneWidget,
        reason: 'the row reveals its delete action on focus, not just hover',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(find.text(l10n.replacementsDeleteTitle), findsOneWidget);
    });

    testWidgets('Backspace in the search field edits text, deletes nothing', (
      tester,
    ) async {
      // The row bindings are scoped to the row; the search field is a
      // sibling of it, not a descendant, so typing stays typing.
      await tester.pumpWidget(
        makeTestable(const ReplacementsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'mfgx');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(find.text(l10n.replacementsDeleteTitle), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'mfg',
      );
    });
  });
}

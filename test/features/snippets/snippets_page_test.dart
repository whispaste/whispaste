/// Tests for [SnippetsPage].
///
/// Covers: empty state, Add dialog, dialog validation, Edit pre-fill, search
/// filter, no-results state, hover → delete confirmation, telemetry category.
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/find_replace_bar.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// The page header renders the picker-trigger [TextField] ahead of the search
/// field wherever the Snippet-Picker exists at all — shifts every subsequent
/// `find.byType(TextField).at(N)` index by one relative to a platform without
/// a picker.
///
/// Read from the same availability answer the page reads
/// ([snippetPickerAvailableOnPlatform]) rather than from `Platform` directly:
/// a test that *injects* unavailability must not keep counting a field that
/// is no longer rendered.
final _fieldOffset = snippetPickerAvailableOnPlatform ? 1 : 0;

/// Sends the platform's "new item" chord — Cmd on macOS, Ctrl elsewhere,
/// exactly as `WpSearchableListPage` binds it.
Future<void> _pressNewItemChord(WidgetTester tester) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(modifier);
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('SnippetsPage', () {
    testWidgets('starts empty — no sample data is seeded', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsEmpty), findsOneWidget);
    });

    testWidgets('Add button opens dialog with correct labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
      expect(
        find.text(l10n.snippetsDialogHint),
        findsOneWidget,
        reason:
            'the explanatory subtitle comes from WpFormDialogShell — without '
            'it this dialog reads barer than its Replacements twin',
      );
      expect(find.text(l10n.snippetsTitleLabel), findsOneWidget);
      expect(find.text(l10n.snippetsBodyLabel), findsOneWidget);
    });

    testWidgets('the dialog carries the editor toolbar, find bar included', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      expect(
        find.byType(WpMarkdownToolbar),
        findsOneWidget,
        reason:
            'a snippet body is written prose like a note or a transcript — it '
            'gets the same bar those two have',
      );

      // The find bar drops out of the toolbar, so it reaches this dialog for
      // free — and it edits the body field, not the title. Body text goes in
      // first: opening the bar inserts two more TextFields ahead of the body
      // in tree order.
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'draft draft',
      );
      await tester.tap(find.bySemanticsLabel(l10n.findReplaceToggle));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel(l10n.findReplaceFindLabel).first,
        'draft',
      );
      await tester.enterText(
        find.bySemanticsLabel(l10n.findReplaceReplaceLabel).first,
        'final',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(l10n.findReplaceReplaceAllAction));
      await tester.pumpAndSettle();

      expect(find.text('final final'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // The third host, and the one where losing the Escape race costs work: a
    // modal route treats Escape as "dismiss", and the dialog by then holds a
    // prompt template the user has been typing into an 18-line field. As in
    // History, "the find bar closed" proves nothing on its own — a popped
    // dialog closes it too. The body text still being there is the assertion.
    testWidgets('Escape closes the find bar without discarding the draft', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'a template worth keeping',
      );
      await tester.tap(find.bySemanticsLabel(l10n.findReplaceToggle));
      await tester.pumpAndSettle();
      expect(find.byType(WpFindReplaceBar), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(l10n.findReplaceFindLabel).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel(l10n.findReplaceFindLabel).first,
        'template',
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(WpFindReplaceBar), findsNothing);
      expect(
        find.text('a template worth keeping'),
        findsOneWidget,
        reason:
            'Escape reached the modal route and popped the dialog, taking the '
            'unsaved snippet body with it',
      );
    });

    testWidgets('the dialog stays whole at a 2x system text size', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
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
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      final buttons = tester.widgetList<WpButton>(find.byType(WpButton));
      expect(
        buttons.any((b) => b.onPressed == null),
        isTrue,
        reason: 'Dialog save button should be disabled with empty fields',
      );
    });

    testWidgets('adding a snippet persists it, shows it in the list, and fires '
        'a distinct "snippets" telemetry category', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // TextFields in tree order: [0] picker trigger (macOS only), [_fieldOffset]
      // page search, [_fieldOffset + 1] title, [_fieldOffset + 2] body
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Signature',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Best,\nSilvio',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      expect(find.text('Signature'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      final counts = container
          .read(telemetrySessionAggregatorProvider)
          .debugCounts;
      expect(counts[('snippets', 'create', null)], 1);
      expect(counts[('replacements', 'create', null)], isNull);
    });

    testWidgets('tapping a tile opens edit dialog with pre-filled title', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Greeting',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Hi there',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Greeting'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsEditSnippet), findsOneWidget);
      expect(find.text('Greeting'), findsWidgets);
    });

    testWidgets('search field filters visible snippets', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      for (final (title, body) in [
        ('Signature', 'Best, Silvio'),
        ('Greeting', 'Hi there'),
      ]) {
        await tester.tap(find.byIcon(LucideIcons.plus));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).at(_fieldOffset + 1),
          title,
        );
        await tester.enterText(
          find.byType(TextField).at(_fieldOffset + 2),
          body,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.snippetsAdd).last);
        await tester.pumpAndSettle();
      }

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Greeting'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(_fieldOffset), 'Sign');
      await tester.pumpAndSettle();

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Greeting'), findsNothing);
    });

    testWidgets('search with no match shows no-results empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Signature',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Best, Silvio',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(_fieldOffset),
        'zzzznonexistent',
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNoMatches), findsOneWidget);
    });

    testWidgets('hover shows delete icon; tapping it opens confirm dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Signature',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Best, Silvio',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      final tile = find.text('Signature');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(tile));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.trash2), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.trash2));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsDeleteTitle), findsOneWidget);
    });

    // The picker-trigger header (and thus its empty-list hint) only renders
    // on macOS — see the `Platform.isMacOS` guard in `SnippetsPage`.
    testWidgets('a set trigger word with an empty snippet list shows the '
        '"trigger does nothing yet" hint until the first snippet exists', (
      tester,
    ) async {
      if (!Platform.isMacOS) return;
      await tester.pumpWidget(
        makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                const AppSettings(
                  behavior: BehaviorSettings(snippetPickerTrigger: 'snippet'),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.snippetsPickerTriggerEmptyListHint),
        findsOneWidget,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      await container
          .read(snippetsProvider.notifier)
          .add('Signature', 'Best,\nSilvio');
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerTriggerEmptyListHint), findsNothing);
    });

    testWidgets('an empty trigger word shows no empty-list hint even while '
        'the snippet list is empty', (tester) async {
      if (!Platform.isMacOS) return;
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerTriggerEmptyListHint), findsNothing);
    });

    // Notizen bound Ctrl/Cmd+N from the start; its two sibling list screens
    // did not, so "create the next one without leaving the keyboard" was a
    // skill that only paid off on one of the three. The shared shell binds
    // it for both.
    testWidgets('Ctrl/Cmd+N opens the add dialog', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.snippetsNewSnippet), findsNothing);

      await _pressNewItemChord(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
    });

    testWidgets('Ctrl/Cmd+N also fires while the search field has focus', (
      tester,
    ) async {
      // Deliberately unguarded: Ctrl/Cmd+N is not a text-editing binding on
      // any of the three platforms, so the chord means "new snippet"
      // wherever the caret happens to sit — the same contract Notizen has.
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).at(_fieldOffset));
      await tester.pumpAndSettle();

      await _pressNewItemChord(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
    });

    testWidgets('Delete on the focused row opens the delete confirmation', (
      tester,
    ) async {
      // Notizen deletes the focused row from the keyboard; its two siblings
      // could only do it by mouse. Same keys now, different consequence by
      // necessity: no trash exists here, so the confirmation is the undo.
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Signature',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Best, Silvio',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      // Walk the traversal order until the row reveals its delete action.
      for (var i = 0; i < 6; i++) {
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

      expect(find.text(l10n.snippetsDeleteTitle), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Picker-Hotkey auf der Seite — zweite Aufrufstelle, eine Wahrheit (Ticket 27)
  // ---------------------------------------------------------------------------

  group('SnippetsPage — Picker-Hotkey', () {
    Widget subject({AppSettings? settings, bool available = true}) =>
        makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings ?? const AppSettings()),
            ),
            // Dieselbe eine Verfügbarkeits-Aussage, die auch die
            // Einstellungs-Zeile liest — hier gestellt, damit beide Zweige
            // unabhängig vom Rechner prüfbar sind, auf dem der Test läuft.
            snippetPickerAvailabilityProvider.overrideWithValue(available),
          ],
        );

    const enabledHotkey = AppSettings(
      snippetPickerHotkey: SnippetPickerHotkeySettings(
        snippetPickerHotkeyEnabled: true,
        snippetPickerHotkeyKey: ';',
        snippetPickerHotkeyKeyDisplay: 'Ö',
        snippetPickerHotkeyModifiers: 'ctrl+alt',
      ),
    );

    testWidgets('shows the combination next to the spoken trigger word', (
      tester,
    ) async {
      await tester.pumpWidget(subject(settings: enabledHotkey));
      await tester.pumpAndSettle();

      // Beide Auslösewege in Sichtweite: das gesprochene Trigger-Wort und die
      // Tastenkombination stehen in derselben Kopfkarte.
      expect(find.text(l10n.snippetsPickerTriggerLabel), findsOneWidget);
      expect(find.text(l10n.snippetsPickerHotkeyLabel), findsOneWidget);
      // Anzeige-Taste, nicht Speicher-Token — dieselbe Darstellungsform wie
      // in den Einstellungen.
      expect(find.text('Ö'), findsOneWidget);
      expect(find.text(';'), findsNothing);
    });

    testWidgets('the combination is per page, not per snippet', (tester) async {
      await tester.pumpWidget(subject(settings: enabledHotkey));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      await container.read(snippetsProvider.notifier).add('Signature', 'Best');
      await container.read(snippetsProvider.notifier).add('Address', 'Street');
      await tester.pumpAndSettle();

      // Der Hotkey gehört dem Picker, nicht dem einzelnen Snippet — sonst
      // stünde er zweimal in der Liste.
      expect(find.text(l10n.snippetsPickerHotkeyLabel), findsOneWidget);
      expect(
        find.byKey(const Key('snippetsPickerHotkeyChange')),
        findsOneWidget,
      );
    });

    testWidgets('changing it here opens the same recorder dialog and writes '
        'the same single stored state', (tester) async {
      await tester.pumpWidget(subject(settings: enabledHotkey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('snippetsPickerHotkeyChange')));
      await tester.pumpAndSettle();
      // Derselbe Dialog wie in den Einstellungen — kein zweiter.
      expect(find.text(l10n.settingsHotkeyRecorderTitle), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final saved = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      ).read(settingsProvider).value!.snippetPickerHotkey;
      expect(saved.snippetPickerHotkeyKey, 'K');
      expect(saved.snippetPickerHotkeyModifiers, 'ctrl+alt');
      // Die Seite zeigt sofort, was gespeichert wurde: ein zweiter Zustand
      // fiele genau hier auf.
      expect(find.text('K'), findsOneWidget);
    });

    testWidgets('a combination already used by another WhisPaste hotkey is '
        'refused here too', (tester) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: 'E',
              snippetPickerHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('snippetsPickerHotkeyChange')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyKey,
        'E',
        reason: 'the collision check is the settings one, not a second copy',
      );
      expect(
        find.byKey(const Key('snippetsPickerHotkeyCollisionNotice')),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.settingsSnippetPickerHotkeyCollision(
            l10n.settingsHotkeyActionRecording,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a switched-off hotkey says so and can be switched on from '
        'here', (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerHotkeyOff), findsOneWidget);
      expect(find.byKey(const Key('snippetsPickerHotkeyChange')), findsNothing);

      await tester.tap(find.byKey(const Key('snippetsPickerHotkeyEnable')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyEnabled,
        isTrue,
      );
      // Und die Zeile zeigt danach die Kombination, ohne dass jemand die Seite
      // verlassen musste.
      expect(find.text(l10n.snippetsPickerHotkeyOff), findsNothing);
      expect(
        find.byKey(const Key('snippetsPickerHotkeyChange')),
        findsOneWidget,
      );
    });

    testWidgets('where the platform has no picker, the page says so and offers '
        'neither trigger word nor hotkey', (tester) async {
      await tester.pumpWidget(
        subject(settings: enabledHotkey, available: false),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetsPickerUnavailable')),
        findsOneWidget,
      );
      // Derselbe Satz wie in den Einstellungen — eine Auskunft, ein Wortlaut.
      expect(find.text(l10n.snippetsPickerUnavailable), findsOneWidget);
      expect(find.text(l10n.snippetsPickerTriggerLabel), findsNothing);
      expect(find.text(l10n.snippetsPickerHotkeyLabel), findsNothing);
      expect(find.byKey(const Key('snippetsPickerHotkeyChange')), findsNothing);
      expect(find.byKey(const Key('snippetsPickerHotkeyEnable')), findsNothing);
    });

    testWidgets('the combination survives an accessibility text size without '
        'clipping', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: SnippetsPage(),
          ),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(enabledHotkey),
            ),
            snippetPickerAvailabilityProvider.overrideWithValue(true),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('snippetsPickerHotkeyComboLine')),
        findsOneWidget,
      );
    });
  });
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

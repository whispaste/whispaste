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
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/dialog.dart';
import 'package:whispaste/widgets/find_replace_bar.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_search_field.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// The toolbar search field. Found through its wrapper, not by tree index:
/// the toolbar sits above the list header, so its position shifted.
Finder get _searchField => find.descendant(
  of: find.byType(WpSearchField),
  matching: find.byType(TextField),
);

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

    // Ticket 16's third editor. Its acceptance criterion is a *verification*,
    // not a change: the dialog is supposed to get its material for free —
    // the card from the form-dialog shell (Ticket 08), the fields from the
    // `form` variant (Ticket 09) — and the thing worth pinning is that it
    // takes them rather than painting anything of its own. If this ever fails
    // by finding a second surface, the fix is to delete that surface, not to
    // widen the expectation.
    testWidgets('the dialog inherits its material from the shell and the form '
        'fields', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // Scoped to the dialog throughout: the page behind it carries its own
      // fields and its own card material (the picker-trigger field, the
      // search field), and none of that is what this test is about.
      final inDialog = find.descendant(
        of: find.byType(WpFormDialogShell),
        matching: find.byType(WpTextField),
      );
      final fields = tester.widgetList<WpTextField>(inDialog).toList();
      expect(fields, hasLength(2), reason: 'title + body');
      expect(
        fields.map((f) => f.variant).toSet(),
        {WpTextFieldVariant.form},
        reason:
            'both dialog fields are form values under their own label — the '
            'variant that owns that shape, and the one whose box the dialog '
            'must not redraw itself',
      );

      // What the dialog card is made of, collected off the painted boxes
      // rather than off a source read: the shell's floating surface, with the
      // tinted rim, and exactly one of it.
      final dialogBoxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(WpFormDialogShell),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .toList();

      expect(
        dialogBoxes.where((d) => d.color == WpColors.floatingSurface),
        hasLength(1),
        reason:
            'the dialog stands on one floating surface — the shell\'s. A '
            'second one is a card on a card.',
      );

      // And nothing in it stacks the in-plane card material on top of that
      // floating one — the "Fläche auf einer Fläche" Ticket 16 exists to
      // remove, in the one editor that never had it.
      // The light sets paint the floating surface and the lifted card the
      // same white, so the shell's own box is excluded by identity.
      final shellBox = dialogBoxes.singleWhere(
        (d) => d.color == WpColors.floatingSurface,
      );
      final stackedCards = dialogBoxes.where(
        (d) =>
            !identical(d, shellBox) &&
            (d.color == WpColors.cardFill ||
                d.color == WpColors.cardFillElevated),
      );
      expect(stackedCards, isEmpty);
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
      await tester.enterText(find.byType(TextField).at(2), 'draft draft');
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
        find.byType(TextField).at(2),
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

      // TextFields in tree order: [0] page search, [1] title, [2] body
      await tester.enterText(find.byType(TextField).at(1), 'Signature');
      await tester.enterText(find.byType(TextField).at(2), 'Best,\nSilvio');
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
      await tester.enterText(find.byType(TextField).at(1), 'Greeting');
      await tester.enterText(find.byType(TextField).at(2), 'Hi there');
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
        await tester.enterText(find.byType(TextField).at(1), title);
        await tester.enterText(find.byType(TextField).at(2), body);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.snippetsAdd).last);
        await tester.pumpAndSettle();
      }

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Greeting'), findsOneWidget);

      await tester.enterText(_searchField, 'Sign');
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
      await tester.enterText(find.byType(TextField).at(1), 'Signature');
      await tester.enterText(find.byType(TextField).at(2), 'Best, Silvio');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      await tester.enterText(_searchField, 'zzzznonexistent');
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
      await tester.enterText(find.byType(TextField).at(1), 'Signature');
      await tester.enterText(find.byType(TextField).at(2), 'Best, Silvio');
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

    // UIA-SNP-07: the duplicate keeps the copy suffix in the app language.
    testWidgets('a duplicate gets a localised copy suffix (UIA-SNP-07)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('de')),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      await container
          .read(snippetsProvider.notifier)
          .add('Signature', 'Best, Silvio');
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Signature')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.files));
      await tester.pumpAndSettle();

      expect(find.text('Signature (Kopie)'), findsOneWidget);
      expect(find.textContaining('(copy)'), findsNothing);
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

    // UIA-SNP-03: the trigger word typed inside the debounce window is saved
    // when the page is left. The field exists on macOS only (see above).
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

      await tester.tap(_searchField);
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
      await tester.enterText(find.byType(TextField).at(1), 'Signature');
      await tester.enterText(find.byType(TextField).at(2), 'Best, Silvio');
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
  // Interactive-snippet template editor — user-placed {{fieldName}}
  // placeholders instead of the old fixed heading-per-field layout.
  // ---------------------------------------------------------------------------

  group('Interactive snippet templates', () {
    Future<void> openInteractiveDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsKindInteractive));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows a warning and disables save while a field is not referenced '
      'in the template',
      (tester) async {
        await openInteractiveDialog(tester);

        expect(find.text(l10n.snippetsTemplateLabel), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(1), 'Bug Report');
        await tester.enterText(find.byType(TextField).at(2), 'Titel');
        await tester.tap(find.text(l10n.snippetsFieldAdd));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(3), 'Beschreibung');
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.snippetsTemplateMissingFieldsWarning),
          findsOneWidget,
        );
        final buttons = tester.widgetList<WpButton>(find.byType(WpButton));
        expect(
          buttons.any(
            (b) => b.label == l10n.snippetsAdd && b.onPressed == null,
          ),
          isTrue,
          reason: 'Save must stay disabled while a field has no placeholder',
        );
      },
    );

    testWidgets(
      'the insert button places {{fieldName}} in the template and the '
      'saved snippet composes from it',
      (tester) async {
        await openInteractiveDialog(tester);

        await tester.enterText(find.byType(TextField).at(1), 'Bug Report');
        await tester.enterText(find.byType(TextField).at(2), 'Titel');
        await tester.tap(find.text(l10n.snippetsFieldAdd));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(3), 'Beschreibung');
        await tester.pumpAndSettle();

        final insertButtons = find.byTooltip(
          l10n.snippetsFieldInsertIntoTemplate,
        );
        expect(insertButtons, findsNWidgets(2));
        await tester.tap(insertButtons.at(0));
        await tester.pumpAndSettle();
        await tester.tap(insertButtons.at(1));
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.snippetsTemplateMissingFieldsWarning),
          findsNothing,
        );
        final template = tester.widget<TextField>(find.byType(TextField).at(4));
        expect(template.controller!.text, '{{Titel}}{{Beschreibung}}');

        await tester.tap(find.text(l10n.snippetsAdd).last);
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SnippetsPage)),
        );
        final saved = container.read(snippetsProvider).value!.single;
        expect(saved.body, '{{Titel}}{{Beschreibung}}');
        expect(saved.fields, ['Titel', 'Beschreibung']);
      },
    );

    testWidgets(
      'reopening an existing interactive snippet pre-fills its template',
      (tester) async {
        await openInteractiveDialog(tester);
        await tester.enterText(find.byType(TextField).at(1), 'Bug Report');
        await tester.enterText(find.byType(TextField).at(2), 'Titel');
        await tester.tap(find.text(l10n.snippetsFieldAdd));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(3), 'Beschreibung');
        await tester.pumpAndSettle();
        final insertButtons = find.byTooltip(
          l10n.snippetsFieldInsertIntoTemplate,
        );
        await tester.tap(insertButtons.at(0));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).at(4),
          'Betreff: {{Titel}}\n\n{{Beschreibung}}',
        );
        await tester.pumpAndSettle();
        await tester.tap(insertButtons.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.snippetsAdd).last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Bug Report'));
        await tester.pumpAndSettle();

        expect(find.text(l10n.snippetsEditSnippet), findsOneWidget);
        final template = tester.widget<TextField>(find.byType(TextField).at(4));
        expect(template.controller!.text, contains('Betreff: {{Titel}}'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Picker-Hotkey auf der Seite — zweite Aufrufstelle, eine Wahrheit (Ticket 27)
  // ---------------------------------------------------------------------------

  group('SnippetsPage — picker link (UX-030)', () {
    Widget subject({
      AppSettings? settings,
      bool available = true,
      double textScale = 1.0,
    }) => makeTestable(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const SnippetsPage(),
      ),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(settings ?? const AppSettings()),
        ),
        // The one availability answer the Settings row reads as well.
        snippetPickerAvailabilityProvider.overrideWithValue(available),
      ],
    );

    testWidgets('the page links to Settings and holds no trigger field or '
        'hotkey control of its own', (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerSettingsLink), findsOneWidget);
      expect(find.text(l10n.snippetsPickerTriggerLabel), findsNothing);
      expect(find.text(l10n.snippetsPickerHotkeyLabel), findsNothing);
    });

    testWidgets('the link opens Settings at the trigger-word row', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.snippetsPickerSettingsLink));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      expect(
        container.read(settingsScrollTargetProvider),
        'general-snippet-picker-trigger',
      );
      expect(container.read(activePageProvider), 'settings');
    });

    testWidgets('where the platform has no picker, the page says so and '
        'offers no link', (tester) async {
      await tester.pumpWidget(subject(available: false));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetsPickerUnavailable')),
        findsOneWidget,
      );
      // Same sentence as in Settings: one fact, one wording.
      expect(find.text(l10n.snippetsPickerUnavailable), findsOneWidget);
      expect(find.text(l10n.snippetsPickerSettingsLink), findsNothing);
    });

    testWidgets('the link stays whole at an accessibility text size', (
      tester,
    ) async {
      await tester.pumpWidget(subject(textScale: 2.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.snippetsPickerSettingsLink), findsOneWidget);
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

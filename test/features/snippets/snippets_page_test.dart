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
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

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

      // TextFields in tree order: [0] page search, [1] title, [2] body.
      // There is no platform-dependent offset any more — the picker-trigger
      // field that used to lead this list on macOS moved to Settings.
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

      await tester.enterText(find.byType(TextField).at(0), 'Sign');
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

      await tester.enterText(find.byType(TextField).at(0), 'zzzznonexistent');
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

      await tester.tap(find.byType(TextField).at(0));
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
}

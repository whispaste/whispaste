/// Tests for [SnippetsPage].
///
/// Covers: empty state, Add dialog, dialog validation, Edit pre-fill, search
/// filter, no-results state, hover → delete confirmation, telemetry category.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/telemetry_service.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

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
      expect(find.text(l10n.snippetsTitleLabel), findsOneWidget);
      expect(find.text(l10n.snippetsBodyLabel), findsOneWidget);
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

      final buttons = tester.widgetList<ElevatedButton>(
        find.byType(ElevatedButton),
      );
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

      // TextFields in tree order: [0] picker trigger, [1] page search,
      // [2] title, [3] body
      await tester.enterText(find.byType(TextField).at(2), 'Signature');
      await tester.enterText(find.byType(TextField).at(3), 'Best,\nSilvio');
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
      expect(counts[('automations', 'create', null)], isNull);
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
      await tester.enterText(find.byType(TextField).at(2), 'Greeting');
      await tester.enterText(find.byType(TextField).at(3), 'Hi there');
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
        await tester.enterText(find.byType(TextField).at(2), title);
        await tester.enterText(find.byType(TextField).at(3), body);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.snippetsAdd).last);
        await tester.pumpAndSettle();
      }

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Greeting'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), 'Sign');
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
      await tester.enterText(find.byType(TextField).at(2), 'Signature');
      await tester.enterText(find.byType(TextField).at(3), 'Best, Silvio');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), 'zzzznonexistent');
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
      await tester.enterText(find.byType(TextField).at(2), 'Signature');
      await tester.enterText(find.byType(TextField).at(3), 'Best, Silvio');
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
  });
}

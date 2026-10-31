/// Widget tests for `VocabularyImportReviewPage`'s search filter.
///
/// The filter is a plain, testable state method (`_applyFilter`) driven by
/// the search field's `onChanged`, so these tests just type into it and
/// check which candidates remain. Covers case-insensitivity and — since the
/// filter builds a `RegExp` from the raw query — that regex metacharacters
/// in the query are treated literally (`RegExp.escape`), not as pattern
/// syntax.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/replacements/vocabulary_import_review_page.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

Future<void> _pump(WidgetTester tester, List<String> candidates) async {
  await tester.pumpWidget(
    makeTestable(
      VocabularyImportReviewPage(candidates: candidates),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('VocabularyImportReviewPage search filter', () {
    testWidgets('is case-insensitive', (tester) async {
      await _pump(tester, ['UserRepository', 'orderService', 'Invoice']);

      await tester.enterText(find.byType(TextField), 'user');
      await tester.pumpAndSettle();

      expect(find.text('UserRepository'), findsOneWidget);
      expect(find.text('orderService'), findsNothing);
      expect(find.text('Invoice'), findsNothing);
    });

    testWidgets('matches a substring anywhere in the candidate', (
      tester,
    ) async {
      await _pump(tester, ['UserRepository', 'orderService', 'Invoice']);

      await tester.enterText(find.byType(TextField), 'Repo');
      await tester.pumpAndSettle();

      expect(find.text('UserRepository'), findsOneWidget);
      expect(find.text('orderService'), findsNothing);
    });

    testWidgets('treats regex metacharacters in the query literally', (
      tester,
    ) async {
      await _pump(tester, ['c++Wrapper', 'plainName', 'a.b.c']);

      // '+' is a regex quantifier and '.' matches any char — a naive
      // RegExp(query) would either throw (dangling quantifier) or
      // over-match. RegExp.escape must keep these literal.
      await tester.enterText(find.byType(TextField), 'c++');
      await tester.pumpAndSettle();

      expect(find.text('c++Wrapper'), findsOneWidget);
      expect(find.text('plainName'), findsNothing);
      expect(find.text('a.b.c'), findsNothing);
    });

    testWidgets('an empty query restores the full candidate list', (
      tester,
    ) async {
      await _pump(tester, ['Alpha', 'Beta', 'Gamma']);

      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
    });
  });

  group('VocabularyImportReviewPage bulk actions', () {
    testWidgets('select-all and deselect-all carry the same weight', (
      tester,
    ) async {
      await _pump(tester, const ['Alpha', 'Beta']);

      final selectAll = tester.widget<WpButton>(
        find.byKey(const Key('vocabulary-import-select-all')),
      );
      final deselectAll = tester.widget<WpButton>(
        find.byKey(const Key('vocabulary-import-deselect-all')),
      );
      expect(selectAll.variant, WpButtonVariant.secondary);
      expect(deselectAll.variant, selectAll.variant);
      expect(deselectAll.tone, selectAll.tone);
      expect(deselectAll.size, selectAll.size);
    });

    testWidgets('import button is disabled while nothing is selected', (
      tester,
    ) async {
      await _pump(tester, const ['Alpha', 'Beta']);

      final importButton = tester.widget<WpButton>(
        find.byKey(const Key('vocabulary-import-confirm')),
      );
      expect(importButton.onPressed, isNull);
    });

    testWidgets('import button is enabled once a candidate is selected', (
      tester,
    ) async {
      await _pump(tester, const ['Alpha', 'Beta']);

      await tester.tap(find.byKey(const Key('vocabulary-import-select-all')));
      await tester.pumpAndSettle();

      final importButton = tester.widget<WpButton>(
        find.byKey(const Key('vocabulary-import-confirm')),
      );
      expect(importButton.onPressed, isNotNull);
    });
  });
}

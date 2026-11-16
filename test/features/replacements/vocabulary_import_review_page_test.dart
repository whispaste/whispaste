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
import 'package:whispaste/widgets/page_shell.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

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

Finder _row(String term) =>
    find.byKey(ValueKey('dictionary-import-review-row-$term'));

void main() {
  testWidgets('uses the shared page frame with a back button (#618)', (
    tester,
  ) async {
    await _pump(tester, ['Invoice']);

    expect(find.byType(WpPageShell), findsOneWidget);
    expect(find.byType(WpPageHeader), findsOneWidget);
    expect(find.byType(SafeArea), findsNothing);
    expect(
      find.byKey(const ValueKey('dictionary-import-review-back')),
      findsOneWidget,
    );
  });

  group('VocabularyImportReviewPage search filter', () {
    testWidgets('is case-insensitive', (tester) async {
      await _pump(tester, ['UserRepository', 'orderService', 'Invoice']);

      await tester.enterText(find.byType(TextField), 'user');
      await tester.pumpAndSettle();

      expect(_row('UserRepository'), findsOneWidget);
      expect(_row('orderService'), findsNothing);
      expect(_row('Invoice'), findsNothing);
    });

    testWidgets('matches a substring anywhere in the candidate', (
      tester,
    ) async {
      await _pump(tester, ['UserRepository', 'orderService', 'Invoice']);

      await tester.enterText(find.byType(TextField), 'Repo');
      await tester.pumpAndSettle();

      expect(_row('UserRepository'), findsOneWidget);
      expect(_row('orderService'), findsNothing);
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

      expect(_row('c++Wrapper'), findsOneWidget);
      expect(_row('plainName'), findsNothing);
      expect(_row('a.b.c'), findsNothing);
    });

    testWidgets('an empty query restores the full candidate list', (
      tester,
    ) async {
      await _pump(tester, ['Alpha', 'Beta', 'Gamma']);

      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();
      expect(_row('Alpha'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(_row('Alpha'), findsOneWidget);
      expect(_row('Beta'), findsOneWidget);
      expect(_row('Gamma'), findsOneWidget);
    });
  });

  group('VocabularyImportReviewPage bulk actions', () {
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

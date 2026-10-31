/// Search-empty guard for the list areas that share the search scaffold.
///
/// An empty result for a query must offer a way back out, so the user is never
/// stranded behind their own search.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../fixtures/test_helpers.dart';

/// Pinned so the four areas are never compared across two translations.
const _locale = Locale('en');
late L10n _l10n;

/// Renders the real Snippets page and seeds it through its own notifier.
Future<void> _pumpSnippets(WidgetTester tester) async {
  await tester.pumpWidget(makeTestable(locale: _locale, const SnippetsPage()));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SnippetsPage)),
  );
  await container
      .read(snippetsProvider.notifier)
      .add('Signature', 'Best regards,\nSilvio');
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    _l10n = await L10n.delegate.load(_locale);
  });

  group('search-empty states offer a way out', () {
    // Ticket 03, point 8. Verlauf and Notizen already offered it; the shared
    // scaffold behind Replacements and Snippets turned out to offer it too, so
    // nothing had to be built — but nothing pinned it either, and an empty
    // state that strands the user behind their own query is exactly the sort
    // of regression that goes unnoticed until someone searches for a typo.
    testWidgets('snippets offers "clear search" when nothing matches', (
      tester,
    ) async {
      await _pumpSnippets(tester);
      // The toolbar search field, found through its wrapper: the picker
      // trigger field sits below the toolbar in tree order, so `.last` is no
      // longer the search field.
      await tester.enterText(
        find.descendant(
          of: find.byType(WpSearchField),
          matching: find.byType(TextField),
        ),
        'zzzz-no-such-snippet',
      );
      await tester.pumpAndSettle();

      expect(
        find.text(_l10n.actionClearSearch),
        findsOneWidget,
        reason:
            'the no-matches state offers no way back out of the search — the '
            'WpEmptyState rule this app documents says it always does',
      );
    });
  });
}

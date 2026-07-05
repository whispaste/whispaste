/// Widget tests for the search-operator discoverability hint wired into
/// [HistorySearchFilterBar] (issue 03, experience-perf-polish Cluster 2).
///
/// Verifies the shared [WpDiscoverabilityHint] component is actually used at
/// this call site too: visible by default while the query is empty, and
/// permanently gone once the "seen" flag has been persisted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'shows the search-operator hint by default when the query is empty',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(const HistoryPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.historySearchOperatorsHint), findsOneWidget);

      // Drain any pending Drift/Riverpod cleanup timers before the test
      // framework tears down the widget tree, otherwise the framework's
      // `!timersPending` invariant fires from the in-memory DB's
      // `StreamQueryStore.markAsClosed` scheduling a zero-duration timer.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('stays hidden once the seen-flag is already persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discoverability_hint_seen_search_operators': true,
    });

    await tester.pumpWidget(
      makeTestable(const HistoryPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.historySearchOperatorsHint), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

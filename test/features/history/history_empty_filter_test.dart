/// An empty filter view offers a way back to "All" (UIA-HIS-21).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('an empty pinned view offers "Show all" (UIA-HIS-21)', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      makeTestable(
        const HistoryPage(),
        locale: const Locale('en'),
        overrides: [
          historyEntriesProvider.overrideWith(
            (ref) => Stream<List<HistoryEntry>>.value(const []),
          ),
          archivedEntriesProvider.overrideWith(
            (ref) => Stream<List<HistoryEntry>>.value(const []),
          ),
          trashEntriesProvider.overrideWith(
            (ref) => Stream<List<HistoryEntry>>.value(const []),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryPage)),
    );
    container.read(historyFilterProvider.notifier).set(HistoryFilter.pinned);
    await tester.pumpAndSettle();

    expect(find.text(l10n.historyShowAll), findsOneWidget);
    await tester.tap(find.text(l10n.historyShowAll));
    await tester.pumpAndSettle();

    expect(container.read(historyFilterProvider), HistoryFilter.all);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

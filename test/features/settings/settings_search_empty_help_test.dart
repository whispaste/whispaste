/// The empty state of a Settings search without a match hands the query to
/// the handbook search on the Help page instead of opening the repository
/// (UIA-SET-11).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/navigation/help_target.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('"Search in help" opens the handbook search with the query', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const SettingsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );

    container.read(settingsSearchQueryProvider.notifier).set('zqxj nomatch');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-search-empty-help')));
    await tester.pumpAndSettle();

    expect(container.read(activePageProvider), 'help');
    expect(
      container.read(helpTargetProvider),
      const HelpTarget(tab: HelpTab.manual, query: 'zqxj nomatch'),
    );
  });
}

// UIA-HIS-14: the smart panel (recent searches, popular tags) is operable with
// the arrow keys and Enter, like the tag and language lists.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/recent_searches.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';

import '../../fixtures/test_helpers.dart';

class _FakeRecent extends RecentSearchesNotifier {
  @override
  List<String> build() => const ['alpha', 'beta'];
}

void main() {
  testWidgets(
    'arrows move through recent searches and Enter replays one (UIA-HIS-14)',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          Scaffold(
            body: HistorySearchFilterBar(
              controller: controller,
              searchFocusNode: focus,
              activeFilter: HistoryFilter.all,
              onFilterChanged: (_) {},
              onSearchChanged: () {},
              resultCount: 0,
              viewMode: HistoryViewMode.list,
              onViewModeChanged: (_) {},
              multiSelectMode: false,
              onToggleMultiSelect: () {},
              sortOrder: HistorySortOrder.newest,
              onSortOrderChanged: (_) {},
            ),
          ),
          overrides: [recentSearchesProvider.overrideWith(_FakeRecent.new)],
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      focus.requestFocus();
      await tester.pumpAndSettle();

      // Enter before any arrow does nothing: no item is highlighted yet.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.text, 'beta');
    },
  );
}

/// #878 evidence in the native desktop app: the real HistoryPage, backed by a
/// real database with thousands of rows, scrolled by real pointer gestures.
/// Logs the page-limit growth and whether the loading indicator
/// (`history-load-more`) appeared. Optional hold at the end (`HOLD_SECONDS`)
/// leaves the window open for a screenshot.
/// Run: `flutter test integration_test/history_paging_native_test.dart -d linux`
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../test/fixtures/test_helpers.dart';
import '../test/test_helpers/test_deadline.dart';

const _entries = int.fromEnvironment('BENCH_ENTRIES', defaultValue: 5000);
const _holdSeconds = int.fromEnvironment('HOLD_SECONDS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('history list pages while scrolling', (tester) async {
    debugPrint('NATIVE start entries=$_entries');
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.batch((b) {
      b.insertAll(db.historyEntries, [
        for (var i = 0; i < _entries; i++)
          HistoryEntriesCompanion.insert(
            id: 'b${i.toString().padLeft(6, '0')}',
            timestamp: DateTime(2025, 1, 1).add(Duration(minutes: i)),
            content: Value('Paging entry ${i.toString().padLeft(6, '0')}'),
            title: Value('Paging entry ${i.toString().padLeft(6, '0')}'),
          ),
      ]);
    });

    debugPrint('NATIVE seeded');
    final deadline = TestDeadline(const Duration(seconds: 60));
    await tester.pumpWidget(
      makeTestable(const HistoryPage(), db: db, locale: const Locale('en')),
    );
    while (find.textContaining('Paging entry').evaluate().isEmpty) {
      if (deadline.expired) fail('list never appeared');
      await tester.pump(const Duration(milliseconds: 16));
    }

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryPage)),
    );
    final more = find.byKey(const ValueKey('history-load-more'));
    var sawIndicator = false;
    var lastLimit = container.read(historyPageLimitProvider);
    debugPrint('NATIVE limit=$lastLimit');
    final scrollable = find
        .ancestor(
          of: find.textContaining('Paging entry').first,
          matching: find.byType(Scrollable),
        )
        .first;
    for (var i = 0; i < 80 && lastLimit < 300; i++) {
      await tester.fling(scrollable, const Offset(0, -2500), 6000);
      for (var f = 0; f < 12; f++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (more.evaluate().isNotEmpty) sawIndicator = true;
      }
      if (i % 5 == 0) {
        final px = tester.state<ScrollableState>(scrollable).position.pixels;
        debugPrint('NATIVE fling $i pixels=${px.round()}');
      }
      final limit = container.read(historyPageLimitProvider);
      if (limit != lastLimit) {
        debugPrint(
          'NATIVE limit=$limit loaded='
          '${container.read(pagedHistoryProvider).value?.length} '
          'indicatorSeen=$sawIndicator',
        );
        lastLimit = limit;
      }
    }
    debugPrint(
      'NATIVE done limit=$lastLimit indicatorSeen=$sawIndicator '
      'indicatorTestId=history-load-more',
    );
    expect(lastLimit, greaterThanOrEqualTo(150));
    expect(sawIndicator, isTrue);

    if (_holdSeconds > 0) {
      debugPrint('NATIVE hold ${_holdSeconds}s for screenshot');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: _holdSeconds)),
      );
    }
  });
}

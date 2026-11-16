/// #879 evidence in the native desktop app: the real HistoryPage on a real
/// database, the duration chips operated by keyboard and pointer. Logs each
/// step (`NATIVE ...`); `HOLD_SECONDS` keeps the window open after the chip
/// step and after the empty state for a screenshot.
/// Run: `flutter test integration_test/history_duration_chips_native_test.dart -d linux`
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../test/fixtures/test_helpers.dart';
import '../test/test_helpers/test_deadline.dart';

const _holdSeconds = int.fromEnvironment('HOLD_SECONDS');

Future<void> _hold(WidgetTester tester, String step) async {
  debugPrint('NATIVE hold $step');
  for (var i = 0; i < _holdSeconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('duration chips filter the real history list', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    const lengths = {
      'Quick reminder': 12.0,
      'Shopping list': 45.0,
      'Standup notes': 60.0,
      'Client call summary': 180.0,
      'Draft for the newsletter': 300.0,
      'Workshop recap': 420.0,
      'Interview transcript': 1260.0,
    };
    var i = 0;
    await db.batch((b) {
      b.insertAll(db.historyEntries, [
        for (final e in lengths.entries)
          HistoryEntriesCompanion.insert(
            id: 'd${i++}',
            timestamp: DateTime(2026, 11, 10, 9).add(Duration(minutes: i)),
            content: Value('${e.key} (${e.value.round()} s)'),
            title: Value(e.key),
            durationSec: Value(e.value),
          ),
      ]);
    });

    await tester.pumpWidget(
      makeTestable(const HistoryPage(), db: db, locale: const Locale('en')),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryPage)),
    );
    List<String> shown() => [
      for (final e
          in container.read(filteredHistoryProvider).value ??
              const <HistoryEntry>[])
        e.title,
    ];
    final deadline = TestDeadline(const Duration(seconds: 60));
    while (shown().length < lengths.length) {
      if (deadline.expired) fail('list never loaded: ${shown()}');
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    debugPrint('NATIVE all=${shown()}');

    // The duration chips live in the filter popover (#1201).
    await tester.tap(find.bySemanticsIdentifier('history-filter-menu'));
    await tester.pumpAndSettle();

    // Keyboard: focus the "1–5 min" chip and activate it with Space.
    final medium = find.bySemanticsIdentifier('history-duration-medium');
    tester
        .widget<InkWell>(
          find.descendant(of: medium, matching: find.byType(InkWell)),
        )
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    debugPrint(
      'NATIVE keyboard bucket=${container.read(historyDurationBucketProvider)} '
      'shown=${shown()}',
    );
    expect(
      container.read(historyDurationBucketProvider),
      HistoryDurationBucket.medium,
    );

    // Pointer: the "over 5 min" chip.
    await tester.tap(find.bySemanticsIdentifier('history-duration-long'));
    await tester.pumpAndSettle();
    debugPrint('NATIVE long shown=${shown()}');
    expect(shown().toSet(), {'Workshop recap', 'Interview transcript'});
    await _hold(tester, 'long');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Search plus chip leave nothing: the empty state names the chip.
    await tester.enterText(find.byType(TextField).first, 'reminder');
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier('history-duration-reset'),
      findsOneWidget,
    );
    debugPrint('NATIVE empty state shown');
    await _hold(tester, 'empty');

    await tester.tap(find.bySemanticsIdentifier('history-duration-reset'));
    await tester.pumpAndSettle();
    debugPrint('NATIVE reset shown=${shown()}');
    expect(shown(), ['Quick reminder']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();
  });
}

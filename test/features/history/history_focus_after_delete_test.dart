// UIA-HIS-08: after Delete the focus moves to the neighbouring entry, so a
// run of deletes does not drop the keyboard cursor back to the top.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

Finder _focusedRow() =>
    find.byWidgetPredicate((w) => w is HistoryEntryRow && w.isFocused);

void main() {
  testWidgets(
    'Delete moves the keyboard focus to the next entry (UIA-HIS-08)',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (var i = 0; i < 3; i++) {
        await db.insertHistoryEntry(
          HistoryEntriesCompanion.insert(
            id: 'focus-$i',
            timestamp: DateTime(2026, 1, 1, 12).subtract(Duration(minutes: i)),
            content: Value('text $i'),
            title: Value('Entry 0$i'),
          ),
        );
      }

      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          locale: const Locale('en'),
          db: db,
          overrides: [
            settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entry 00'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(find.text('Entry 00'), findsNothing);
      // With the focus on Entry 01, one ArrowDown reaches Entry 02. A stale
      // focus would restart the cursor at the top and land on Entry 01.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _focusedRow(), matching: find.text('Entry 02')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

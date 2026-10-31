// UIA-HIS-07: a failed merge says so instead of leaving the selection
// silently in place.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _MergeFailsDatabase extends HistoryDatabase {
  _MergeFailsDatabase() : super.forTesting(NativeDatabase.memory());

  @override
  Future<HistoryEntry?> mergeEntries(List<String> entryIds) async {
    throw StateError('database is locked');
  }
}

void main() {
  late L10n l10n;
  late HistoryDatabase db;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() async {
    db = _MergeFailsDatabase();
    for (var i = 0; i < 2; i++) {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'merge-$i',
          timestamp: DateTime.now().subtract(Duration(minutes: i)),
          content: Value('text $i'),
          model: const Value('whisper-small'),
        ),
      );
    }
  });

  tearDown(() => db.close());

  testWidgets('a failed merge shows the write-failed toast (UIA-HIS-07)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
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

    await tester.sendKeyDownEvent(primaryShortcutModifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(primaryShortcutModifier);
    await tester.pumpAndSettle();

    // Merge lives in the bar's overflow menu (UIA-HIS-18).
    await tester.tap(find.byKey(const ValueKey('history-multiselect-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('history-multiselect-more-merge')),
    );
    await tester.pumpAndSettle();
    // The confirm dialog repeats the label; its button is the last match.
    await tester.tap(find.text(l10n.historyMerge).last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text(l10n.historyWriteFailedToast), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

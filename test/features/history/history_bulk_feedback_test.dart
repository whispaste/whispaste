// UIA-HIS-06: a bulk archive says how many entries it moved and can be undone,
// like the single-entry path.
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

void main() {
  late L10n l10n;
  late HistoryDatabase db;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    for (var i = 0; i < 2; i++) {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'bulk-$i',
          timestamp: DateTime.now().subtract(Duration(minutes: i)),
          content: Value('text $i'),
          model: const Value('whisper-small'),
        ),
      );
    }
  });

  tearDown(() => db.close());

  testWidgets('bulk archive reports the count and offers undo (UIA-HIS-06)', (
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

    // Archive is a secondary batch action, so it sits in the bar's overflow
    // menu (UIA-HIS-18). The menu opens through its state, as the button can
    // sit under the title bar at this surface size.
    tester
        .state<PopupMenuButtonState<VoidCallback>>(
          find.byKey(const ValueKey('history-multiselect-more')),
        )
        .showButtonMenu();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('history-multiselect-more-archive')),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(l10n.historyBulkArchived(2)), findsOneWidget);
    expect(find.text(l10n.historyUndo), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

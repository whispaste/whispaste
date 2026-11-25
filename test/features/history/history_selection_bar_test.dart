// The selection bar stands as soon as select mode is on, also with nothing
// ticked yet, directly between the search row and the list (#1845, page
// family `internal-notes` ①).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/widgets/wp_collection_page.dart';
import 'package:whispaste/widgets/wp_multi_select_bar.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  late HistoryDatabase db;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    for (var i = 0; i < 2; i++) {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'sel-$i',
          timestamp: DateTime(2026, 11, 19, 12).subtract(Duration(minutes: i)),
          content: Value('text $i'),
          model: const Value('whisper-small'),
        ),
      );
    }
  });

  tearDown(() => db.close());

  testWidgets('select mode shows the bar with 0 selected above the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final l10n = await L10n.delegate.load(const Locale('en'));
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
    expect(find.byType(WpMultiSelectBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey('history-select-toggle')));
    await tester.pumpAndSettle();

    expect(find.byType(WpMultiSelectBar), findsOneWidget);
    expect(find.text(l10n.historyItemsSelected(0)), findsOneWidget);
    final bar = tester.getRect(find.byType(WpMultiSelectBar));
    final toolbar = tester.getRect(find.byType(WpCollectionToolbar));
    final list = tester.getRect(
      find.byKey(const ValueKey('history-list-area')),
    );
    expect(bar.top, greaterThanOrEqualTo(toolbar.bottom));
    expect(bar.bottom, lessThanOrEqualTo(list.top));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

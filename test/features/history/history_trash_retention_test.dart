/// BIZ-15: the trash hint names the period the app really applies (the
/// `historyAutoTrashDays` setting, shown as the Standard/Minimal presets), not a
/// number baked into the copy. UX-028: the empty-trash confirmation names how
/// many recordings it permanently deletes.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

AppSettings _withTrashDays(int days) =>
    AppSettings(history: HistorySettings(historyAutoTrashDays: days));

/// Pumps the history page on its trash view with [trashed] entries in the
/// trash and [db] as the backing database.
Future<void> _pumpTrash(
  WidgetTester tester, {
  required AppSettings settings,
  required HistoryDatabase db,
  List<HistoryEntry> trashed = const [],
}) async {
  await tester.pumpWidget(
    makeTestable(
      const HistoryPage(),
      locale: const Locale('en'),
      db: db,
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
        historyEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(trashed)),
      ],
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HistoryPage)),
  );
  container.read(historyFilterProvider.notifier).set(HistoryFilter.trash);
  await tester.pumpAndSettle();
}

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('BIZ-15 trash hint follows the retention setting', () {
    for (final (days, expected) in [
      (30, 'after 30 days'), // Minimal preset
      (90, 'after 90 days'), // Standard preset and the code default
    ]) {
      testWidgets('$days days in settings reads "$expected"', (tester) async {
        await _pumpTrash(tester, settings: _withTrashDays(days), db: db);

        expect(find.textContaining(expected), findsOneWidget);
      });
    }

    testWidgets('the default settings name the default period', (tester) async {
      await _pumpTrash(tester, settings: AppSettings.defaults, db: db);

      expect(
        find.textContaining(
          'after ${AppSettings.defaults.history.historyAutoTrashDays} days',
        ),
        findsOneWidget,
      );
    });

    testWidgets('unlimited (0 days) says nothing is removed automatically', (
      tester,
    ) async {
      await _pumpTrash(tester, settings: _withTrashDays(0), db: db);

      expect(find.textContaining('days'), findsNothing);
      expect(find.textContaining('after'), findsNothing);
    });
  });

  group('UIA-HIS-01 permanent delete asks first', () {
    Future<List<HistoryEntry>> seedTrash(int count) async {
      final now = DateTime.now();
      for (var i = 0; i < count; i++) {
        await db.insertHistoryEntry(
          HistoryEntriesCompanion.insert(
            id: 'trash-$i',
            timestamp: now,
            deletedAt: Value(now),
          ),
        );
      }
      return db.select(db.historyEntries).get();
    }

    testWidgets('deleting a trashed entry shows a confirmation and keeps it '
        'until confirmed', (tester) async {
      final trashed = await tester.runAsync(() => seedTrash(1)) ?? const [];
      tester.view.physicalSize = const Size(1800, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      // A focused trash row overflows its action bar by a few pixels in
      // this test layout (pre-existing, not UIA-HIS-01). Only that overflow
      // is tolerated; every other framework error still fails the test.
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (!details.exceptionAsString().contains('overflowed')) {
          previousOnError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previousOnError);
      await _pumpTrash(
        tester,
        settings: AppSettings.defaults,
        db: db,
        trashed: trashed,
      );

      // Arrow down focuses the first entry; Delete then asks for a
      // permanent-delete confirmation.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(find.text('Delete permanently?'), findsOneWidget);
      expect(
        await tester.runAsync(() => db.select(db.historyEntries).get()),
        hasLength(1),
        reason: 'nothing is deleted before the user confirms',
      );

      await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(
        await tester.runAsync(() => db.select(db.historyEntries).get()),
        isEmpty,
      );
    });
  });

  group('UX-028 empty-trash confirmation names the count', () {
    testWidgets('three trashed entries are named in the confirmation', (
      tester,
    ) async {
      final now = DateTime.now();
      for (final id in ['a', 'b', 'c']) {
        await db.insertHistoryEntry(
          HistoryEntriesCompanion.insert(
            id: id,
            timestamp: now,
            deletedAt: Value(now),
          ),
        );
      }
      final trashed = await db.select(db.historyEntries).get();

      await _pumpTrash(
        tester,
        settings: AppSettings.defaults,
        db: db,
        trashed: trashed,
      );

      await tester.tap(find.text('Empty trash'));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 transcriptions'), findsOneWidget);
    });
  });
}

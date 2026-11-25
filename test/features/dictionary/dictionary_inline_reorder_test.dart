// #1969: the order of the replacements is changed right in the dictionary
// list, by the grip or Alt+Up/Down, without a separate order dialog.
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/sorting/list_sort_preference.dart';
import 'package:whispaste/core/sorting/list_sort.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';

import '../../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  test('the dictionary shows the order of use by default', () {
    expect(kReplacementsDefaultSort, const ListSort(ListSortField.order));
  });

  Future<HistoryDatabase> pumpPage(WidgetTester tester) async {
    final db = HistoryDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    await tester.runAsync(() async {
      await db.writeAppSettings({'replacementsSamplesSeeded': '1'});
      for (final (i, t) in ['zeta', 'alpha', 'mid'].indexed) {
        await db.upsertReplacementWithTriggers(
          id: t,
          triggers: [t],
          replacement: t.toUpperCase(),
          createdAt: DateTime(2026, 1, 1, 0, i),
        );
      }
      await db.reorderReplacements(['zeta', 'alpha', 'mid']);
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      makeTestable(
        const DictionaryPage(),
        db: db,
        overrides: [settingsProvider.overrideWith(_Settings.new)],
        locale: const Locale('en'),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(db.readAllReplacements);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return db;
  }

  Future<List<String>> order(WidgetTester tester, HistoryDatabase db) async => [
    for (final r in (await tester.runAsync(db.readAllReplacements))!) r.row.id,
  ];

  testWidgets('rows lead with a grip, in the order they apply', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const ValueKey('dictionary-order-open')), findsNothing);
    for (final id in ['zeta', 'alpha', 'mid']) {
      expect(find.byKey(ValueKey('replacements-drag-$id')), findsOneWidget);
    }
    final ys = [
      for (final id in ['zeta', 'alpha', 'mid'])
        tester.getTopLeft(find.byKey(ValueKey('replacements-row-$id'))).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('Alt+Down on a row moves it one place', (tester) async {
    final db = await pumpPage(tester);

    final row = find.byKey(const ValueKey('replacements-row-zeta'));
    await tester.ensureVisible(row);
    // The row's own focus (the one Tab reaches), not the search bar.
    final node = [
      for (final e
          in find.descendant(of: row, matching: find.byType(Focus)).evaluate())
        (e.widget as Focus).focusNode,
    ].whereType<FocusNode>().firstWhere((n) => n.canRequestFocus);
    node.requestFocus();
    await tester.pump();
    expect(node.hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(db.readAllReplacements);
      await tester.pump();
    }

    expect(await order(tester, db), ['alpha', 'zeta', 'mid']);
  });

  testWidgets('dragging the grip moves the row', (tester) async {
    final db = await pumpPage(tester);

    final grip = find.byKey(const ValueKey('replacements-drag-mid'));
    final top = tester.getTopLeft(
      find.byKey(const ValueKey('replacements-row-zeta')),
    );
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 10; step++) {
      await gesture.moveTo(
        Offset.lerp(tester.getCenter(grip), top, step / 10)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(db.readAllReplacements);
      await tester.pump();
    }

    expect((await order(tester, db)).first, 'mid');
  });
}

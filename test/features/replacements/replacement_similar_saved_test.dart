// #1969: a match mode or tolerance picked in the entry dialog is input like
// typed text. Leaving the dialog without saving asks first instead of
// silently dropping "Similar"; saving stores it.
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  const modeKey = ValueKey('replacements-match-mode-choice');

  Future<HistoryDatabase> openEditDialog(WidgetTester tester) async {
    final db = HistoryDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    await tester.runAsync(() async {
      await db.writeAppSettings({'replacementsSamplesSeeded': '1'});
      await db.upsertReplacementWithTriggers(
        id: 'k',
        triggers: const ['kubernetis'],
        replacement: 'Kubernetes',
        createdAt: DateTime(2026),
      );
    });
    await tester.pumpWidget(
      makeTestable(
        const ReplacementsPage(),
        locale: const Locale('en'),
        db: db,
      ),
    );
    // Lets the database work queued by the frame finish (no real wait).
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(db.readAllReplacements);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('replacements-row-k')));
    await tester.pumpAndSettle();
    return db;
  }

  void pickSimilar(WidgetTester tester) => tester
      .widget<WpSegmentedChoice<TextReplacementMatchMode>>(find.byKey(modeKey))
      .onChanged(TextReplacementMatchMode.fuzzy);

  testWidgets('leaving after picking Similar asks instead of dropping it', (
    tester,
  ) async {
    await openEditDialog(tester);
    pickSimilar(tester);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const ValueKey('confirm-dialog-confirm')),
      findsOneWidget,
    );
  });

  testWidgets('saving after picking Similar stores it', (tester) async {
    final db = await openEditDialog(tester);
    pickSimilar(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('replacements-save')));
    // Lets the database work queued by the frame finish (no real wait).
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(db.readAllReplacements);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final rows = await tester.runAsync(db.readAllReplacements);
    expect(rows!.single.row.matchMode, TextReplacementMatchMode.fuzzy.name);
  });
}

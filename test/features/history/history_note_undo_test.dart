// UIA-HIS-24: undoing the delete of a note keeps its original creation date.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_notes_section.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('undoing a note delete restores its creation date (UIA-HIS-24)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final l10n = await L10n.delegate.load(const Locale('en'));
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final createdAt = DateTime(2020, 1, 1, 9);
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'e1',
        timestamp: DateTime(2026, 1, 1, 12),
        content: const Value('entry'),
      ),
    );
    await db.upsertNote(
      EntryNotesCompanion(
        id: const Value('n1'),
        entryId: const Value('e1'),
        content: const Value('Old note'),
        createdAt: Value(createdAt),
        updatedAt: Value(createdAt),
      ),
    );

    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: HistoryNotesSection(entryId: 'e1')),
        db: db,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.actionDelete).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.undo), findsOneWidget);

    await tester.tap(find.text(l10n.undo));
    await tester.pumpAndSettle();

    final restored = await db.select(db.entryNotes).get();
    expect(restored.single.content, 'Old note');
    expect(restored.single.createdAt, createdAt);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

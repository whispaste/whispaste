/// The two ends of the note <-> recording link (issue #629): shown while the
/// other side is alive, gone otherwise, and a click opens the other side.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/history/widgets/history_note_link.dart';
import 'package:whispaste/features/notes/widgets/note_source_link.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      makeTestable(child, db: db, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
  }

  // drift closes a stream's query on a zero timer; let it fire before the
  // test ends.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  testWidgets('the recording opens its note', (tester) async {
    await tester.runAsync(() async {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(id: 'e1', timestamp: DateTime(2026, 11)),
      );
      await db.createNoteFromEntry('e1', 'text');
    });
    await pump(tester, const Scaffold(body: HistoryNoteLink(entryId: 'e1')));

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsIdentifier('history-detail-note-link'), findsOne);
    await tester.tap(find.bySemanticsIdentifier('history-detail-note-link'));
    await tester.pump();
    semantics.dispose();

    final container = containerOf(tester);
    expect(container.read(activePageProvider), 'notes');
    expect(container.read(notesEditorTargetProvider), isNotNull);
    await teardownTree(tester);
  });

  testWidgets('a recording without a note shows no link', (tester) async {
    await tester.runAsync(() async {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(id: 'e1', timestamp: DateTime(2026, 11)),
      );
    });
    await pump(tester, const Scaffold(body: HistoryNoteLink(entryId: 'e1')));

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsIdentifier('history-detail-note-link'),
      findsNothing,
    );
    semantics.dispose();
    await teardownTree(tester);
  });

  testWidgets('the note opens its recording', (tester) async {
    await tester.runAsync(() async {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(id: 'e1', timestamp: DateTime(2026, 11)),
      );
    });
    await pump(
      tester,
      const Scaffold(body: NoteSourceLink(sourceEntryId: 'e1')),
    );

    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsIdentifier('notes-editor-source-link'));
    await tester.pump();
    semantics.dispose();

    final container = containerOf(tester);
    expect(container.read(activePageProvider), 'history');
    expect(container.read(historyOpenEntryProvider), 'e1');
    await teardownTree(tester);
  });

  testWidgets('a note whose recording is gone shows no link', (tester) async {
    await pump(
      tester,
      const Scaffold(body: NoteSourceLink(sourceEntryId: 'gone')),
    );

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsIdentifier('notes-editor-source-link'),
      findsNothing,
    );
    semantics.dispose();
    await teardownTree(tester);
  });
}

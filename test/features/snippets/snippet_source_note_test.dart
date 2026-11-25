/// The back-reference of a snippet saved from a note (#664) names the note
/// the way the notes list does: an untitled note goes by its first line.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('an untitled source note is named by its first line', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final note = await db.createNote();
      await db.updateNoteContent(note.id, '\nAnfang der Notiz\nmehr Text');
      await db.upsertSnippet(
        id: 's1',
        title: 'Gruss',
        body: 'Anfang',
        createdAt: DateTime(2026),
        sourceNoteId: note.id,
      );
    });
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), db: db, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('snippets-item-s1'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final link = find.byKey(const ValueKey('snippets-editor-source-note'));
    expect(link, findsOneWidget);
    expect(
      find.descendant(
        of: link,
        matching: find.textContaining('Anfang der Notiz'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

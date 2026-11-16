/// While the History PIN locks the notes, no note text is shown anywhere on
/// the notes page, including the list. Quick-note capture only appends (it
/// does not depend on the page), so the gate is the only place to check.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';

const _secret = 'Geheimer Text der Notiz';

Note _note() {
  final t = DateTime(2026, 10, 18, 9);
  return Note(
    id: 'n1',
    content: _secret,
    createdAt: t,
    updatedAt: t,
    pinned: false,
    isQuickNote: true,
    deletedAt: null,
  );
}

Future<void> _pump(WidgetTester tester, {required bool locked}) async {
  await tester.pumpWidget(
    makeTestable(
      const NotesPage(),
      overrides: [
        historyContentHiddenProvider.overrideWithValue(locked),
        notesProvider.overrideWith((ref) => Stream.value([_note()])),
        allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
        noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
      ],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a locked notes page shows no note text', (tester) async {
    await _pump(tester, locked: true);
    expect(find.textContaining(_secret), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the same note is visible once the notes are unlocked', (
    tester,
  ) async {
    await _pump(tester, locked: false);
    expect(find.textContaining(_secret), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}

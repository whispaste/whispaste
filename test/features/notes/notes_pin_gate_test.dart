/// A History PIN also locks the notes (GS-149): the notes page shows the lock
/// screen while the history is hidden, and the normal page once it is not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets(
    'a PIN-locked history shows the lock screen instead of the notes',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            historyContentHiddenProvider.overrideWithValue(true),
            notesProvider.overrideWith((ref) => Stream.value(const [])),
            allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
            noteTagsProvider.overrideWith(
              (ref, noteId) => Stream.value(const []),
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsIdentifier('notes-pin-gate'), findsOneWidget);
      semantics.dispose();
      expect(find.text('Notes are locked'), findsOneWidget);
    },
  );

  testWidgets('without the lock the notes page is shown, not the lock screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        overrides: [
          historyContentHiddenProvider.overrideWithValue(false),
          notesProvider.overrideWith((ref) => Stream.value(const [])),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsIdentifier('notes-pin-gate'), findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

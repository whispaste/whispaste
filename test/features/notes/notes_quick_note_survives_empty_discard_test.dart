/// Pins the fix for the empty-discard rule's interaction with the quick
/// note: `NotesPage` deletes a note it is leaving when the note is blank
/// (`_leaveCurrentNote`/`dispose`), but the marked quick note must survive
/// even while blank — it is the pipeline's zero-config dictation target and
/// has to still be there the first time a dictation lands, not just after.
///
/// Uses the same real-db + widget-tree + recording-actions-subclass pattern
/// as `notes_autosave_wiring_test.dart`, since the point is exactly which
/// `NotesActions` method `NotesPage` reaches for — `discardIfBlank`, never
/// the unconditional `deleteForever` — not what the DB layer does in
/// isolation (already covered in `notes_db_test.dart`/`notes_actions_test.dart`).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';

import '../../fixtures/test_helpers.dart';

List<Object> get _noTagOverrides => [
  allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
  noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
];

Note _note({required String id, bool isQuickNote = false}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: '',
    pinned: false,
    isQuickNote: isQuickNote,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

/// Records which empty-discard method `NotesPage` reaches for, instead of
/// hitting the DB — the point under test is the call site, not the DB's own
/// (separately tested) exemption logic.
class _RecordingDiscardActions extends NotesActions {
  _RecordingDiscardActions(super.db);

  final List<String> calls = [];

  @override
  Future<bool> discardIfBlank(String noteId) async {
    calls.add('discardIfBlank:$noteId');
    return false;
  }

  @override
  Future<void> deleteForever(String noteId) async {
    calls.add('deleteForever:$noteId');
  }
}

void main() {
  testWidgets(
    'switching away from a blank marked quick note uses discardIfBlank, '
    'never the unconditional deleteForever',
    (tester) async {
      final notes = [_note(id: 'quick', isQuickNote: true), _note(id: 'other')];
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _RecordingDiscardActions(db);
      addTearDown(db.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          size: const Size(1800, 900),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Both list rows and the open editor panel render the same "Untitled
      // note" label, so a plain text finder can't tell them apart once a
      // note is open — scope the taps to each row's `ValueKey(note.id)`.
      await tester.tap(find.byKey(const ValueKey('quick')));
      await tester.pumpAndSettle();
      // Sanity check the tap opened the row it targeted, not the editor's
      // own copy of the same label.
      expect(find.byType(NotesListTile), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('other')));
      await tester.pumpAndSettle();

      expect(actions.calls, ['discardIfBlank:quick']);
      expect(
        actions.calls,
        isNot(contains('deleteForever:quick')),
        reason:
            'deleteForever is unconditional — routing the empty-discard '
            'trigger through it would delete the quick note before it is '
            'ever unmarked',
      );
    },
  );
}

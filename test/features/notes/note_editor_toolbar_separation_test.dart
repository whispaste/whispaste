/// Toolbar actions of the note editor are found by stable per-note keys.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('toolbar actions are found by stable per-note keys', (
    tester,
  ) async {
    final note = Note(
      id: 'n1',
      content: 'Eine Notiz',
      createdAt: DateTime(2026, 4, 14, 10, 30),
      updatedAt: DateTime(2026, 4, 14, 10, 30),
      pinned: false,
      isQuickNote: false,
    );
    final controller = TextEditingController(text: note.content);
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      makeTestable(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 640,
            height: 600,
            child: NoteEditorPanel(
              note: note,
              tags: const [],
              controller: controller,
              focusNode: focusNode,
              onClose: () {},
              onToggleFavorite: () {},
              onQuickNoteSet: () {},
              onQuickNoteClear: () {},
              onMoveToTrash: () {},
              onRestore: () {},
              onDeleteForever: () {},
              onAddTag: (_) {},
              onRemoveTag: (_) {},
              onDuplicate: () {},
              onExport: () {},
              onVoiceTranscript: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final action in ['duplicate', 'quicknote', 'trash', 'close']) {
      expect(
        find.byKey(ValueKey('notes-editor-$action-${note.id}')),
        findsOneWidget,
        reason: 'the $action action needs a stable key',
      );
    }
  });
}

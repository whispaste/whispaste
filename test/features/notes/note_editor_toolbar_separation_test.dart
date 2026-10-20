/// UX-003: the destructive "move to trash" action sat directly beside the
/// close (X) button, so a reach for close could delete the note. The two
/// must keep a visible gap in the normal (not trashed) toolbar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/widgets/wp_icon_button.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('move-to-trash and close keep a gap between them', (
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

    // Measure the tap targets, not the glyphs: a 24 dp icon centred in a
    // 48 dp button still leaves the two targets touching.
    Rect buttonOf(IconData icon) => tester.getRect(
      find
          .ancestor(of: find.byIcon(icon), matching: find.byType(WpIconButton))
          .first,
    );
    final trash = buttonOf(LucideIcons.trash2);
    final close = buttonOf(LucideIcons.x);
    expect(
      close.left - trash.right,
      greaterThanOrEqualTo(8),
      reason: 'the destructive trash action must not touch close',
    );
  });
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

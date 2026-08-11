/// Regression test for FLUTTER_WHISPASTE-64 — "RenderFlex overflowed by 3.7
/// pixels on the right" in [NoteEditorPanel]'s toolbar row.
///
/// The split view renders the editor panel from 280 dp upwards
/// (`_minDetailRenderWidth`) and animates its width on open/close, so the
/// toolbar sees narrow frames the user never gets to rest on. Its action
/// cluster is inflexible — a `Row` hands non-flex children unbounded width —
/// and measures a few dp more than the 24/12 inset leaves at that floor.
///
/// Pinned at the floor, below it, and at a comfortable width, and at an
/// accessibility text size.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';

import '../../fixtures/test_helpers.dart';

Note _note() => Note(
  id: 'n1',
  content: 'Eine Notiz mit einem ziemlich langen abgeleiteten Titel oben drin',
  createdAt: DateTime(2026, 4, 14, 10, 30),
  updatedAt: DateTime(2026, 4, 14, 10, 30),
  pinned: false,
  deletedAt: null,
);

Widget _panel({
  required bool trashed,
  required TextEditingController controller,
  required FocusNode focusNode,
}) => NoteEditorPanel(
  note: trashed
      ? _note().copyWith(deletedAt: Value(DateTime(2026, 4, 15)))
      : _note(),
  tags: const [],
  controller: controller,
  focusNode: focusNode,
  onClose: () {},
  onToggleFavorite: () {},
  onMoveToTrash: () {},
  onRestore: () {},
  onDeleteForever: () {},
  onAddTag: (_) {},
  onRemoveTag: (_) {},
  onExport: () {},
  onVoiceTranscript: (_) {},
);

void main() {
  // 280 is the split view's `_minDetailRenderWidth`; 240 is below anything it
  // renders, and stands in for the animation's narrow frames.
  for (final width in [240.0, 280.0, 320.0, 640.0]) {
    for (final trashed in [false, true]) {
      testWidgets('toolbar does not overflow at ${width}dp '
          '(${trashed ? 'trashed' : 'normal'} actions)', (tester) async {
        final controller = TextEditingController(text: _note().content);
        addTearDown(controller.dispose);
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          makeTestable(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 600,
                child: _panel(
                  trashed: trashed,
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('toolbar does not overflow at the render floor with a 1.5x text '
      'scaler', (tester) async {
    final controller = TextEditingController(text: _note().content);
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                height: 600,
                child: _panel(
                  trashed: false,
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

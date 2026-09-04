/// The Notes editor is **one** surface (Ticket 16).
///
/// Ticket 09 moved the `bare` variant onto the card material and, in the same
/// move, deleted the `DecoratedBox(gradient: surfaceGradient)` this panel used
/// to paint around it — the field now *is* the writing surface, and a panel
/// ground under a field ground would stack two frost layers, which measures
/// `textMuted` at 4.43:1 over the lightest ambient stop (below AA) where one
/// layer measures 4.76:1. Ticket 16 asked for that decision to be re-checked
/// rather than assumed, and this is the check made executable: nothing between
/// the panel's root and its field may paint a surface of its own.
///
/// Written as an ancestor walk instead of a source grep so it also catches the
/// wrapper coming back in some other shape — a `Container(color:)`, a
/// `Material`, a second card token — rather than only the exact expression
/// that was removed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

Note _note() => Note(
  id: 'n1',
  content: 'Ein Notiztext, lang genug um die Schreibfläche zu füllen.',
  createdAt: DateTime(2026, 4, 14, 10, 30),
  updatedAt: DateTime(2026, 4, 14, 10, 30),
  pinned: false,
  isQuickNote: false,
  deletedAt: null,
);

Widget _panel({
  required TextEditingController controller,
  required FocusNode focusNode,
}) => NoteEditorPanel(
  note: _note(),
  tags: const [],
  controller: controller,
  focusNode: focusNode,
  onClose: () {},
  onDuplicate: () {},
  onToggleFavorite: () {},
  onQuickNoteSet: () {},
  onQuickNoteClear: () {},
  onMoveToTrash: () {},
  onRestore: () {},
  onDeleteForever: () {},
  onAddTag: (_) {},
  onRemoveTag: (_) {},
  onExport: () {},
  onVoiceTranscript: (_) {},
);

/// Every fill a single widget paints, gradients included.
Iterable<Color> _paintedFills(Widget w) sync* {
  if (w is DecoratedBox) {
    if (w.decoration case final BoxDecoration d) {
      if (d.color != null) yield d.color!;
      if (d.gradient case final Gradient g) yield* g.colors;
    }
  } else if (w is ColoredBox) {
    yield w.color;
  } else if (w is Material) {
    if (w.color != null) yield w.color!;
  }
}

void main() {
  testWidgets('nothing paints a surface between the panel and its field', (
    tester,
  ) async {
    final controller = TextEditingController(text: _note().content);
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      makeTestable(
        SizedBox(
          width: 640,
          height: 600,
          child: _panel(controller: controller, focusNode: focusNode),
        ),
      ),
    );
    await tester.pump();

    final field = find.byType(WpTextField);
    expect(
      tester.widget<WpTextField>(field).variant,
      WpTextFieldVariant.bare,
      reason:
          'the editor is the `bare` field — the variant that *is* the '
          'surface. A different one here changes what this test means.',
    );

    // Walk from the field up to the panel, collecting everything painted on
    // the way. The panel itself is the ceiling: what the *page* stands on is
    // not this panel's business (One-Atmosphere Rule — the ambient is the
    // app's, and it shows through the field).
    final stacked = <String>[];
    tester.element(field).visitAncestorElements((ancestor) {
      if (ancestor.widget is NoteEditorPanel) return false;
      for (final color in _paintedFills(ancestor.widget)) {
        if (color.a == 0) continue; // painted nothing
        stacked.add('${ancestor.widget.runtimeType} → $color');
      }
      return true;
    });

    expect(
      stacked,
      isEmpty,
      reason:
          'A surface under the Notes editor stacks a second frost layer under '
          'the one the `bare` field already paints — card on card, which is '
          'the "Fläche auf einer Fläche" this panel was cleared of, and which '
          'drops the placeholder below AA. Found: ${stacked.join(', ')}',
    );
  });

  testWidgets('the field itself still carries the card material', (
    tester,
  ) async {
    final controller = TextEditingController(text: _note().content);
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      makeTestable(
        SizedBox(
          width: 640,
          height: 600,
          child: _panel(controller: controller, focusNode: focusNode),
        ),
      ),
    );
    await tester.pump();

    // The other half of the decision: the wrapper could only *go* because the
    // field brought a surface of its own. Without this, the test above would
    // pass just as happily on a panel with no material anywhere.
    final box = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(WpTextField),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((box.decoration! as BoxDecoration).color, WpColors.cardFill);
  });
}

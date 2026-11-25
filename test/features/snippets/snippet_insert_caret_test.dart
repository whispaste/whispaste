// Inserting a Textbaustein from inside an editor (#664): focus coming back
// from the chooser keeps the caret. Without the hand-over the editor's
// keyboard-focus rule (#1498) moved it to the end, so a cancelled chooser
// lost the position and typing after an insert landed at the end of the
// text (found on Ubuntu with another app).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

class _OneSnippet extends SnippetsNotifier {
  @override
  Future<List<SnippetItem>> build() async => [
    SnippetItem(
      id: 's1',
      title: 'Gruss',
      body: 'Gruss ',
      createdAt: DateTime(2026),
    ),
  ];

  @override
  Future<void> recordUse(String id) async {}
}

Future<void> _openChooser(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
  expect(find.bySemanticsIdentifier('snippet-insert-search'), findsOneWidget);
}

void main() {
  testWidgets('the caret stays put after cancel and follows the insert', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Anfang Ende');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      makeTestable(
        Material(
          child: Consumer(
            builder: (context, ref, _) => WpTextEditor(
              testId: 'probe',
              controller: controller,
              focusNode: focusNode,
              // Multi-line like the note editor: Flutter selects all on
              // focus only in single-line fields.
              variant: WpTextFieldVariant.bare,
              onInsertSnippet: () => insertSnippetAtCursor(
                context: context,
                ref: ref,
                controller: controller,
                focusNode: focusNode,
              ),
            ),
          ),
        ),
        overrides: [snippetsProvider.overrideWith(_OneSnippet.new)],
      ),
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();

    await _openChooser(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 7));

    await _openChooser(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'Anfang Gruss Ende');
    expect(focusNode.hasFocus, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 13));

    // The hand-over is spent: plain keyboard focus moves to the end again.
    focusNode.unfocus();
    await tester.pump();
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      TextSelection.collapsed(offset: controller.text.length),
    );
  }, variant: TargetPlatformVariant.desktop());
}

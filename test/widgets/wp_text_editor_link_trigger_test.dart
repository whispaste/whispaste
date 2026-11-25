/// Typing `[[` in the editor block opens the link chooser (#660); the chosen
/// link replaces the two brackets as one undo step, and nothing but typing
/// opens it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/text_undo.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late int asked;
  String? answer;

  setUp(() {
    controller = TextEditingController(text: 'See [')
      ..selection = const TextSelection.collapsed(offset: 5);
    focusNode = FocusNode();
    asked = 0;
    answer = '[[note:n-1|Meeting]]';
  });
  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(
        Material(
          child: WpTextEditor(
            testId: 'probe',
            controller: controller,
            focusNode: focusNode,
            variant: WpTextFieldVariant.form,
            minLines: 3,
            maxLines: 5,
            onPickLink: () async {
              asked++;
              return answer;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the second typed bracket asks and inserts the link', (
    tester,
  ) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    controller.value = const TextEditingValue(
      text: 'See [[',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(controller.text, 'See [[note:n-1|Meeting]]');
    expect(controller.selection.extentOffset, controller.text.length);

    // One undo step takes the link back to the typed brackets.
    TextUndoController.of(controller)?.undo();
    await tester.pump();
    expect(controller.text, 'See [[');
  });

  testWidgets('cancelling keeps the brackets', (tester) async {
    answer = null;
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    controller.value = const TextEditingValue(
      text: 'See [[',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(controller.text, 'See [[');
  });

  testWidgets('pasted brackets do not ask', (tester) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    controller.value = const TextEditingValue(
      text: 'See [x [[',
      selection: TextSelection.collapsed(offset: 9),
    );
    await tester.pumpAndSettle();
    expect(asked, 0);
  });
}

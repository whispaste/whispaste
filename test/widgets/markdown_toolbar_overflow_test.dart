/// The formatting bar stays one line on any width (#1845): on a short,
/// narrow editor (Notes at 800x600) the wrapped bar took four rows and left
/// no height for the text. What does not fit moves into a "More" menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/text_undo.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';

import '../fixtures/test_helpers.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  final controller = TextEditingController(text: 'abc');
  final focus = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  final undo = TextUndoController(controller);
  addTearDown(undo.dispose);
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: WpMarkdownToolbar(
            controller: controller,
            focusNode: focus,
            testIdPrefix: 't',
            undoController: undo,
          ),
        ),
      ),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}

final _bar = find.byType(WpMarkdownToolbar);

void main() {
  testWidgets('a narrow bar is one line and offers the rest under More', (
    tester,
  ) async {
    await _pump(tester, 300);
    expect(tester.getSize(_bar).height, lessThanOrEqualTo(48));
    expect(find.byTooltip('More'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('t-toolbar-more-text-view')),
      findsOneWidget,
      reason: 'the last button is reachable from the menu',
    );
  });

  testWidgets('a wide bar shows every button and no More', (tester) async {
    await _pump(tester, 1200);
    expect(tester.getSize(_bar).height, lessThanOrEqualTo(48));
    expect(find.byTooltip('More'), findsNothing);
  });
}

/// The one editor context menu (#650, #670): spell suggestions first, then
/// the platform's entries, then the Smart Mode actions with their testIDs.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/editor_smart_action.dart';
import 'package:whispaste/widgets/editor_smart_action_scope.dart';

import '../fixtures/test_helpers.dart';

final _desktop = TargetPlatformVariant.desktop();

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController(text: 'helo world')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    focusNode = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> openMenu(
    WidgetTester tester, {
    List<String> leading = const [],
    ValueChanged<EditorSmartAction>? onSmartAction,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        Material(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            contextMenuBuilder: (context, editable) => editorContextMenu(
              context,
              editable,
              leading: [
                for (final label in leading)
                  ContextMenuButtonItem(label: label, onPressed: () {}),
              ],
              onSmartAction: onSmartAction,
              testIdPrefix: 'probe',
            ),
          ),
        ),
      ),
    );
    // A right click, as on the desktop.
    await tester.tapAt(
      tester.getTopLeft(find.byType(TextField)) + const Offset(8, 8),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'spell entries lead, Smart Mode actions follow',
    variant: _desktop,
    (tester) async {
      EditorSmartAction? picked;
      await openMenu(
        tester,
        leading: ['hello'],
        onSmartAction: (a) => picked = a,
      );

      final smart = find.text('Smart Mode: Cleanup');
      expect(smart, findsOneWidget);
      // The desktop menu is one column: the suggestion comes first.
      expect(
        tester.getTopLeft(find.text('hello')).dy,
        lessThan(tester.getTopLeft(smart).dy),
      );
      expect(
        find.bySemanticsIdentifier('probe-context-smart-cleanUp'),
        findsOneWidget,
      );

      await tester.tap(smart);
      await tester.pump();
      expect(picked, EditorSmartAction.cleanUp);
    },
  );

  testWidgets(
    'without Smart Mode only the spell entries are added',
    variant: _desktop,
    (tester) async {
      await openMenu(tester, leading: ['hello']);

      expect(find.text('hello'), findsOneWidget);
      expect(find.textContaining('Smart Mode:'), findsNothing);
      expect(
        find.bySemanticsIdentifier('probe-context-smart-cleanUp'),
        findsNothing,
      );
    },
  );
}

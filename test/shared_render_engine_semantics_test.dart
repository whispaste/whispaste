/// Floating button and overlay for assistive tech (#1923): the surface is a
/// button that can be pressed, and the overlay's painted cancel X is a node
/// of its own with its own name and action.
library;

import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/shared_render_engine_helpers.dart';

void main() {
  Widget layer({
    required VoidCallback onTap,
    RenderEngineSecondaryAction? secondary,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: RenderEngineGestureLayer(
      semanticsLabel: 'Recording overlay',
      onTap: onTap,
      onPanStart: () {},
      onSecondaryOrLongPress: () {},
      secondaryAction: secondary,
      child: const SizedBox(width: 200, height: 40),
    ),
  );

  testWidgets('the surface is a button assistive tech can press', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(layer(onTap: () => taps++));

    final node = tester.getSemantics(
      find.bySemanticsLabel('Recording overlay'),
    );
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('Recording overlay'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('the cancel control is a separate node with its own action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var body = 0;
    var cancel = 0;
    await tester.pumpWidget(
      layer(
        onTap: () => body++,
        secondary: RenderEngineSecondaryAction(
          rect: const Rect.fromLTWH(170, 8, 24, 24),
          label: 'Cancel recording',
          onTap: () => cancel++,
        ),
      ),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('Cancel recording'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, 'Cancel recording');
    expect(node.rect.size, const Size(24, 24));
    tester.semantics.tap(find.semantics.byLabel('Cancel recording'));
    expect(cancel, 1);
    expect(body, 0);

    // A pointer click outside the X still reaches the surface.
    await tester.tapAt(const Offset(20, 20));
    expect(body, 1);
    handle.dispose();
  });
}

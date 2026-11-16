import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('a disabled toggle takes keyboard focus and names its reason', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: settingsToggle(
            label: 'Show timer',
            testId: 'disabled-toggle',
            value: false,
            onChanged: null,
            disabledReason: 'Not drawn at this size',
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    expect(
      find.descendant(
        of: find.byType(WpFocusRing),
        matching: find.byType(Switch),
      ),
      findsOneWidget,
    );
    expect(
      focus!.context!.findAncestorWidgetOfExactType<WpFocusRing>(),
      isNotNull,
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Show timer'));
    expect(node.hint, 'Not drawn at this size');
    // Space on a disabled toggle changes nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    semantics.dispose();
  });

  testWidgets('a disabled toggle without a reason takes no focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: settingsToggle(label: 'Hold', value: false, onChanged: null),
        ),
      ),
    );
    expect(find.byType(WpFocusRing), findsNothing);
  });

  testWidgets('an enabled toggle toggles by keyboard and carries no hint', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var value = false;
    await tester.pumpWidget(
      makeTestable(
        StatefulBuilder(
          builder: (context, setState) => settingsToggle(
            label: 'Quiet hint',
            value: value,
            onChanged: (v) => setState(() => value = v),
            disabledReason: 'ignored while enabled',
          ),
        ),
      ),
    );
    expect(find.byType(WpFocusRing), findsNothing);
    expect(tester.getSemantics(find.bySemanticsLabel('Quiet hint')).hint, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(value, isTrue);
    semantics.dispose();
  });
}

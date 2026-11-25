/// A dock selector drops its accent outline as soon as focus leaves it, so
/// two dock controls never look focused at once (#1845).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/recording_dock_controls.dart';
import 'package:whispaste/widgets/recording_dock_layout.dart';

import '../fixtures/test_helpers.dart';

double _outlineWidth(WidgetTester tester, String id) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byKey(ValueKey('chrome-$id')),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  final border = (box.decoration as BoxDecoration).border! as Border;
  return border.top.width;
}

void main() {
  testWidgets('the outline follows focus away', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    Widget selector(String id) => SizedBox(
      key: ValueKey('chrome-$id'),
      width: 180,
      height: 40,
      child: WpDockSelector(
        id: id,
        form: WpDockSelectorForm.values.first,
        icon: LucideIcons.globe,
        overline: id,
        value: id,
        onTap: () {},
      ),
    );
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [selector('a'), selector('b')],
          ),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focusedWidth = _outlineWidth(tester, 'a');
    expect(focusedWidth, greaterThan(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_outlineWidth(tester, 'a'), 1);
    expect(_outlineWidth(tester, 'b'), focusedWidth);
  });
}

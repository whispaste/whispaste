import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';
import 'package:whispaste/widgets/side_panel/side_panel_view.dart';

import '../../fixtures/test_helpers.dart';

const _snapshot = SidePanelSnapshot(
  transcriptions: [
    SidePanelRow(id: 't1', title: 'First recording'),
    SidePanelRow(id: 't2', title: 'Second recording'),
  ],
);

/// Tab from the start of the panel until a row holds the focus. The header
/// and tab bar come first in traversal order, so this is the keyboard path
/// a user takes, not a direct focus request.
Future<void> _tabToFirstRow(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    if (FocusManager.instance.primaryFocus?.debugLabel ==
        'WpSidePanelRowTile') {
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('no row received the focus by Tab');
}

void main() {
  testWidgets('Tab reaches a row, arrow down moves on, Enter activates it', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      makeTestable(
        WpSidePanelView(
          snapshot: _snapshot,
          onRowTap: (section, id) => tapped.add(id),
          onClose: () {},
        ),
      ),
    );

    await _tabToFirstRow(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tapped, ['t2']);
  });

  testWidgets('Escape closes the panel while a row has the focus', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      makeTestable(
        WpSidePanelView(
          snapshot: _snapshot,
          onRowTap: (_, _) {},
          onClose: () => closed++,
        ),
      ),
    );

    await _tabToFirstRow(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closed, 1);
  });
}

/// Keyboard order of the app shell (#1845): Tab finishes the sidebar before
/// it enters the page, and a page opened by shortcut takes focus at its
/// first control instead of leaving it on the sidebar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/app_shell.dart';
import 'package:whispaste/widgets/focus_first_in.dart';

final _nodes = <String, FocusNode>{};

Widget _button(String label, double top) => Padding(
  padding: EdgeInsets.only(top: top),
  child: TextButton(
    focusNode: _nodes.putIfAbsent(label, () => FocusNode(debugLabel: label)),
    onPressed: () {},
    child: Text(label),
  ),
);

String? _focusedLabel(WidgetTester tester) =>
    FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  tearDown(() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _nodes.clear();
  });

  testWidgets('Tab walks the whole sidebar before the page', (tester) async {
    // Sidebar entries at 0, 80, 160 px; the page's first control sits at
    // 40 px, between the first two entries. Reading order without groups
    // would interleave them.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WpAppShell(
            titleBar: const SizedBox(height: 10),
            sidebar: SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _button('s1', 0),
                  _button('s2', 40),
                  _button('s3', 40),
                ],
              ),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_button('c1', 40), _button('c2', 40)],
            ),
            dock: const SizedBox(height: 10),
            contentDecoration: const BoxDecoration(),
          ),
        ),
      ),
    );
    _nodes['s1']!.requestFocus();
    await tester.pump();
    final order = <String?>[_focusedLabel(tester)];
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(_focusedLabel(tester));
    }
    expect(order, ['s1', 's2', 's3', 'c1', 'c2']);
  });

  testWidgets('Tab finishes the page before the dock, even below it', (
    tester,
  ) async {
    // The page scrolls: c3 and c4 lie below the dock on screen. Reading
    // order without region groups would put the dock between c2 and c3.
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WpAppShell(
            titleBar: _button('t1', 0),
            sidebar: SizedBox(width: 60, child: _button('s1', 0)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _button('c1', 0),
                  _button('c2', 60),
                  _button('c3', 120),
                  _button('c4', 120),
                ],
              ),
            ),
            dock: _button('d1', 0),
            contentDecoration: const BoxDecoration(),
          ),
        ),
      ),
    );
    _nodes['t1']!.requestFocus();
    await tester.pump();
    final order = <String?>[_focusedLabel(tester)];
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(_focusedLabel(tester));
    }
    expect(order, ['t1', 's1', 'c1', 'c2', 'c3', 'c4', 'd1']);
  });

  testWidgets('focusFirstIn picks the top-start control of the area', (
    tester,
  ) async {
    final area = FocusNode(skipTraversal: true);
    addTearDown(area.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _button('outside', 0),
              Focus(
                focusNode: area,
                skipTraversal: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [_button('first', 20), _button('second', 20)],
                    ),
                    _button('third', 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(focusFirstIn(area), isTrue);
    await tester.pump();
    expect(_focusedLabel(tester), 'first');
  });

  testWidgets('focusFirstIn leaves focus alone in an empty area', (
    tester,
  ) async {
    final area = FocusNode(skipTraversal: true);
    addTearDown(area.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: area, child: const Text('no controls')),
      ),
    );
    expect(focusFirstIn(area), isFalse);
  });
}

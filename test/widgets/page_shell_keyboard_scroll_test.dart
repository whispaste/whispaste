/// Pages scroll by keyboard (#1845): Page Down/Up and Ctrl+End work while
/// focus is in the page, and a page without controls is a Tab stop itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/page_shell.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';

ScrollPosition _page(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

double _offset(WidgetTester tester) => _page(tester).pixels;

Widget _host({required Widget page, FocusNode? outside}) => MaterialApp(
  home: Scaffold(
    body: Row(
      children: [
        SizedBox(
          width: 80,
          child: TextButton(
            focusNode: outside,
            onPressed: () {},
            child: const Text('nav'),
          ),
        ),
        Expanded(child: WpPageShell(child: page)),
      ],
    ),
  ),
);

void main() {
  testWidgets('a page without controls is reached by Tab and scrolls', (
    tester,
  ) async {
    final nav = FocusNode(debugLabel: 'nav');
    addTearDown(nav.dispose);
    await tester.pumpWidget(
      _host(
        outside: nav,
        page: Column(
          children: [for (var i = 0; i < 30; i++) const SizedBox(height: 100)],
        ),
      ),
    );
    await tester.pump();
    nav.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'page-scroll-region',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(_offset(tester), greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    final pos = _page(tester);
    expect(pos.pixels, pos.maxScrollExtent);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(_offset(tester), 0);
  });

  testWidgets('the focused region marks focus with its scroll bar, no frame', (
    tester,
  ) async {
    final nav = FocusNode(debugLabel: 'nav');
    addTearDown(nav.dispose);
    await tester.pumpWidget(
      _host(
        outside: nav,
        page: Column(
          children: [for (var i = 0; i < 30; i++) const SizedBox(height: 100)],
        ),
      ),
    );
    await tester.pump();
    Scrollbar bar() => tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar().thumbVisibility, isNot(true));
    nav.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byType(WpFocusRing), findsNothing);
    expect(bar().thumbVisibility, isTrue);
  });

  testWidgets('a page without controls and nothing to scroll is no Tab stop', (
    tester,
  ) async {
    final nav = FocusNode(debugLabel: 'nav');
    addTearDown(nav.dispose);
    await tester.pumpWidget(
      _host(outside: nav, page: const SizedBox(height: 100)),
    );
    await tester.pump();
    nav.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('page-scroll-region'),
    );
  });

  testWidgets('Page Down scrolls while a control in the page has focus', (
    tester,
  ) async {
    final button = FocusNode(debugLabel: 'b');
    addTearDown(button.dispose);
    await tester.pumpWidget(
      _host(
        page: Column(
          children: [
            TextButton(
              focusNode: button,
              onPressed: () {},
              child: const Text('b'),
            ),
            for (var i = 0; i < 30; i++) const SizedBox(height: 100),
          ],
        ),
      ),
    );
    await tester.pump();
    button.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(_offset(tester), greaterThan(0));
    expect(FocusManager.instance.primaryFocus, button);
  });

  testWidgets('a text field keeps Page Down for itself', (tester) async {
    final field = FocusNode(debugLabel: 'f');
    addTearDown(field.dispose);
    await tester.pumpWidget(
      _host(
        page: Column(
          children: [
            TextField(focusNode: field),
            for (var i = 0; i < 30; i++) const SizedBox(height: 100),
          ],
        ),
      ),
    );
    field.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(_offset(tester), 0);
  });
}

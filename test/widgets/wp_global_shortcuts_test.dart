/// App-wide shortcuts fire once, whether focus is inside the shell or
/// nowhere at all (after a click on a sidebar item, #1845).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_global_shortcuts.dart';

void main() {
  Future<int Function()> pump(WidgetTester tester, FocusNode inner) async {
    var hits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WpGlobalShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f1): () => hits++,
          },
          child: Focus(focusNode: inner, child: const SizedBox()),
        ),
      ),
    );
    return () => hits;
  }

  testWidgets('F1 fires once with focus inside', (tester) async {
    final inner = FocusNode();
    addTearDown(inner.dispose);
    final hits = await pump(tester, inner);
    inner.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    expect(hits(), 1);
  });

  testWidgets('F1 fires once with no focus inside the app', (tester) async {
    final inner = FocusNode();
    addTearDown(inner.dispose);
    final hits = await pump(tester, inner);
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.rootScope.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    expect(hits(), 1);
  });
}

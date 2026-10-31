/// The keys that open the Help hub from anywhere in the app (WP-78).
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/help/help_shortcuts.dart';

void main() {
  testWidgets('F1 opens help', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: helpShortcuts(() => opened++),
          child: const Focus(autofocus: true, child: SizedBox()),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('Cmd/Ctrl+? opens help', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: helpShortcuts(() => opened++),
          child: const Focus(autofocus: true, child: SizedBox()),
        ),
      ),
    );
    await tester.pump();

    // The shortcut is Cmd on macOS and Ctrl elsewhere; the test host decides.
    final modifier = Platform.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();

    expect(opened, 1);
  });
}

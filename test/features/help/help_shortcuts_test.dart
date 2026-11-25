/// The keys that open the Help hub from anywhere in the app (ticket).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
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

  /// Whether a binding accepts a Cmd/Ctrl+Shift+[key] press. Checked on the
  /// activators directly: the key simulator has no physical mapping for
  /// layout keys such as logical "?" or "ß".
  bool opensHelp({
    required LogicalKeyboardKey key,
    required PhysicalKeyboardKey physical,
    String? character,
  }) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final keyboard = HardwareKeyboard();
    const stamp = Duration.zero;
    final modifiers = [
      (
        isMac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
        isMac ? PhysicalKeyboardKey.metaLeft : PhysicalKeyboardKey.controlLeft,
      ),
      (LogicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftLeft),
    ];
    for (final (logical, phys) in modifiers) {
      keyboard.handleKeyEvent(
        KeyDownEvent(physicalKey: phys, logicalKey: logical, timeStamp: stamp),
      );
    }
    final event = KeyDownEvent(
      physicalKey: physical,
      logicalKey: key,
      character: character,
      timeStamp: stamp,
    );
    keyboard.handleKeyEvent(event);
    return helpShortcuts(() {}).keys.any((a) => a.accepts(event, keyboard));
  }

  test('Cmd/Ctrl+? opens help when the key arrives as question '
      '(Linux, #1845)', () {
    expect(
      opensHelp(
        key: LogicalKeyboardKey.question,
        physical: PhysicalKeyboardKey.slash,
        character: '?',
      ),
      isTrue,
    );
  });

  test('Cmd/Ctrl+? opens help on a German layout (Shift+ß types ?)', () {
    expect(
      opensHelp(
        key: const LogicalKeyboardKey(0x000000df),
        physical: PhysicalKeyboardKey.minus,
        character: '?',
      ),
      isTrue,
    );
  });

  test('Ctrl+Shift+ß opens help on Windows, where Ctrl suppresses the '
      'character (#1845)', () {
    expect(
      opensHelp(
        key: const LogicalKeyboardKey(0x000000df),
        physical: PhysicalKeyboardKey.minus,
      ),
      isTrue,
    );
  });

  test('Ctrl+Shift+ß opens help with the values Windows really sends: '
      'logical bracketLeft on physical Minus, no character (#1931)', () {
    expect(
      opensHelp(
        key: LogicalKeyboardKey.bracketLeft,
        physical: PhysicalKeyboardKey.minus,
      ),
      isTrue,
    );
    // US Ctrl+Shift+[ sits on the physical BracketLeft key: no Help.
    expect(
      opensHelp(
        key: LogicalKeyboardKey.bracketLeft,
        physical: PhysicalKeyboardKey.bracketLeft,
      ),
      isFalse,
    );
  });

  /// Whether a plain Shift+[key] press opens a view's shortcut overview.
  bool opensOverview({
    required LogicalKeyboardKey key,
    required PhysicalKeyboardKey physical,
    String? character,
  }) {
    final keyboard = HardwareKeyboard();
    const stamp = Duration.zero;
    keyboard.handleKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: stamp,
      ),
    );
    final event = KeyDownEvent(
      physicalKey: physical,
      logicalKey: key,
      character: character,
      timeStamp: stamp,
    );
    keyboard.handleKeyEvent(event);
    return shortcutOverviewKeys(
      () {},
    ).keys.any((a) => a.accepts(event, keyboard));
  }

  test('? opens a shortcut overview on US, Linux and German layouts', () {
    expect(
      opensOverview(
        key: LogicalKeyboardKey.slash,
        physical: PhysicalKeyboardKey.slash,
        character: '?',
      ),
      isTrue,
    );
    expect(
      opensOverview(
        key: LogicalKeyboardKey.question,
        physical: PhysicalKeyboardKey.slash,
        character: '?',
      ),
      isTrue,
    );
    // German layout: Shift+ß types "?" (#1845).
    expect(
      opensOverview(
        key: const LogicalKeyboardKey(0x000000df),
        physical: PhysicalKeyboardKey.minus,
        character: '?',
      ),
      isTrue,
    );
  });

  test('the recording detail uses the shared overview keys', () {
    final src = File(
      'lib/features/history/widgets/history_detail_panel.dart',
    ).readAsStringSync();
    expect(src, contains('shortcutOverviewKeys('));
    expect(src, isNot(contains('LogicalKeyboardKey.slash, shift: true')));
  });
}

/// The shared editor block (#638): the contract History, Notes and Snippets
/// rely on — one save key, one undo history behind the shortcut and the
/// toolbar button, and a read mode that keeps the bar but disables it.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_save_status.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

Future<void> _pressCommand(WidgetTester tester, LogicalKeyboardKey key) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    // A valid selection, as a real field has once shown: UndoHistory only
    // records values with one, so 'hello' becomes the first undo step.
    controller = TextEditingController(text: 'hello')
      ..selection = const TextSelection.collapsed(offset: 5);
    focusNode = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool editable = true,
    VoidCallback? onSave,
    ValueListenable<WpSaveStatus>? saveStatus,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        Material(
          child: WpTextEditor(
            testId: 'probe',
            controller: controller,
            focusNode: focusNode,
            variant: WpTextFieldVariant.form,
            editable: editable,
            onSave: onSave,
            saveStatus: saveStatus,
            minLines: 3,
            maxLines: 5,
            readView: const Text('read', key: ValueKey('probe-read')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('save is bound only when the surface has something to save', () {
    final without = WpTextEditor.shortcutBindings(
      controller: controller,
      focusNode: focusNode,
    );
    expect(without.containsKey(WpTextEditor.saveActivator), isFalse);

    var saved = 0;
    final withSave = WpTextEditor.shortcutBindings(
      controller: controller,
      focusNode: focusNode,
      onSave: () => saved++,
    );
    withSave[WpTextEditor.saveActivator]!();
    expect(saved, 1);
    // Formatting keys are identical with and without a save target.
    expect(
      withSave.keys.where((k) => k != WpTextEditor.saveActivator).toSet(),
      without.keys.toSet(),
    );
  });

  testWidgets('Ctrl/Cmd+S in the field calls onSave', (tester) async {
    var saved = 0;
    await pump(tester, onSave: () => saved++);
    focusNode.requestFocus();
    await tester.pump();

    await _pressCommand(tester, LogicalKeyboardKey.keyS);
    expect(saved, 1);
  });

  testWidgets('the toolbar undo button reverts the same history as typing', (
    tester,
  ) async {
    await pump(tester);
    // UndoHistory's throttle is trailing-only: the initial value lands after
    // 500 ms, and a change inside that window would replace it.
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(WpTextField), 'hello world');
    await tester.pumpAndSettle();
    // UndoHistory throttles; let the change land as its own step.
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.bySemanticsIdentifier('probe-toolbar-undo'));
    await tester.pumpAndSettle();
    expect(controller.text, 'hello');

    await tester.tap(find.bySemanticsIdentifier('probe-toolbar-redo'));
    await tester.pumpAndSettle();
    expect(controller.text, 'hello world');
  });

  testWidgets('read mode keeps the bar, disabled, and shows the read view', (
    tester,
  ) async {
    await pump(tester, editable: false, onSave: () {});

    expect(find.byType(WpTextField), findsNothing);
    expect(find.byKey(const ValueKey('probe-read')), findsOneWidget);
    expect(find.bySemanticsIdentifier('probe-toolbar'), findsOneWidget);
    final bold = tester.getSemantics(
      find.bySemanticsIdentifier('probe-toolbar-bold'),
    );
    // The button is one merged node (#652); its flags live in the merged
    // data a screen reader reads, not on the boundary node itself.
    expect(bold.getSemanticsData().flagsCollection.isEnabled, Tristate.isFalse);
    // No save hint outside editing: there is nothing to save.
    expect(find.bySemanticsIdentifier('probe-save-hint'), findsNothing);
  });

  // F-save-status-hint: one save message at a time in the status line.
  testWidgets('the save status replaces the save hint once it leaves idle', (
    tester,
  ) async {
    final status = ValueNotifier(WpSaveStatus.idle);
    addTearDown(status.dispose);
    await pump(tester, onSave: () {}, saveStatus: status);
    expect(find.bySemanticsIdentifier('probe-save-hint'), findsOneWidget);

    status.value = WpSaveStatus.saved;
    await tester.pump();
    expect(find.bySemanticsIdentifier('probe-save-hint'), findsNothing);
    expect(
      find.byKey(const ValueKey('probe-save-status-saved')),
      findsOneWidget,
    );
  });

  // F-caret-edit-mode: typing after focusing landed in the middle of the
  // text. Keyboard focus puts the caret at the end; a click keeps its spot.
  testWidgets('keyboard focus puts the caret at the end of the text', (
    tester,
  ) async {
    controller.selection = const TextSelection.collapsed(offset: 0);
    await pump(tester);

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('a click keeps the caret where it was clicked', (tester) async {
    controller.text = 'hello world';
    await pump(tester);

    final field = find.byType(TextField);
    final box = tester.getRect(field);
    // Far left of the first line: the caret must land near the start, not at
    // the end the keyboard-focus rule would pick.
    await tester.tapAt(Offset(box.left + 14, box.top + 20));
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, lessThan(controller.text.length));
  });
}

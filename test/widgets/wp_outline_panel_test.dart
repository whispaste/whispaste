// The editor outline (#645): the panel lists the headings, a choice puts
// the caret at the heading and the focus back in the text, the keys step
// from heading to heading, and the list follows typing after a pause.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/widgets/wp_outline_panel.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

const _text = 'Lead\n# Intro\nfirst\n## Detail\nsecond\n# Close\nend';

final _l10n = L10nEn();

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(primaryShortcutModifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyUpEvent(primaryShortcutModifier);
  await tester.pump();
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController(text: _text)
      ..selection = const TextSelection.collapsed(offset: 0);
    focusNode = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pump(WidgetTester tester, {bool editable = true}) async {
    await tester.pumpWidget(
      makeTestable(
        Material(
          child: WpTextEditor(
            testId: 'probe',
            controller: controller,
            focusNode: focusNode,
            variant: WpTextFieldVariant.form,
            editable: editable,
            minLines: 3,
            maxLines: 8,
            readView: const Text('read'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder item(int n) => find.bySemanticsIdentifier('probe-outline-item-$n');

  testWidgets('the toolbar button lists every heading; a choice jumps', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(WpOutlinePanel), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('probe-toolbar-outline'));
    await tester.pumpAndSettle();

    expect(find.byType(WpOutlinePanel), findsOneWidget);
    expect(item(0), findsOneWidget);
    expect(item(1), findsOneWidget);
    expect(item(2), findsOneWidget);
    expect(item(3), findsNothing);

    await tester.tap(item(1));
    await tester.pumpAndSettle();

    final detailEnd = _text.indexOf('## Detail') + '## Detail'.length;
    expect(controller.selection, TextSelection.collapsed(offset: detailEnd));
    expect(focusNode.hasFocus, isTrue);
    // The panel stays open for the next jump.
    expect(find.byType(WpOutlinePanel), findsOneWidget);
  });

  testWidgets('the outline key focuses the heading at the caret; arrows, '
      'Enter and Escape work in the list', (tester) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    controller.selection = TextSelection.collapsed(
      offset: _text.indexOf('second'),
    );
    await tester.pump();

    await _chord(tester, LogicalKeyboardKey.keyG, shift: true);
    await tester.pumpAndSettle();
    expect(find.byType(WpOutlinePanel), findsOneWidget);
    expect(focusNode.hasFocus, isFalse);
    final focusedLabel = FocusManager.instance.primaryFocus?.debugLabel;
    expect(focusedLabel, 'OutlineItem 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'OutlineItem 2');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      TextSelection.collapsed(offset: _text.indexOf('# Close') + 7),
    );
    expect(focusNode.hasFocus, isTrue);

    // Escape from the list: back to the text, caret kept, panel open.
    await _chord(tester, LogicalKeyboardKey.keyG, shift: true);
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
    expect(
      controller.selection,
      TextSelection.collapsed(offset: _text.indexOf('# Close') + 7),
    );
    expect(find.byType(WpOutlinePanel), findsOneWidget);
  });

  testWidgets('next/previous heading keys step with the panel closed', (
    tester,
  ) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    tester.takeAnnouncements();

    await _chord(tester, LogicalKeyboardKey.pageDown);
    expect(controller.selection.baseOffset, '# Intro'.length + 5);
    await _chord(tester, LogicalKeyboardKey.pageDown);
    await _chord(tester, LogicalKeyboardKey.pageDown);
    final closeEnd = _text.indexOf('# Close') + 7;
    expect(controller.selection.baseOffset, closeEnd);
    tester.takeAnnouncements();

    // macOS announces past the test messenger (announce.dart), so the
    // spoken text is checked on Windows and Linux; the keys on all three.
    final spoken = defaultTargetPlatform != TargetPlatform.macOS;
    await _chord(tester, LogicalKeyboardKey.pageDown);
    expect(controller.selection.baseOffset, closeEnd);
    if (spoken) {
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains(_l10n.editorOutlineNoNext),
      );
    }

    await _chord(tester, LogicalKeyboardKey.pageUp);
    expect(
      controller.selection.baseOffset,
      _text.indexOf('## Detail') + '## Detail'.length,
    );
    if (spoken) {
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains(_l10n.editorOutlineJumped('Detail', 2)),
      );
    }

    // On macOS the arrow pair without a Page Down key does the same.
    if (!spoken) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(controller.selection.baseOffset, closeEnd);
    }
    expect(find.byType(WpOutlinePanel), findsNothing);
    expect(focusNode.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('the list follows typing only after the pause', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsIdentifier('probe-toolbar-outline'));
    await tester.pumpAndSettle();
    expect(item(3), findsNothing);

    controller.text = '$_text\n# Added';
    await tester.pump(const Duration(milliseconds: 100));
    expect(item(3), findsNothing);
    controller.text = '$_text\n# Added later';
    await tester.pump(const Duration(milliseconds: 200));
    expect(item(3), findsNothing, reason: 'typing restarts the pause');

    await tester.pump(WpOutlinePanel.defaultThrottle);
    expect(item(3), findsOneWidget);
  });

  testWidgets('no headings: the panel says how to make one', (tester) async {
    controller.text = 'Just a dictation.';
    await pump(tester);
    await tester.tap(find.bySemanticsIdentifier('probe-toolbar-outline'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('probe-outline-empty'), findsOneWidget);
    expect(find.text(_l10n.editorOutlineEmpty), findsOneWidget);
  });

  testWidgets('while only reading, the outline stays closed and its key '
      'does nothing', (tester) async {
    await pump(tester, editable: false);
    await tester.tap(find.bySemanticsIdentifier('probe-toolbar-outline'));
    await tester.pumpAndSettle();
    expect(find.byType(WpOutlinePanel), findsNothing);
  });

  test('the heading keys are named for the platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(WpTextEditor.nextHeadingShortcutLabel(_l10n), '⌥⌘↓');
    expect(WpTextEditor.nextHeadingActivators, hasLength(2));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      WpTextEditor.nextHeadingShortcutLabel(_l10n),
      'Ctrl+${_l10n.shortcutKeyPageDown}',
    );
    expect(WpTextEditor.nextHeadingActivators, hasLength(1));
    debugDefaultTargetPlatformOverride = null;
  });
}

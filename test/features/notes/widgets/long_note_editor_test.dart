// Handover points of the long-note editor (#641): the page's controller holds
// the whole text, only the active row is a text field, and selection, find,
// dictation and jumps work across rows.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/widgets/long_note_editor.dart';
import 'package:whispaste/widgets/find_replace.dart';

/// [count] paragraphs, each a few sentences long.
String _corpus(int count) => [
  for (var i = 0; i < count; i++)
    'Absatz $i. Ein Satz mit einigen Wörtern. Noch ein Satz zum Schluss.',
].join('\n\n');

Future<(WpFindHighlightController, FocusNode)> _pump(
  WidgetTester tester,
  String text,
) async {
  final controller = WpFindHighlightController(text: text);
  final focus = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LongNoteEditor(
          controller: controller,
          focusNode: focus,
          semanticsLabel: 'Note text',
        ),
      ),
    ),
  );
  await tester.pump();
  return (controller, focus);
}

LongNoteEditorState _state(WidgetTester tester) =>
    tester.state<LongNoteEditorState>(find.byType(LongNoteEditor));

Finder _rowsBuilt() => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.identifier?.startsWith('notes-editor-row-') ?? false),
);

EditableText _field(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText));

void main() {
  testWidgets('builds only the rows near the viewport, with a buffer', (
    tester,
  ) async {
    await _pump(tester, _corpus(3000));
    final state = _state(tester);
    expect(state.rows.length, 3000);
    final built = _rowsBuilt().evaluate().length;
    // The buffer keeps rows past the viewport in the tree (screen readers
    // read on), but nowhere near the whole note.
    expect(built, greaterThan(1));
    expect(built, lessThan(300));
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets('dictation inserts at the caret in a far row', (tester) async {
    final (controller, _) = await _pump(tester, _corpus(3000));
    final state = _state(tester);
    final row = state.rows.firstRowOfBlock(2000);
    final at = state.rows.startOf(row) + 6;
    controller.selection = TextSelection.collapsed(offset: at);
    await tester.pump();
    await tester.pump();
    expect(state.activeRow, row);

    // What voice insert does: replace the selection on the page's controller.
    final before = controller.text;
    controller.value = controller.value.replaced(
      controller.selection,
      'diktiert ',
    );
    await tester.pump();
    await tester.pump();
    expect(controller.text, before.replaceRange(at, at, 'diktiert '));
    expect(_field(tester).controller.text, contains('diktiert '));
    expect(_rowsBuilt(), findsWidgets);
  });

  testWidgets('typing in the active row lands in the whole text', (
    tester,
  ) async {
    final (controller, _) = await _pump(tester, _corpus(500));
    final state = _state(tester);
    final row = state.rows.firstRowOfBlock(300);
    final start = state.rows.segmentStart(row);
    controller.selection = TextSelection.collapsed(offset: start);
    await tester.pump();
    await tester.pump();

    final local = _field(tester).controller;
    local.value = TextEditingValue(
      text: 'X${local.text}',
      selection: const TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    expect(controller.text.substring(start, start + 9), 'XAbsatz 3');
    expect(controller.selection, TextSelection.collapsed(offset: start + 1));
  });

  testWidgets('a selection across rows copies and deletes as one', (
    tester,
  ) async {
    final text = _corpus(200);
    final (controller, focus) = await _pump(tester, text);
    final state = _state(tester);
    final from = state.rows.startOf(state.rows.firstRowOfBlock(10)) + 3;
    final to = state.rows.startOf(state.rows.firstRowOfBlock(14)) + 5;
    focus.requestFocus();
    await tester.pump();
    controller.selection = TextSelection(baseOffset: from, extentOffset: to);
    await tester.pump();
    await tester.pump();

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final mod = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
    expect(copied, text.substring(from, to));

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, text.replaceRange(from, to, ''));
    expect(controller.selection, TextSelection.collapsed(offset: from));
  });

  testWidgets('Shift+Down at the end of a row extends into the next row', (
    tester,
  ) async {
    final (controller, focus) = await _pump(tester, _corpus(50));
    final state = _state(tester);
    final end = state.rows.segmentEnd(3, controller.text.length);
    controller.selection = TextSelection.collapsed(offset: end);
    focus.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.selection.baseOffset, end);
    expect(
      controller.selection.extentOffset,
      state.rows.segmentEnd(4, controller.text.length),
    );
  });

  testWidgets('a find hit far down scrolls into view and is tinted', (
    tester,
  ) async {
    final text = _corpus(3000);
    final (controller, _) = await _pump(tester, text);
    final state = _state(tester);
    final hit = text.indexOf('Absatz 2500.');
    controller
      ..setFindHighlight(WpFindMatches(starts: [hit], length: 6), 0)
      ..selection = TextSelection(baseOffset: hit, extentOffset: hit + 6);
    await tester.pumpAndSettle();
    final row = state.rows.segmentOf(hit);
    expect(state.activeRow, row);
    final scroll = state.scrollController.offset;
    expect(scroll, greaterThan(0));
    expect(
      (state.heights.offsetOf(row) - scroll).abs(),
      lessThan(tester.view.physicalSize.height),
    );
    final local = _field(tester).controller as WpFindHighlightController;
    expect(local.findMatches.count, 1);
    expect(local.activeFindIndex, 0);
  });

  testWidgets('jumping to a paragraph moves the field there', (tester) async {
    final (controller, focus) = await _pump(tester, _corpus(3000));
    final state = _state(tester);
    focus.requestFocus();
    await tester.pump();
    final row = state.rows.firstRowOfBlock(1499);
    controller.selection = TextSelection.collapsed(
      offset: state.rows.startOf(row),
    );
    await tester.pumpAndSettle();
    expect(state.activeRow, row);
    expect(find.bySemanticsIdentifier('notes-editor-active-block'), findsOne);
    expect(state.scrollController.offset, greaterThan(0));
  });

  testWidgets('IME keeps its input client while a composition splits a row', (
    tester,
  ) async {
    final (controller, _) = await _pump(tester, 'first\n\nsecond');
    await tester.showKeyboard(find.byType(EditableText));
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'first\n\nかな\n',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 7, end: 9),
      ),
    );
    await tester.pump();
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(field),
    );
    expect(controller.value.composing, const TextRange(start: 7, end: 9));
    expect(controller.text, 'first\n\nかな\n\nsecond');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'first\n\n仮名\n',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'first\n\n仮名\n\nsecond');
    expect(controller.value.composing, TextRange.empty);
    expect(_state(tester).rows.length, 3);
    await _undo(tester);
    expect(controller.text, 'first\n\nsecond');
    await _undo(tester, redo: true);
    expect(controller.text, 'first\n\n仮名\n\nsecond');
  });

  testWidgets('composition-only updates are forwarded and cleared', (
    tester,
  ) async {
    final (controller, _) = await _pump(tester, 'first\n\nsecond');
    controller.selection = const TextSelection.collapsed(offset: 9);
    await tester.pumpAndSettle();
    final local = _field(tester).controller;
    local.value = local.value.copyWith(
      composing: const TextRange(start: 0, end: 3),
    );
    expect(controller.value.composing, const TextRange(start: 7, end: 10));
    local.clearComposing();
    expect(controller.value.composing, TextRange.empty);
  });

  testWidgets('IME postpones a soft split and survives scrolling off screen', (
    tester,
  ) async {
    final (controller, _) = await _pump(
      tester,
      List.filled(2000, 'word').join(' '),
    );
    await tester.showKeyboard(find.byType(EditableText));
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    final local = _field(tester).controller;
    final before = local.text;
    final inserted = List.filled(3000, 'あ').join();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$before$inserted',
        selection: TextSelection.collapsed(
          offset: before.length + inserted.length,
        ),
        composing: TextRange(
          start: before.length,
          end: before.length + inserted.length,
        ),
      ),
    );
    await tester.pump();
    _state(tester).scrollController.jumpTo(5000);
    await tester.pump();
    expect(
      tester.state<EditableTextState>(
        find.byType(EditableText, skipOffstage: false),
      ),
      same(state),
    );
    expect(controller.value.composing.isCollapsed, isFalse);
    local.clearComposing();
    await tester.pumpAndSettle();
    expect(controller.value.composing, TextRange.empty);
    expect(controller.text, contains(inserted));
  });

  testWidgets(
    'soft boundaries allow left, delete and undo without skipping text',
    (tester) async {
      final source = List.filled(1000, 'word').join(' ');
      final (controller, focus) = await _pump(tester, source);
      final boundary = _state(tester).rows.segmentStart(1);
      controller.selection = TextSelection.collapsed(offset: boundary);
      focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.selection.extentOffset, boundary - 1);
      expect(_state(tester).activeRow, 0);
      controller.selection = TextSelection.collapsed(
        offset: boundary,
        affinity: TextAffinity.upstream,
      );
      await tester.pumpAndSettle();
      expect(_state(tester).activeRow, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(controller.text, source.replaceRange(boundary, boundary + 1, ''));
      await _undo(tester);
      expect(controller.text, source);
    },
  );

  testWidgets('dragging beyond the viewport scrolls and extends selection', (
    tester,
  ) async {
    final (controller, _) = await _pump(tester, _corpus(3000));
    final start =
        tester.getTopLeft(find.byType(EditableText)) + const Offset(10, 12);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(
      Offset(start.dx, tester.view.physicalSize.height + 40),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_state(tester).scrollController.offset, greaterThan(0));
    expect(controller.selection.extentOffset, greaterThan(100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.selection.baseOffset, lessThan(10));
  });

  testWidgets('selection and deletion at a soft boundary preserve graphemes', (
    tester,
  ) async {
    const emoji = '👩‍💻';
    final prefix = List.filled(2000, 'a').join();
    final source = '$prefix$emoji${List.filled(2000, 'b').join()}';
    final (controller, focus) = await _pump(tester, source);
    final boundary = _state(tester).rows.segmentStart(1);
    expect(boundary, prefix.length);
    controller.selection = TextSelection.collapsed(
      offset: boundary,
      affinity: TextAffinity.upstream,
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      controller.text,
      source.replaceRange(boundary, boundary + emoji.length, ''),
    );
    await _undo(tester);
    expect(controller.text, source);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      TextSelection(
        baseOffset: boundary,
        extentOffset: boundary + emoji.length,
      ),
    );
  });

  testWidgets('undo and redo restore edits and selections across rows', (
    tester,
  ) async {
    final (controller, focus) = await _pump(tester, 'first\n\nsecond');
    focus.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pumpAndSettle();
    _field(tester).controller.value = const TextEditingValue(
      text: 'fiXrst\n',
      selection: TextSelection.collapsed(offset: 3),
    );
    await tester.pumpAndSettle();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await tester.pumpAndSettle();
    _field(tester).controller.value = const TextEditingValue(
      text: 'secondY',
      selection: TextSelection.collapsed(offset: 7),
    );
    await tester.pumpAndSettle();
    await _undo(tester);
    expect(controller.text, 'fiXrst\n\nsecond');
    await _undo(tester);
    expect(controller.text, 'first\n\nsecond');
    expect(controller.selection.extentOffset, 2);
    await _undo(tester, redo: true);
    await _undo(tester, redo: true);
    expect(controller.text, 'fiXrst\n\nsecondY');
    expect(controller.selection.extentOffset, controller.text.length);
  });

  testWidgets('Shift arrows extend and reverse selection through a boundary', (
    tester,
  ) async {
    final (controller, focus) = await _pump(tester, 'first\n\nsecond');
    controller.selection = const TextSelection.collapsed(offset: 6);
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 6, extentOffset: 7),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 6, extentOffset: 8),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
  });

  testWidgets('drag from input through plain rows keeps the document anchor', (
    tester,
  ) async {
    final (controller, _) = await _pump(tester, 'first\n\nsecond\n\nthird');
    final start =
        tester.getTopLeft(find.byType(EditableText)) + const Offset(10, 12);
    final end = tester.getCenter(
      find.bySemanticsIdentifier('notes-editor-row-2'),
    );
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(end);
    await tester.pump();
    final selection = controller.selection;
    expect(selection.start, lessThan(6));
    expect(selection.end, greaterThanOrEqualTo(15));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.selection, selection);
    expect(_state(tester).activeRow, 2);
  });

  testWidgets(
    'find across a boundary and dictation replace the whole selection',
    (tester) async {
      final (controller, focus) = await _pump(tester, 'first\n\nsecond');
      focus.requestFocus();
      controller
        ..setFindHighlight(const WpFindMatches(starts: [3], length: 6), 0)
        ..selection = const TextSelection(baseOffset: 3, extentOffset: 9);
      await tester.pumpAndSettle();
      controller.value = controller.value.replaced(
        controller.selection,
        'dictated\n\ntext',
      );
      await tester.pumpAndSettle();
      expect(controller.text, 'firdictated\n\ntextcond');
      expect(controller.selection.extentOffset, 17);
      await _undo(tester);
      expect(controller.text, 'first\n\nsecond');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 3, extentOffset: 9),
      );
    },
  );

  testWidgets(
    'accessibility focus reveals buffered rows so reading can continue',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _corpus(3000));
      await tester.pumpAndSettle();
      final target = _rowsBuilt().last;
      final node = tester.getSemantics(target);
      expect(
        node.getSemanticsData().hasAction(
          SemanticsAction.didGainAccessibilityFocus,
        ),
        isTrue,
      );
      tester.binding.rootPipelineOwner.visitChildren((owner) {
        owner.semanticsOwner?.performAction(
          node.id,
          SemanticsAction.didGainAccessibilityFocus,
        );
      });
      await tester.pumpAndSettle();
      expect(_state(tester).scrollController.offset, greaterThan(0));
      expect(_rowsBuilt().evaluate().length, lessThan(300));
      semantics.dispose();
    },
  );
}

Future<void> _undo(WidgetTester tester, {bool redo = false}) async {
  final mod = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(mod);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(mod);
  await tester.pumpAndSettle();
}

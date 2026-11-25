// Handover points of folding in the long-note editor (#1344): shortcut and
// button fold a heading section, the text never changes, copying keeps
// folded text, and a caret, find hit or jump into a fold opens it. The
// folds go to and come from the per-entry view state as heading ordinals.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/long_note_editor.dart';
import 'package:whispaste/features/notes/widgets/note_fold_controller.dart';
import 'package:whispaste/widgets/find_replace.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../../fixtures/test_helpers.dart';

/// Three sections of [perSection] paragraphs each, the second with a
/// subsection.
String _doc(int perSection) {
  String body(String tag) => [
    for (var i = 0; i < perSection; i++) '$tag $i. Ein Satz mit Wörtern.',
  ].join('\n\n');
  return [
    'Einleitung.',
    '# Eins',
    body('eins'),
    '# Zwei',
    body('zwei'),
    '## Zwei a',
    body('zweia'),
    '# Drei',
    body('drei'),
  ].join('\n\n');
}

Future<(WpFindHighlightController, FocusNode, NoteFoldController)> _pump(
  WidgetTester tester,
  String text,
) async {
  final controller = WpFindHighlightController(text: text);
  final focus = FocusNode();
  final folds = NoteFoldController();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  addTearDown(folds.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('de'),
      home: Scaffold(
        body: LongNoteEditor(
          controller: controller,
          focusNode: focus,
          folds: folds,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (controller, focus, folds);
}

LongNoteEditorState _state(WidgetTester tester) =>
    tester.state<LongNoteEditorState>(find.byType(LongNoteEditor));

LogicalKeyboardKey get _mod => defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(_mod);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(_mod);
  await tester.pump();
}

int _rowOf(LongNoteEditorState state, String text, String needle) =>
    state.rows.segmentOf(text.indexOf(needle));

void main() {
  // The outline of the shared editor block (#645) over the long-note editor:
  // the next-heading key lands on a heading inside a folded section, which
  // opens, and the caret stays at the heading's end.
  testWidgets('a heading jump into a folded section opens it', (tester) async {
    final text = _doc(4);
    final controller = WpFindHighlightController(text: text);
    final focus = FocusNode();
    final folds = NoteFoldController();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(folds.dispose);
    await tester.pumpWidget(
      makeTestable(
        locale: const Locale('de'),
        Material(
          child: WpTextEditor(
            testId: 'notes-editor',
            controller: controller,
            focusNode: focus,
            variant: WpTextFieldVariant.bare,
            fieldOverride: LongNoteEditor(
              controller: controller,
              focusNode: focus,
              folds: folds,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final state = _state(tester);
    // Fold everything, "Zwei" (which holds "Zwei a") with it. Keyboard focus
    // puts the caret at the end first (WpTextEditor), so the caret is
    // placed after it; folding moves it to the end of "# Zwei".
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
    controller.selection = TextSelection.collapsed(
      offset: text.indexOf('zwei 1.') + 2,
    );
    await tester.pump();
    await tester.pump();
    folds.foldAll();
    await tester.pump();
    expect(state.folded, contains(1));
    expect(state.isRowHidden(_rowOf(state, text, '## Zwei a')), isTrue);

    await tester.sendKeyDownEvent(_mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(_mod);
    await tester.pump();
    await tester.pump();

    final end = text.indexOf('## Zwei a') + '## Zwei a'.length;
    expect(controller.selection, TextSelection.collapsed(offset: end));
    expect(state.isRowHidden(_rowOf(state, text, '## Zwei a')), isFalse);
    expect(controller.text, text);
  });

  testWidgets('the shortcut folds the section at the caret, text unchanged', (
    tester,
  ) async {
    final text = _doc(5);
    final (controller, focus, _) = await _pump(tester, text);
    final state = _state(tester);
    controller.selection = TextSelection.collapsed(
      offset: text.indexOf('eins 2.') + 3,
    );
    focus.requestFocus();
    await tester.pump();
    await tester.pump();

    await _shortcut(tester, LogicalKeyboardKey.keyK);
    expect(state.folded, {0});
    expect(state.isRowHidden(_rowOf(state, text, 'eins 2.')), isTrue);
    expect(state.isRowHidden(_rowOf(state, text, '# Eins')), isFalse);
    expect(state.isRowHidden(_rowOf(state, text, '# Zwei')), isFalse);
    expect(controller.text, text, reason: 'a fold never touches the text');
    // The caret left the folded body for the end of its heading.
    expect(
      controller.selection,
      TextSelection.collapsed(offset: text.indexOf('# Eins') + 6),
    );
    final announced = tester.takeAnnouncements().map((a) => a.message);
    expect(announced, contains('Eins: zugeklappt'));

    await _shortcut(tester, LogicalKeyboardKey.keyK);
    expect(state.folded, isEmpty);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Eins: aufgeklappt'),
    );
  });

  testWidgets('the chevron button folds and reports its state', (tester) async {
    final handle = tester.ensureSemantics();
    final text = _doc(3);
    await _pump(tester, text);
    final state = _state(tester);
    final button = find.bySemanticsIdentifier('notes-editor-fold-1');
    expect(button, findsOneWidget);
    expect(
      tester.getSemantics(button),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
    );
    await tester.tap(button);
    await tester.pump();
    expect(state.folded, {1});
    expect(state.isRowHidden(_rowOf(state, text, 'zweia 0.')), isTrue);
    expect(
      tester.getSemantics(button),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
    );
    handle.dispose();
  });

  testWidgets('arrow down skips a folded section', (tester) async {
    final text = _doc(3);
    final (controller, focus, folds) = await _pump(tester, text);
    final state = _state(tester);
    state.toggleSection(0);
    await tester.pump();
    // The end of the heading row's segment: its blank line belongs to it.
    controller.selection = TextSelection.collapsed(
      offset: state.rows.segmentEnd(_rowOf(state, text, '# Eins'), text.length),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(state.activeRow, _rowOf(state, text, '# Zwei'));
    expect(state.folded, {0}, reason: 'the fold stays');
  });

  testWidgets('a caret, a jump or a find hit in a fold opens it', (
    tester,
  ) async {
    final text = _doc(4);
    final (controller, _, folds) = await _pump(tester, text);
    final state = _state(tester);
    folds.foldAll();
    await tester.pump();
    expect(state.folded, {0, 1, 2, 3});

    // A jump ("Go to paragraph", dictation target) into the subsection
    // opens it and the section around it, nothing else.
    controller.selection = TextSelection.collapsed(
      offset: text.indexOf('zweia 1.'),
    );
    await tester.pump();
    expect(state.folded, {0, 3});
    expect(state.isRowHidden(_rowOf(state, text, 'zweia 1.')), isFalse);

    // The active find hit opens its section.
    final hit = text.indexOf('drei 3.');
    controller.setFindHighlight(WpFindMatches(starts: [hit], length: 4), 0);
    await tester.pump();
    expect(state.folded, {0});
    expect(controller.text, text);
  });

  testWidgets('copying across a fold takes the folded text along', (
    tester,
  ) async {
    final text = _doc(3);
    final (controller, focus, folds) = await _pump(tester, text);
    final state = _state(tester);
    folds.foldAll();
    await tester.pump();
    focus.requestFocus();
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
    await tester.sendKeyDownEvent(_mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(_mod);
    await tester.pump();
    expect(copied, text);
    expect(state.folded, {0, 1, 2, 3}, reason: 'select all keeps the folds');
  });

  testWidgets('folds go to the view state and come back from it', (
    tester,
  ) async {
    final text = _doc(3);
    final (controller, _, folds) = await _pump(tester, text);
    final state = _state(tester);
    var changes = 0;
    state.viewAnchorChanges.addListener(() => changes++);
    expect(folds.canFold, isTrue);
    expect(folds.anyFolded, isFalse);

    state.toggleSection(2);
    state.toggleSection(0);
    await tester.pump();
    expect(state.captureFolds(), [0, 2]);
    expect(changes, greaterThan(0), reason: 'the memory saves on a fold');
    expect(folds.anyFolded, isTrue);

    folds.unfoldAll();
    await tester.pump();
    expect(state.captureFolds(), isEmpty);

    // Restoring ignores unknown ordinals and keeps the caret's section open.
    controller.selection = TextSelection.collapsed(
      offset: text.indexOf('drei 1.'),
    );
    await tester.pump();
    state.restoreFolds([0, 3, 7]);
    await tester.pump();
    expect(state.captureFolds(), [0]);
    expect(controller.text, text);
  });

  testWidgets('editing above a folded heading keeps its fold', (tester) async {
    final text = _doc(3);
    final (controller, _, _) = await _pump(tester, text);
    final state = _state(tester);
    state.toggleSection(3);
    await tester.pump();
    controller.value = TextEditingValue(
      text: '# Neu\n\nText.\n\n$text',
      selection: const TextSelection.collapsed(offset: 2),
    );
    await tester.pump();
    expect(state.folded, {4}, reason: '# Drei is now the fifth heading');
  });
}

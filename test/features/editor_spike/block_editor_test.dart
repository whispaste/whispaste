import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/blocks/block_document.dart';
import 'package:whispaste/features/editor_spike/block_editor.dart';

import 'package:whispaste/features/editor_spike/spike_corpus.dart';

Future<BlockEditorController> _pump(
  WidgetTester tester,
  BlockDocument doc,
) async {
  final controller = BlockEditorController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlockEditor(document: doc, controller: controller),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('tapping a block activates it; typing edits only its Markdown', (
    tester,
  ) async {
    final doc = BlockDocument.parse('# Titel\n\nAlt\n\nRest\n');
    final c = await _pump(tester, doc);

    await tester.tap(find.byKey(const ValueKey('editor-spike-row-1')));
    await tester.pump();
    expect(c.activeBlock, 1);
    expect(find.byType(EditableText), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Neu');
    c.commit();
    expect(doc.toMarkdown(), '# Titel\n\nNeu\n\nRest\n');
  });

  testWidgets('the active block shows raw Markdown, others hide markers', (
    tester,
  ) async {
    final doc = BlockDocument.parse('## Kopf\n\nText\n');
    final c = await _pump(tester, doc);
    expect(find.text('Kopf'), findsOneWidget);

    c.activateBlock(0);
    await tester.pump();
    expect(c.activeText!.text, '## Kopf');
  });

  testWidgets('arrow down at the block end moves to the next block', (
    tester,
  ) async {
    final doc = BlockDocument.parse('Eins\n\nZwei\n');
    final c = await _pump(tester, doc);
    c.activateBlock(0, caret: 4);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.activeBlock, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.activeBlock, 0);
  });

  testWidgets('backspace at block start merges into the previous block', (
    tester,
  ) async {
    final doc = BlockDocument.parse('Eins.\n\nZwei.\n');
    final c = await _pump(tester, doc);
    c.activateBlock(1);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(doc.toMarkdown(), 'Eins.Zwei.\n');
    expect(c.activeBlock, 0);
    expect(c.activeText!.selection.baseOffset, 'Eins.'.length);
  });

  testWidgets('editing a soft-split segment keeps the rest of the paragraph', (
    tester,
  ) async {
    final source = singleParagraph(2000);
    final doc = BlockDocument.parse(source);
    final c = await _pump(tester, doc);
    expect(c.rowCount, greaterThan(1));

    c.activateBlock(0);
    await tester.pump();
    final segment = c.activeText!.text;
    c.activeText!.text = 'X$segment';
    c.commit();
    expect(doc.toMarkdown(), 'X$source');
  });

  testWidgets('jumpToBlock brings a far block into the built range', (
    tester,
  ) async {
    final doc = BlockDocument.parse(germanProse(5000));
    final c = await _pump(tester, doc);
    final target = doc.blocks.length - 3;
    final rowsBefore = c.rowCount;

    var done = false;
    unawaited(c.jumpToBlock(target).then((_) => done = true));
    for (var i = 0; i < 6 && !done; i++) {
      await tester.pump();
    }
    expect(done, isTrue);
    expect(c.rowCount, rowsBefore);
    expect(
      find.byKey(ValueKey('editor-spike-row-$target'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('a screen reader tap on an inactive block activates it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final doc = BlockDocument.parse('# Titel\n\nAlt\n\nRest\n');
    final c = await _pump(tester, doc);

    // Throws when the node has no tap action.
    tester.semantics.tap(
      find.semantics.byPredicate((n) => n.identifier == 'editor-spike-block-2'),
    );
    await tester.pump();
    expect(c.activeBlock, 2);
    handle.dispose();
  });

  testWidgets('dictation is inserted at the caret of the active block', (
    tester,
  ) async {
    final doc = BlockDocument.parse('# Titel\n\nAlt\n\nRest\n');
    final c = await _pump(tester, doc);
    c.activateBlock(1, caret: 1);
    await tester.pump();

    c.insertAtCaret('Neu ');
    expect(c.activeText!.selection.baseOffset, 'ANeu '.length);
    c.commit();
    expect(doc.toMarkdown(), '# Titel\n\nANeu lt\n\nRest\n');
  });

  testWidgets('dictation replaces a selection', (tester) async {
    final doc = BlockDocument.parse('Eins zwei drei\n');
    final c = await _pump(tester, doc);
    c.activateBlock(0);
    await tester.pump();
    c.activeText!.selection = const TextSelection(
      baseOffset: 5,
      extentOffset: 9,
    );

    c.insertAtCaret('vier');
    c.commit();
    expect(doc.toMarkdown(), 'Eins vier drei\n');
  });

  testWidgets('shift+arrow selects inside the block without leaving it', (
    tester,
  ) async {
    final doc = BlockDocument.parse('Eins\n\nZwei\n');
    final c = await _pump(tester, doc);
    c.activateBlock(0, caret: 4);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(c.activeBlock, 0);
    final sel = c.activeText!.selection;
    expect((sel.start, sel.end), (2, 4));
  });
}

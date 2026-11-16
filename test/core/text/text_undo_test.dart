import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/text_undo.dart';

void main() {
  TextEditingValue value(String text, [int? caret]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length),
  );

  var now = DateTime(2026);
  DateTime clock() => now;
  void wait(int ms) => now = now.add(Duration(milliseconds: ms));

  /// Types [chars] one key at a time, [gap] ms apart, from [start].
  TextEditingValue type(
    TextUndoHistory history,
    TextEditingValue start,
    String chars, {
    int gap = 100,
  }) {
    var current = start;
    for (final c in chars.split('')) {
      wait(gap);
      final caret = current.selection.extentOffset;
      final next = value(current.text.replaceRange(caret, caret, c), caret + 1);
      history.record(current, next);
      current = next;
    }
    return current;
  }

  group('grouping', () {
    test('keys within 500 ms are one step, a pause starts the next', () {
      final history = TextUndoHistory(clock: clock);
      var v = type(history, value(''), 'Hello');
      wait(500);
      v = type(history, v, ' world');
      v = history.undo(v)!;
      expect(v.text, 'Hello');
      expect(history.undo(v)!.text, '');
      expect(history.canUndo, isFalse);
    });

    test('a caret jump ends the group', () {
      final history = TextUndoHistory(clock: clock);
      var v = type(history, value(''), 'ab');
      final moved = value(v.text, 0);
      history.record(v, moved);
      v = type(history, moved, 'x');
      expect(v.text, 'xab');
      v = history.undo(v)!;
      expect(v.text, 'ab');
      expect(history.undo(v)!.text, '');
    });

    test('backspace runs group; changing direction splits', () {
      final history = TextUndoHistory(clock: clock);
      var v = value('abcdef');
      for (var i = 0; i < 3; i++) {
        wait(100);
        final next = value(v.text.substring(0, v.text.length - 1));
        history.record(v, next);
        v = next;
      }
      expect(v.text, 'abc');
      v = type(history, v, 'Z');
      v = history.undo(v)!;
      expect(v.text, 'abc');
      v = history.undo(v)!;
      expect(v.text, 'abcdef');
      expect(v.selection.extentOffset, 6);
    });

    test('a command is a step of its own and seals the group', () {
      final history = TextUndoHistory(clock: clock);
      var v = type(history, value(''), 'word');
      wait(10);
      final bold = value('**word**');
      history.record(v, bold, command: true);
      v = type(history, bold, '!', gap: 10);
      v = history.undo(v)!;
      expect(v.text, '**word**');
      v = history.undo(v)!;
      expect(v.text, 'word');
      expect(history.undo(v)!.text, '');
    });

    test('a pasted or dictated block undoes as one unit', () {
      final history = TextUndoHistory(clock: clock);
      var v = type(history, value(''), 'a');
      wait(10);
      final dictated = value('a dictated sentence.');
      history.record(v, dictated);
      v = history.undo(dictated)!;
      expect(v.text, 'a');
    });

    test('an IME composition lands as one step, never split', () {
      final history = TextUndoHistory(clock: clock);
      final start = value('x');
      var prev = start;
      for (final s in ['xn', 'xに', 'xにほ', 'xにほん']) {
        wait(50);
        final composing = value(
          s,
        ).copyWith(composing: TextRange(start: 1, end: s.length));
        history.record(prev, composing);
        prev = composing;
      }
      expect(history.canUndo, isFalse);
      final committed = value('x日本');
      history.record(prev, committed);
      expect(history.undo(committed), start);
    });

    test('a cancelled IME composition makes no step', () {
      final history = TextUndoHistory(clock: clock);
      final before = value('one');
      final composing = value(
        'one仮',
      ).copyWith(composing: const TextRange(start: 3, end: 4));
      history.record(before, composing);
      history.record(composing, before);
      expect(history.undo(before), isNull);
    });
  });

  test('selection changes keep redo, a new edit replaces the branch', () {
    final history = TextUndoHistory(clock: clock);
    final before = value('one\n\ntwo', 2);
    final after = value('one\n\ntwo!');
    history.record(before, after);
    expect(history.undo(after), before);
    history.record(before, value(before.text, 0));
    expect(history.redo(before), after);
    history.undo(after);
    final branched = value('one!\n\ntwo', 4);
    history.record(before, branched);
    expect(history.redo(branched), isNull);
    expect(history.undo(branched), before);
  });

  test('keeps the newest maxDepth steps (at least 100)', () {
    expect(TextUndoHistory.maxDepth, greaterThanOrEqualTo(100));
    final history = TextUndoHistory(clock: clock);
    var v = value('');
    for (var i = 0; i < TextUndoHistory.maxDepth + 5; i++) {
      final next = value('${v.text}$i;');
      history.record(v, next, command: true);
      v = next;
    }
    var undone = 0;
    while (true) {
      final back = history.undo(v);
      if (back == null) break;
      v = back;
      undone++;
    }
    expect(undone, TextUndoHistory.maxDepth);
    expect(v.text, startsWith('0;1;2;3;4;'));
  });

  test('text changed behind its back drops the history', () {
    final history = TextUndoHistory(clock: clock);
    history.record(value('first'), value('first!'));
    expect(history.undo(value('second')), isNull);
    expect(history.canUndo, isFalse);
  });

  group('TextUndoController', () {
    test('registers on the text controller; commands are steps', () {
      final text = TextEditingController();
      final undo = TextUndoController(text, clock: clock);
      expect(TextUndoController.of(text), same(undo));
      text.value = value('a');
      wait(10);
      TextUndoController.command(text, () => text.value = value('**a**'));
      expect(undo.canUndo, isTrue);
      undo.undo();
      expect(text.text, 'a');
      expect(undo.canRedo, isTrue);
      undo.redo();
      expect(text.text, '**a**');
      undo.dispose();
      expect(TextUndoController.of(text), isNull);
      // Without a history the command still applies.
      TextUndoController.command(text, () => text.text = 'plain');
      expect(text.text, 'plain');
    });

    test('switching documents parks the history, autosave keeps it', () {
      final text = TextEditingController();
      final undo = TextUndoController(text, clock: clock);
      undo.open('note-1', () => text.value = value('one'));
      expect(undo.canUndo, isFalse);
      text.value = value('one!');
      undo.open('note-2', () => text.value = value('two'));
      expect(undo.canUndo, isFalse);
      undo.open('note-1', () => text.value = value('one!'));
      expect(undo.canUndo, isTrue);
      undo.undo();
      expect(text.text, 'one');
    });

    test('a parked history is dropped when the text changed meanwhile', () {
      final text = TextEditingController();
      final undo = TextUndoController(text, clock: clock);
      undo.open('note-1', () => text.value = value('one'));
      text.value = value('one!');
      undo.open('note-2', () => text.value = value('two'));
      undo.open('note-1', () => text.value = value('changed elsewhere'));
      expect(undo.canUndo, isFalse);
    });

    test('reloading the same document is an undoable step', () {
      final text = TextEditingController();
      final undo = TextUndoController(text, clock: clock);
      undo.open('note-1', () => text.value = value('draft'));
      undo.open('note-1', () => text.value = value('restored version'));
      undo.undo();
      expect(text.text, 'draft');
    });

    test('reset forgets the open document', () {
      final text = TextEditingController();
      final undo = TextUndoController(text, clock: clock);
      undo.open('entry', () => text.value = value('saved'));
      text.value = value('saved, edited');
      undo.reset(() => text.value = value('saved'));
      expect(undo.canUndo, isFalse);
      expect(undo.canRedo, isFalse);
    });
  });
}

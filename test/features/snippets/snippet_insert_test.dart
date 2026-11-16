// Inserting a Textbaustein from inside an editor (#664): the chooser's
// filter and the caret insertion every editor shares.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/snippets/snippet_item.dart';
import 'package:whispaste/features/snippets/widgets/snippet_insert_dialog.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';

SnippetItem _s(String id, String title, String body, {bool fav = false}) =>
    SnippetItem(
      id: id,
      title: title,
      body: body,
      createdAt: DateTime(2026),
      isFavorite: fav,
    );

void main() {
  test('filter lists favourites first and matches title or body', () {
    final items = [
      _s('a', 'Greeting', 'Hello there'),
      _s('b', 'Signature', 'Best regards', fav: true),
      _s('c', 'Address', 'Main street 1'),
    ];
    expect(filterSnippetsForInsert(items, '').map((s) => s.id), [
      'b',
      'a',
      'c',
    ]);
    expect(filterSnippetsForInsert(items, ' HELLO ').map((s) => s.id), ['a']);
    expect(filterSnippetsForInsert(items, 'sig').map((s) => s.id), ['b']);
    expect(filterSnippetsForInsert(items, 'zzz'), isEmpty);
  });

  test('insertText replaces the selection, appends without one, and '
      'selectedText ignores blank selections', () {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final ctrl = TextEditingController(text: 'one two three');
    addTearDown(ctrl.dispose);
    final fmt = WpMarkdownFormatting(controller: ctrl, focusNode: focus);

    ctrl.selection = const TextSelection(baseOffset: 4, extentOffset: 7);
    expect(fmt.selectedText, 'two');
    fmt.insertText('2');
    expect(ctrl.text, 'one 2 three');
    expect(ctrl.selection, const TextSelection.collapsed(offset: 5));

    ctrl.selection = const TextSelection(baseOffset: 3, extentOffset: 4);
    expect(fmt.selectedText, isNull);

    ctrl.selection = const TextSelection.collapsed(offset: -1);
    fmt.insertText('!');
    expect(ctrl.text, 'one 2 three!');
    expect(ctrl.selection, TextSelection.collapsed(offset: ctrl.text.length));
  });
}

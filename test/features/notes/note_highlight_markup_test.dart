/// `==text==` highlight markup for the amber marker role (WP-31a).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_highlight_markup.dart';

void main() {
  test('finds each marked range with its inner bounds', () {
    const text = 'Milch ==Eier== und ==Brot==';
    final spans = noteHighlightSpans(text);
    expect(spans, hasLength(2));
    expect(text.substring(spans[0].innerStart, spans[0].innerEnd), 'Eier');
    expect(text.substring(spans[0].start, spans[0].end), '==Eier==');
    expect(text.substring(spans[1].innerStart, spans[1].innerEnd), 'Brot');
  });

  test('ignores unclosed markers, empty and multi-line markers', () {
    expect(noteHighlightSpans('nur ==offen'), isEmpty);
    expect(noteHighlightSpans('leer ==  == hier'), isEmpty);
    expect(noteHighlightSpans('==zeile\numbruch=='), isEmpty);
  });
}

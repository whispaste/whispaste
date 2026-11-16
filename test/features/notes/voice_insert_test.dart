// XP-5-11: a dictation inserted into a note keeps the word gap to the text
// around the caret instead of gluing onto the previous word.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/voice_insert.dart';

TextEditingValue _at(String text, int caret) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret),
);

void main() {
  test('after a word it adds a space before the dictation', () {
    final r = insertDictation(_at('äöü', 3), 'Heute');
    expect(r.text, 'äöü Heute');
    expect(r.selection.baseOffset, 9);
  });

  test('after a sentence end it adds a space', () {
    expect(insertDictation(_at('Gut.', 4), 'Weiter').text, 'Gut. Weiter');
  });

  test('no extra space after existing whitespace, a newline or a bracket', () {
    expect(insertDictation(_at('Gut ', 4), 'so').text, 'Gut so');
    expect(insertDictation(_at('Gut\n', 4), 'so').text, 'Gut\nso');
    expect(insertDictation(_at('(', 1), 'so').text, '(so');
  });

  test('an empty note and the start of the text get no space', () {
    expect(insertDictation(_at('', 0), 'Hallo').text, 'Hallo');
    expect(insertDictation(_at('Welt', 0), 'Hallo').text, 'Hallo Welt');
  });

  test('a dictation starting with punctuation is not separated', () {
    expect(insertDictation(_at('Gut', 3), ', danke').text, 'Gut, danke');
  });

  test('in the middle of words it pads both sides, caret after the text', () {
    final r = insertDictation(_at('einszwei', 4), 'und');
    expect(r.text, 'eins und zwei');
    expect(r.selection.baseOffset, 8);
  });

  test('before punctuation or a space no trailing space is added', () {
    expect(insertDictation(_at('Gut.', 3), 'so').text, 'Gut so.');
    expect(insertDictation(_at('a b', 1), 'x').text, 'a x b');
  });

  test('a selection is replaced with the same gap rules', () {
    const value = TextEditingValue(
      text: 'eins alt zwei',
      selection: TextSelection(baseOffset: 5, extentOffset: 8),
    );
    expect(insertDictation(value, 'neu').text, 'eins neu zwei');
  });

  test('an invalid selection appends at the end', () {
    const value = TextEditingValue(text: 'Ende');
    final r = insertDictation(value, 'jetzt');
    expect(r.text, 'Ende jetzt');
    expect(r.selection.baseOffset, r.text.length);
  });

  test('a selection past the end of the text is clamped, not a crash', () {
    // A stale selection must not throw a RangeError: the transcript would be
    // lost. It is inserted at the end instead.
    const value = TextEditingValue(
      text: 'Ende',
      selection: TextSelection.collapsed(offset: 9),
    );
    final r = insertDictation(value, 'jetzt');
    expect(r.text, 'Ende jetzt');
    expect(r.selection.baseOffset, r.text.length);
  });

  test('a selection that reaches past the end is clamped as well', () {
    const value = TextEditingValue(
      text: 'Ende',
      selection: TextSelection(baseOffset: 2, extentOffset: 9),
    );
    expect(insertDictation(value, 'neu').text, 'En neu');
  });
}

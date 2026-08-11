/// Unit tests for [stripPunctuation].
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/text_transforms.dart';

void main() {
  group('stripPunctuation', () {
    test('removes a trailing sentence period', () {
      expect(stripPunctuation('Search term.'), 'Search term');
    });

    test('removes commas and collapses the resulting double space', () {
      expect(stripPunctuation('Milk, eggs, and bread.'), 'Milk eggs and bread');
    });

    test('removes question and exclamation marks', () {
      expect(stripPunctuation('Is this working? Yes!'), 'Is this working Yes');
    });

    test('removes colons and semicolons', () {
      expect(
        stripPunctuation('Note: important; urgent'),
        'Note important urgent',
      );
    });

    test('removes em dash and ellipsis', () {
      expect(
        stripPunctuation('Wait — actually… never mind'),
        'Wait actually never mind',
      );
    });

    test('preserves apostrophes in contractions', () {
      expect(stripPunctuation("Don't stop."), "Don't stop");
    });

    test('preserves hyphens in compound words', () {
      expect(stripPunctuation('A well-known fact.'), 'A well-known fact');
    });

    test('preserves a decimal point between digits', () {
      expect(stripPunctuation('Pi is 3.14'), 'Pi is 3.14');
    });

    test('preserves a comma decimal separator between digits', () {
      expect(stripPunctuation('Pi is 3,14'), 'Pi is 3,14');
    });

    test('preserves a thousands separator between digits', () {
      expect(
        stripPunctuation('The budget is 1,000 dollars'),
        'The budget is 1,000 dollars',
      );
    });

    test('preserves every period in a version number', () {
      expect(
        stripPunctuation('Running version 1.2.53'),
        'Running version 1.2.53',
      );
    });

    test('preserves a price with a decimal cents value', () {
      expect(stripPunctuation(r'It costs $19.99'), r'It costs $19.99');
    });

    test('still strips a sentence-ending period right after a number', () {
      expect(stripPunctuation('The answer is 42.'), 'The answer is 42');
    });

    test('still strips a comma right after a number mid-sentence', () {
      expect(
        stripPunctuation('I have 5, maybe 6 apples.'),
        'I have 5 maybe 6 apples',
      );
    });

    test('empty input stays empty', () {
      expect(stripPunctuation(''), '');
    });

    test('input with no punctuation is unchanged', () {
      expect(stripPunctuation('just a word'), 'just a word');
    });

    test(
      'leading and trailing punctuation is removed with whitespace trimmed',
      () {
        expect(stripPunctuation('  , Hello world . '), 'Hello world');
      },
    );
  });

  group('appendToQuickNoteContent', () {
    test('empty note gets no leading whitespace — addition is the content', () {
      expect(appendToQuickNoteContent('', 'First thought'), 'First thought');
    });

    test('whitespace-only note is treated as empty', () {
      expect(
        appendToQuickNoteContent('   \n  ', 'First thought'),
        'First thought',
      );
    });

    test('appends as a new paragraph with exactly one blank line', () {
      expect(
        appendToQuickNoteContent('Existing line', 'New thought'),
        'Existing line\n\nNew thought',
      );
    });

    test('collapses any number of existing trailing newlines to exactly one '
        'blank line', () {
      expect(
        appendToQuickNoteContent('Existing line\n\n\n\n', 'New thought'),
        'Existing line\n\nNew thought',
      );
      expect(
        appendToQuickNoteContent('Existing line\n', 'New thought'),
        'Existing line\n\nNew thought',
      );
    });

    test('inserts no timestamp', () {
      expect(
        appendToQuickNoteContent('Existing', 'New'),
        isNot(contains(RegExp(r'\d{1,2}:\d{2}'))),
      );
    });
  });
}

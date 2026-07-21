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

    test(
      'known limitation: a decimal point is stripped like a sentence period',
      () {
        // This is plain sentence-punctuation removal, not number-aware — a
        // decimal point reads the same as a sentence period to the regex.
        // Acceptable trade-off for a simple, predictable toggle; see
        // text_transforms.dart doc comment.
        expect(stripPunctuation('Pi is 3.14'), 'Pi is 314');
      },
    );

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
}

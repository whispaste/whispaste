/// Unit tests for the pure transcript text transforms.
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

  group('collapseTranscriptWhitespace', () {
    test('turns engine-inserted newlines into single spaces', () {
      expect(
        collapseTranscriptWhitespace('Hello\nworld\r\n\r\nagain\rnow'),
        'Hello world again now',
      );
    });

    test('collapses repeated spaces and trims the ends', () {
      expect(collapseTranscriptWhitespace('  Hello    world  '), 'Hello world');
    });

    test('leaves already clean text untouched', () {
      expect(collapseTranscriptWhitespace('Hello world.'), 'Hello world.');
    });
  });

  group('removeFillerWords', () {
    group('word boundaries', () {
      test('keeps a word that merely starts with a filler token', () {
        expect(
          removeFillerWords('Ähmlich klingt das', languageCode: 'de'),
          'Ähmlich klingt das',
        );
      });

      test('keeps the German preposition "um"', () {
        expect(
          removeFillerWords('Wir treffen uns um 8 Uhr.', languageCode: 'de'),
          'Wir treffen uns um 8 Uhr.',
        );
      });

      test('keeps "um" when the language is auto-detected', () {
        expect(
          removeFillerWords('Wir treffen uns um 8 Uhr.', languageCode: 'auto'),
          'Wir treffen uns um 8 Uhr.',
        );
      });

      test('removes "um" in English', () {
        expect(removeFillerWords('um, so', languageCode: 'en'), 'So');
      });

      test('keeps hyphenated words such as "uh-huh"', () {
        expect(
          removeFillerWords('Uh-huh, that works.', languageCode: 'en'),
          'Uh-huh, that works.',
        );
      });

      test('never touches meaning-carrying words', () {
        const text = 'So, like, I also think so.';
        expect(removeFillerWords(text, languageCode: 'en'), text);
        expect(
          removeFillerWords('Also, ich komme mit.', languageCode: 'de'),
          'Also, ich komme mit.',
        );
      });
    });

    group('per-language token lists', () {
      test('removes every German filler', () {
        for (final filler in ['äh', 'ähm', 'öh', 'öhm', 'hm', 'hmm', 'ehm']) {
          expect(
            removeFillerWords('Ich $filler komme', languageCode: 'de'),
            'Ich komme',
            reason: filler,
          );
        }
      });

      test('removes every English filler', () {
        for (final filler in ['uh', 'uhm', 'um', 'umm', 'erm', 'hmm']) {
          expect(
            removeFillerWords('I $filler agree', languageCode: 'en'),
            'I agree',
            reason: filler,
          );
        }
      });

      test('auto-detect removes the union of all lists except "um"', () {
        expect(
          removeFillerWords('Ich äh komme, uh, später', languageCode: 'auto'),
          'Ich komme später',
        );
      });

      test('a regional language code resolves to its base language', () {
        expect(removeFillerWords('um, so', languageCode: 'en-US'), 'So');
      });

      test('an unlisted language falls back to the set without "um"', () {
        // Portuguese "um" is the article "a/one".
        expect(
          removeFillerWords('Eu tenho uh um carro', languageCode: 'pt'),
          'Eu tenho um carro',
        );
      });
    });

    group('punctuation and whitespace', () {
      test('removes a filler wrapped in commas', () {
        expect(
          removeFillerWords('Ich habe, äh, keine Zeit.', languageCode: 'de'),
          'Ich habe keine Zeit.',
        );
      });

      test('keeps the sentence-ending mark after a trailing filler', () {
        expect(
          removeFillerWords('Das ist gut, ähm.', languageCode: 'de'),
          'Das ist gut.',
        );
        expect(
          removeFillerWords('Is that right, um?', languageCode: 'en'),
          'Is that right?',
        );
      });

      test('removes a filler followed by an ellipsis', () {
        expect(
          removeFillerWords('I think uh... we should go.', languageCode: 'en'),
          'I think we should go.',
        );
        expect(
          removeFillerWords('I think uh… we should go.', languageCode: 'en'),
          'I think we should go.',
        );
      });

      test('removes a filler that forms its own sentence', () {
        expect(
          removeFillerWords('Ähm. Ich komme morgen.', languageCode: 'de'),
          'Ich komme morgen.',
        );
        expect(
          removeFillerWords('Gut. Äh. Bis dann.', languageCode: 'de'),
          'Gut. Bis dann.',
        );
      });

      test('removes consecutive fillers', () {
        expect(
          removeFillerWords('Äh, ähm, das passt.', languageCode: 'de'),
          'Das passt.',
        );
      });

      test('leaves legitimate punctuation elsewhere untouched', () {
        expect(
          removeFillerWords('Wait... what? Uh, fine.', languageCode: 'en'),
          'Wait... what? Fine.',
        );
      });
    });

    group('capitalisation', () {
      test('capitalises the new sentence start', () {
        expect(
          removeFillerWords('Äh, das stimmt. Ähm, ja.', languageCode: 'de'),
          'Das stimmt. Ja.',
        );
      });

      test('matches fillers case-insensitively', () {
        expect(
          removeFillerWords('Ich ÄHM komme', languageCode: 'de'),
          'Ich komme',
        );
      });

      test('does not change the case of a mid-sentence word', () {
        expect(
          removeFillerWords('I, uh, think so', languageCode: 'en'),
          'I think so',
        );
      });
    });

    group('fallback', () {
      test('returns the raw text when only fillers were dictated', () {
        expect(removeFillerWords('Ähm.', languageCode: 'de'), 'Ähm.');
        expect(removeFillerWords('uh, um', languageCode: 'en'), 'uh, um');
      });

      test('returns text without fillers unchanged', () {
        expect(
          removeFillerWords('Hallo Welt.', languageCode: 'de'),
          'Hallo Welt.',
        );
        expect(removeFillerWords('', languageCode: 'de'), '');
      });
    });
  });
}

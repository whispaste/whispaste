import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/transcription/continuity_guard.dart';
import 'package:whispaste/services/transcription/transcript_seam.dart';

void main() {
  group('dropSeamRepeat', () {
    test('removes the words the next text repeats from the previous end', () {
      expect(
        dropSeamRepeat('we went to the market', 'to the market and back'),
        ' and back',
      );
    });

    test('compares ignoring case and punctuation', () {
      expect(dropSeamRepeat('Hallo, wie geht', 'wie geht es dir'), ' es dir');
    });

    test('keeps the text when nothing repeats', () {
      expect(dropSeamRepeat('eins zwei', 'drei vier'), 'drei vier');
    });

    test('a fully repeated next text becomes empty', () {
      expect(dropSeamRepeat('ja gut', 'ja gut'), '');
    });

    test('takes the longest repeated run', () {
      expect(dropSeamRepeat('a b c d b c d', 'b c d e'), ' e');
    });

    test('does not match words that normalise to nothing', () {
      expect(dropSeamRepeat('weiter —', '— und dann'), '— und dann');
    });

    test('checks at most maxWords words', () {
      final tail = List.generate(10, (i) => 'w$i').join(' ');
      expect(dropSeamRepeat(tail, tail), tail);
      expect(dropSeamRepeat(tail, tail, maxWords: 10), '');
    });

    test('empty previous text removes nothing', () {
      expect(dropSeamRepeat('', 'hallo welt'), 'hallo welt');
    });
  });

  group('dropLeadingEcho', () {
    test('strips a copy of the whole carried text', () {
      expect(
        dropLeadingEcho('the quick brown fox', 'the quick brown fox jumps'),
        ' jumps',
      );
    });

    test('keeps text that only starts like the carried text', () {
      expect(
        dropLeadingEcho('the quick brown fox', 'the quick jumps'),
        'the quick jumps',
      );
    });

    test('keeps text when the echo is not at the start', () {
      expect(
        dropLeadingEcho('brown fox', 'the brown fox jumps'),
        'the brown fox jumps',
      );
    });
  });

  group('isRepetitionLoop', () {
    test('detects one word repeated back to back', () {
      expect(isRepetitionLoop('Danke Danke Danke Danke Danke Danke'), isTrue);
    });

    test('detects a phrase repeated back to back', () {
      expect(
        isRepetitionLoop(
          'Ich gehe nach Hause. Ich gehe nach Hause. '
          'Ich gehe nach Hause. Ich gehe nach Hause.',
        ),
        isTrue,
      );
    });

    test('detects a repeated phrase that ends mid-copy', () {
      expect(
        isRepetitionLoop('eins zwei drei eins zwei drei eins zwei drei eins'),
        isTrue,
      );
    });

    test('ordinary speech is not a loop', () {
      expect(
        isRepetitionLoop('Das ist ein ganz normaler Satz mit vielen Wörtern.'),
        isFalse,
      );
    });

    test('a short emphasis is not a loop', () {
      expect(isRepetitionLoop('ja ja ja, genau so'), isFalse);
      expect(isRepetitionLoop('wir fahren los wir fahren los'), isFalse);
    });

    test('empty text is not a loop', () {
      expect(isRepetitionLoop(''), isFalse);
    });
  });

  group('continuityCarryFor', () {
    test('carries the trailing words of a normal piece', () {
      expect(continuityCarryFor('Hallo Welt.'), 'Hallo Welt.');
    });

    test('carries nothing from a looping piece', () {
      expect(
        continuityCarryFor('Danke Danke Danke Danke Danke Danke Danke'),
        isNull,
      );
    });

    test('carries nothing from an empty piece', () {
      expect(continuityCarryFor(''), isNull);
    });

    test('carries at most 200 characters', () {
      final long = List.generate(100, (i) => 'wort$i').join(' ');
      expect(continuityCarryFor(long)!.length, lessThanOrEqualTo(200));
    });
  });

  group('continuityContextFrom word boundary', () {
    test('a window cut inside a word starts at the next word', () {
      final text = '${'a' * 150} ${'b' * 60} ccc ${'d' * 30}';
      expect(continuityContextFrom(text), '${'b' * 60} ccc ${'d' * 30}');
    });
  });

  group('stripPromptEcho', () {
    test('removes a repeated carry from the start of the output', () {
      expect(
        stripPromptEcho('Projekt Alpha', 'Projekt Alpha ist fertig'),
        ' ist fertig',
      );
    });

    test('keeps output that does not echo the carry', () {
      expect(stripPromptEcho('Projekt Alpha', 'Heute ist'), 'Heute ist');
    });
  });

  group('joinSeamTexts', () {
    test('removes the repeat at hard-cut seams only', () {
      const texts = ['wir gehen heute nach Hause.', 'nach Hause und dann'];
      expect(
        joinSeamTexts(texts, const [false, true]),
        'wir gehen heute nach Hause. und dann',
      );
      expect(
        joinSeamTexts(texts, const [false, false]),
        'wir gehen heute nach Hause. nach Hause und dann',
      );
    });

    test('skips empty pieces and seams on the last non-empty text', () {
      expect(
        joinSeamTexts(
          const ['eins zwei', '', 'zwei drei'],
          const [false, false, true],
        ),
        'eins zwei drei',
      );
    });
  });
}

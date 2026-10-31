import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/voice_line_breaks.dart';

String _en(String text) => applyVoiceLineBreaks(text, languageCode: 'en');
String _de(String text) => applyVoiceLineBreaks(text, languageCode: 'de');

void main() {
  group('applyVoiceLineBreaks — per language', () {
    test('en: new paragraph and new line', () {
      expect(
        _en('first part new paragraph second part'),
        'first part\n\nSecond part',
      );
      expect(_en('first part new line second part'), 'first part\nsecond part');
      expect(_en('one paragraph break two'), 'one\n\nTwo');
      expect(_en('one line break two'), 'one\ntwo');
    });

    test('de: neuer Absatz, neue Zeile', () {
      expect(_de('Hallo neuer Absatz Welt'), 'Hallo\n\nWelt');
      expect(_de('Hallo neuen Absatz Welt'), 'Hallo\n\nWelt');
      expect(_de('Hallo neue Zeile Welt'), 'Hallo\nWelt');
      expect(_de('die nächste Zeile fehlt'), 'die nächste Zeile fehlt');
    });

    test('es: nuevo párrafo, nueva línea (with and without accent)', () {
      const code = 'es';
      expect(
        applyVoiceLineBreaks('Hola nuevo párrafo Adiós', languageCode: code),
        'Hola\n\nAdiós',
      );
      expect(
        applyVoiceLineBreaks('uno nueva linea dos', languageCode: code),
        'uno\ndos',
      );
      expect(
        applyVoiceLineBreaks('uno nueva línea dos', languageCode: code),
        'uno\ndos',
      );
    });

    test('pt: novo parágrafo, nova linha', () {
      const code = 'pt';
      expect(
        applyVoiceLineBreaks('Oi novo parágrafo tudo bem', languageCode: code),
        'Oi\n\nTudo bem',
      );
      expect(
        applyVoiceLineBreaks('Oi nova linha tudo bem', languageCode: code),
        'Oi\ntudo bem',
      );
    });

    test('ru: новый абзац, новая строка', () {
      const code = 'ru';
      expect(
        applyVoiceLineBreaks('привет новый абзац как дела', languageCode: code),
        'привет\n\nКак дела',
      );
      expect(
        applyVoiceLineBreaks(
          'строка один новая строка текст',
          languageCode: code,
        ),
        'строка один\nтекст',
      );
    });

    test('he: פסקה חדשה, שורה חדשה', () {
      const code = 'he';
      expect(
        applyVoiceLineBreaks('שלום פסקה חדשה מה נשמע', languageCode: code),
        'שלום\n\nמה נשמע',
      );
      expect(
        applyVoiceLineBreaks('שלום שורה חדשה מה נשמע', languageCode: code),
        'שלום\nמה נשמע',
      );
    });

    test('a known language uses only its own set', () {
      expect(_de('Hello new line world'), 'Hello new line world');
      expect(_en('Hallo neue Zeile du'), 'Hallo neue Zeile du');
    });

    test('a language without a set gets no commands', () {
      expect(
        applyVoiceLineBreaks('Bonjour new line toi', languageCode: 'fr'),
        'Bonjour new line toi',
      );
    });

    test('regional codes resolve to the base language', () {
      expect(
        applyVoiceLineBreaks('one new line two', languageCode: 'en-US'),
        'one\ntwo',
      );
    });

    test('auto-detect applies all sets', () {
      expect(
        applyVoiceLineBreaks('Hallo neue Zeile du', languageCode: 'auto'),
        'Hallo\ndu',
      );
      expect(
        applyVoiceLineBreaks('one new line two', languageCode: 'auto'),
        'one\ntwo',
      );
      expect(
        applyVoiceLineBreaks('Hola nuevo párrafo Adiós', languageCode: 'auto'),
        'Hola\n\nAdiós',
      );
    });
  });

  group('applyVoiceLineBreaks — punctuation and capitalisation', () {
    test('Hello, new paragraph. Next gives Hello,\\n\\nNext', () {
      expect(_en('Hello, new paragraph. Next'), 'Hello,\n\nNext');
    });

    test('a comma around a line command is tolerated (", new line,")', () {
      expect(_en('word, new line, next'), 'word,\nnext');
    });

    test('a capitalised, period-terminated command is tolerated', () {
      expect(_de('Hallo. Neuer Absatz. weiter'), 'Hallo.\n\nWeiter');
      expect(_de('Hallo, Neue Zeile. weiter'), 'Hallo,\nweiter');
    });

    test('hyphen or stray punctuation between the words is tolerated', () {
      expect(_de('Hallo neuer-Absatz weiter'), 'Hallo\n\nWeiter');
      expect(_en('one new. line two'), 'one\ntwo');
    });

    test('a line break after a sentence end capitalises the next word', () {
      expect(_en('This is it. new line and so on'), 'This is it.\nAnd so on');
    });

    test('a line break after a comma does not capitalise', () {
      expect(_en('This is it, new line and so on'), 'This is it,\nand so on');
    });

    test('a paragraph break always capitalises', () {
      expect(_en('one, new paragraph two'), 'one,\n\nTwo');
    });

    test('the space before a command is dropped', () {
      expect(_en('one     new line     two'), 'one\ntwo');
    });
  });

  group('applyVoiceLineBreaks — transcript start and end', () {
    test('a command at the start is dropped', () {
      expect(_de('neuer Absatz Hallo'), 'Hallo');
      expect(_en('new line hello'), 'hello');
    });

    test('a command at the end is dropped', () {
      expect(_de('Hallo neuer Absatz.'), 'Hallo');
      expect(_en('Hallo new line'), 'Hallo');
    });

    test('a transcript that is only a command is returned unchanged', () {
      expect(_en('new paragraph'), 'new paragraph');
    });
  });

  group('applyVoiceLineBreaks — consecutive commands', () {
    test(
      'a line command followed by a paragraph command is one blank line',
      () {
        expect(_en('eins new line new paragraph zwei'), 'eins\n\nZwei');
      },
    );

    test('two line commands in a row are one line break', () {
      expect(_en('eins new line new line zwei'), 'eins\nzwei');
    });

    test(
      'a paragraph command followed by a line command keeps the blank line',
      () {
        expect(_en('eins new paragraph new line zwei'), 'eins\n\nZwei');
      },
    );
  });

  group('applyVoiceLineBreaks — no false positives in longer words', () {
    test('Absatzmarke is not a command', () {
      expect(_de('Die Absatzmarke bleibt'), 'Die Absatzmarke bleibt');
      expect(_de('neuer Absatzmarke'), 'neuer Absatzmarke');
    });

    test('a compound containing the phrase is not a command', () {
      expect(
        _de('die Zeilenbreite ist neue Zeilenbreite'),
        'die Zeilenbreite ist neue Zeilenbreite',
      );
    });

    test('"newline" as one word is not a command', () {
      expect(_en('use the newline character'), 'use the newline character');
    });

    test('a different word after the trigger word is not a command', () {
      expect(_de('das sind neue Zeiten'), 'das sind neue Zeiten');
    });

    test('text without any command is returned unchanged', () {
      expect(_en('Hello world. How are you?'), 'Hello world. How are you?');
    });
  });
}

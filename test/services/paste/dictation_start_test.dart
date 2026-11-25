import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/paste/dictation_start.dart';

void main() {
  String adapt(
    String text,
    String before, {
    String? language = 'de',
    Set<String> terms = const {},
  }) => adaptDictationStart(
    text,
    before: before,
    languageCode: language,
    protectedTerms: terms,
  );

  group('case of the first letter', () {
    test('an empty field or a new line starts a sentence', () {
      expect(adapt('hallo zusammen', ''), 'Hallo zusammen');
      expect(adapt('hallo', '   '), 'Hallo');
      expect(adapt('hallo', 'Erste Zeile\n'), 'Hallo');
    });

    test('a sentence end starts a sentence, also behind a closing quote', () {
      expect(adapt('danach gehen wir', 'Das war gut. '), 'Danach gehen wir');
      expect(adapt('wirklich', 'Echt? '), 'Wirklich');
      expect(adapt('weiter', 'Sie sagte: „Gut.“ '), 'Weiter');
    });

    test('inside a sentence a listed word goes lower case', () {
      expect(adapt('Und dann', 'Wir kommen '), 'und dann');
      expect(adapt('The answer', 'This is ', language: 'en'), 'the answer');
      expect(adapt('Und dann', 'Wir kommen ', language: 'de-DE'), 'und dann');
    });

    test('names and German nouns are not on any list and stay', () {
      expect(adapt('Berlin ist schön', 'Wir mögen '), 'Berlin ist schön');
      expect(adapt('Haus am See', 'Das schöne '), 'Haus am See');
      expect(adapt('Anna called', 'Then ', language: 'en'), 'Anna called');
    });

    test('words that would change their meaning stay', () {
      expect(adapt('Sie kommen', 'Wann '), 'Sie kommen');
      expect(adapt('Ihr Termin', 'Hier ist '), 'Ihr Termin');
      expect(adapt('I think', 'Well ', language: 'en'), 'I think');
    });

    test('dictionary terms keep their spelling in both directions', () {
      expect(
        adapt('Das Projekt', 'Wir starten ', terms: {'Das'}),
        'Das Projekt',
      );
      expect(adapt('loam läuft', 'Gut. ', terms: {'loam'}), 'loam läuft');
    });

    test('a colon and an opening quote leave the case alone', () {
      expect(adapt('Das Ergebnis', 'Wichtig: '), 'Das Ergebnis');
      expect(adapt('das Ergebnis', 'Wichtig: '), 'das Ergebnis');
      expect(adapt('Das ist gut', 'Er sagte „'), 'Das ist gut');
    });

    test('mixed spelling, acronyms and non-words are never touched', () {
      expect(adapt('iPhone läuft', ''), 'iPhone läuft');
      expect(adapt('DAS Protokoll', 'Wir nutzen '), 'DAS Protokoll');
      expect(adapt('42 Tage', ''), '42 Tage');
      expect(adapt('whispaste.de ist da', ''), 'whispaste.de ist da');
    });

    test('a language without a list only ever gains a capital', () {
      expect(adapt('Und dann', 'Wir ', language: 'ru'), 'Und dann');
      expect(adapt('Und dann', 'Wir ', language: null), 'Und dann');
      expect(adapt('привет', '', language: 'ru'), 'Привет');
    });

    test('a letter without a single capital stays', () {
      expect(adapt('ßeta', ''), 'ßeta');
    });
  });

  group('gap to the text before', () {
    test('a missing space is added', () {
      expect(adapt('und dann', 'Wir kommen'), ' und dann');
      expect(adapt('Danach', 'Fertig.'), ' Danach');
    });

    test('a doubled space is removed', () {
      expect(adapt(' und dann', 'Wir kommen '), 'und dann');
      expect(adapt('  Hallo', ''), 'Hallo');
    });

    test('no space behind an opening bracket or before punctuation', () {
      expect(adapt('siehe unten', 'Text ('), 'siehe unten');
      expect(adapt(', und dann', 'Wir kommen'), ', und dann');
      expect(adapt('. Danach', 'Fertig'), '. Danach');
    });

    test('scripts without word gaps get none', () {
      expect(adapt('你好', '我们', language: 'zh'), '你好');
    });
  });

  test('a blank transcript stays as it is', () {
    expect(adapt('   ', 'Text'), '   ');
    expect(adapt('', ''), '');
  });

  test('blanks at the start of every line are dropped (#2088)', () {
    expect(
      stripLeadingLineBlanks(' Eins\n Zwei\n\n \tDrei'),
      'Eins\nZwei\n\nDrei',
    );
    expect(stripLeadingLineBlanks('Ein  Wort'), 'Ein  Wort');
  });
}

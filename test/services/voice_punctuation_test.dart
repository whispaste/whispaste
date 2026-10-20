import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/voice_punctuation.dart';

String _apply(String text, [String lang = 'de']) =>
    applyVoicePunctuation(text, languageCode: lang);

void main() {
  group('German commands', () {
    test('turns spoken marks into punctuation attached to the word before', () {
      expect(_apply('Hallo Komma wie geht es dir'), 'Hallo, wie geht es dir');
      expect(_apply('Das ist gut Punkt'), 'Das ist gut.');
      expect(_apply('Ist das so Fragezeichen'), 'Ist das so?');
      expect(_apply('Wow Ausrufezeichen'), 'Wow!');
      expect(_apply('Liste Doppelpunkt eins'), 'Liste: eins');
    });

    test('capitalises the word after a sentence end', () {
      expect(_apply('Das war gut Punkt neuer Satz'), 'Das war gut. Neuer Satz');
    });

    test('is case-insensitive and drops a mark Whisper already added', () {
      expect(_apply('hallo KOMMA welt'), 'hallo, welt');
      expect(_apply('Hallo Komma. wie'), 'Hallo, wie');
    });
  });

  group('German false positives stay text', () {
    test('compound words are not commands', () {
      expect(_apply('Das ist ein Kommando'), 'Das ist ein Kommando');
      expect(_apply('Seine Punktzahl war gut'), 'Seine Punktzahl war gut');
      expect(_apply('Die Kommas fehlen'), 'Die Kommas fehlen');
    });

    test('a noun after an article is not a command', () {
      expect(_apply('Der Punkt ist wichtig'), 'Der Punkt ist wichtig');
      expect(_apply('Wir setzen ein Komma'), 'Wir setzen ein Komma');
    });

    test('a command without a word before it is kept as text', () {
      expect(_apply('Komma allein'), 'Komma allein');
    });

    test('"um Punkt acht" is not a command', () {
      expect(
        _apply('Wir treffen uns um Punkt acht'),
        'Wir treffen uns um Punkt acht',
      );
    });
  });

  group('numbers stay numbers', () {
    test('a mark between two digit groups is written literally, no spaces', () {
      expect(_apply('Der Preis ist 3 Komma 5 Euro'), 'Der Preis ist 3,5 Euro');
      expect(_apply('Version 2 Punkt 0'), 'Version 2.0');
      expect(_apply('18 Punkt 10'), '18.10');
      expect(
        _apply('It costs 3 comma 5 dollars', 'en'),
        'It costs 3,5 dollars',
      );
      expect(_apply('cuesta 3 coma 5 euros', 'es'), 'cuesta 3,5 euros');
      expect(_apply('цена 3 запятая 5', 'ru'), 'цена 3,5');
    });

    test('IP addresses and dates keep their separators', () {
      expect(_apply('192 Punkt 168 Punkt 1 Punkt 1'), '192.168.1.1');
      expect(_apply('Am 18 Punkt 10 Punkt 2026'), 'Am 18.10.2026');
    });

    test('"point" counts as a mark only between digits', () {
      expect(_apply('Version 2 point 0', 'en'), 'Version 2.0');
      expect(_apply('2 point 5', 'auto'), '2.5');
      expect(_apply('The point of view', 'en'), 'The point of view');
    });

    test('auto detection with English, version and IP numbers', () {
      expect(_apply('Hello comma world', 'auto'), 'Hello, world');
      expect(_apply('Version 2 Punkt 0', 'auto'), 'Version 2.0');
      expect(_apply('192 Punkt 168 Punkt 1 Punkt 1', 'auto'), '192.168.1.1');
    });

    test('number words on both sides stay text', () {
      expect(_apply('drei Komma fünf'), 'drei Komma fünf');
      expect(_apply('three comma five', 'en'), 'three comma five');
    });

    test('a mix of a number word and digits stays text', () {
      expect(
        _apply('Das sind drei Komma 5 Liter'),
        'Das sind drei Komma 5 Liter',
      );
    });

    test('a number on one side only still converts', () {
      expect(_apply('Wert 3 Punkt Fazit'), 'Wert 3. Fazit');
    });
  });

  group('articles, pronouns and inflected adjectives stay text', () {
    test('German: an inflected adjective between article and noun', () {
      expect(_apply('Das ist der erste Punkt'), 'Das ist der erste Punkt');
      expect(_apply('Das ist ein guter Punkt'), 'Das ist ein guter Punkt');
      expect(_apply('Dieser alte große Punkt'), 'Dieser alte große Punkt');
    });

    test('a noun after an article converts (curated adjective list)', () {
      expect(_apply('Die Frage Punkt'), 'Die Frage.');
      expect(_apply('Ich habe die Frage Punkt'), 'Ich habe die Frage.');
    });

    test('an adjective directly before the command keeps text, no article', () {
      expect(_apply('Das ist ein buen punto', 'es'), 'Das ist ein buen punto');
      expect(_apply('Esse é bom ponto', 'pt'), 'Esse é bom ponto');
    });

    test('a noun after an article in Spanish converts', () {
      expect(_apply('la casa punto', 'es'), 'la casa.');
    });

    test('Spanish: an article and an agreeing adjective', () {
      expect(
        _apply('Este es el segundo punto', 'es'),
        'Este es el segundo punto',
      );
    });

    test('Russian: a pronoun and an inflected adjective', () {
      expect(
        _apply('Вот эта хорошая запятая', 'ru'),
        'Вот эта хорошая запятая',
      );
    });

    test('English: only the word directly after an article is checked', () {
      expect(_apply('That is the comma', 'en'), 'That is the comma');
    });
  });

  group('line breaks around a command', () {
    test('a break before the command stays after the mark', () {
      expect(_apply('Hallo\nKomma wie geht es'), 'Hallo,\nwie geht es');
    });

    test('a break after the command is kept and capitalises the next word', () {
      expect(
        _apply('Das war gut Punkt\nneuer Satz'),
        'Das war gut.\nNeuer Satz',
      );
    });

    test('spaces before a break are dropped, the break stays', () {
      expect(
        _apply('Das war gut Punkt  \nneuer Satz'),
        'Das war gut.\nNeuer Satz',
      );
    });

    test('a blank line after the command is kept', () {
      expect(
        _apply('Das war gut Punkt\n\nneuer Satz'),
        'Das war gut.\n\nNeuer Satz',
      );
    });
  });

  group('other languages', () {
    test('English', () {
      expect(_apply('Hello comma how are you', 'en'), 'Hello, how are you');
      expect(_apply('That is all full stop', 'en-US'), 'That is all.');
      expect(_apply('Is it done question mark', 'en'), 'Is it done?');
      expect(
        _apply('It was a period of time', 'en'),
        'It was a period of time',
      );
    });

    test('Spanish', () {
      expect(_apply('Hola coma qué tal', 'es'), 'Hola, qué tal');
      expect(
        _apply('Nos vemos a las tres en punto', 'es'),
        'Nos vemos a las tres en punto',
      );
      expect(_apply('Es un punto de vista', 'es'), 'Es un punto de vista');
      expect(_apply('Hola signo de interrogación', 'es'), 'Hola?');
    });

    test('Portuguese', () {
      expect(_apply('Oi vírgula tudo bem', 'pt'), 'Oi, tudo bem');
      expect(_apply('Oi ponto de interrogação', 'pt'), 'Oi?');
      expect(
        _apply('Esse é um ponto de vista', 'pt'),
        'Esse é um ponto de vista',
      );
    });

    test('Russian', () {
      expect(_apply('Привет запятая как дела', 'ru'), 'Привет, как дела');
      expect(_apply('Это точка зрения', 'ru'), 'Это точка зрения');
    });

    test('Hebrew', () {
      expect(_apply('שלום פסיק מה נשמע', 'he'), 'שלום, מה נשמע');
    });

    test('auto detection uses the union of the sets', () {
      expect(_apply('Hallo Komma welt', 'auto'), 'Hallo, welt');
      expect(_apply('Hello comma world', 'auto'), 'Hello, world');
    });

    test('a language without a set gets no commands', () {
      expect(_apply('Bonjour virgule ça va', 'fr'), 'Bonjour virgule ça va');
    });
  });

  test('text without any command is returned unchanged', () {
    expect(_apply('Ein ganz normaler Satz.'), 'Ein ganz normaler Satz.');
    expect(_apply(''), '');
  });

  group('word lookup beyond a fixed window', () {
    test('a word more than 64 characters before the command still counts', () {
      expect(_apply('Hallo${' ' * 80}Komma wie'), 'Hallo, wie');
    });

    test('a long word ending at the window edge is read whole', () {
      final long = 'Donaudampfschifffahrtsgesellschaft' * 3;
      expect(_apply('$long Komma wie'), '$long, wie');
    });
  });

  group('linearity and language switches', () {
    const chunk = 'Hallo Komma wie geht es dir Punkt das ist gut Fragezeichen ';

    int bestOf3(String text) {
      var best = 1 << 30;
      for (var run = 0; run < 3; run++) {
        final watch = Stopwatch()..start();
        _apply(text);
        watch.stop();
        if (watch.elapsedMicroseconds < best) best = watch.elapsedMicroseconds;
      }
      return best;
    }

    test('run time grows linearly with the text, not quadratically', () {
      final small = List.filled(500, chunk).join();
      final large = List.filled(2000, chunk).join(); // 4x the input
      _apply(small); // warm up the compiled matcher
      final t1 = bestOf3(small);
      final t4 = bestOf3(large);
      expect(
        t4,
        lessThan(8 * t1),
        reason: 'x4 input took $t4 us, x1 took $t1 us',
      );
    });

    test(
      'a very large dictation finishes within a generous absolute bound',
      () {
        final text = List.filled(2000, chunk).join();
        final watch = Stopwatch()..start();
        final result = _apply(text);
        watch.stop();
        expect(
          result.startsWith('Hallo, wie geht es dir. Das ist gut? Hallo, wie'),
          isTrue,
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );

    test(
      'switching between languages uses the right command set each time',
      () {
        expect(_apply('Hallo Komma welt', 'de'), 'Hallo, welt');
        expect(_apply('Hello comma world', 'en'), 'Hello, world');
        expect(_apply('Hallo Komma welt', 'de'), 'Hallo, welt');
        expect(_apply('Hello comma world', 'en'), 'Hello, world');
      },
    );
  });
}

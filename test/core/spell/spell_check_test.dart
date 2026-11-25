// Spell check logic (#670): word splitting, error tracking while typing, the
// F7 walk, language choice, the cached checker and the underline ranges.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/spell/spell_check.dart';
import 'package:whispaste/core/spell/spell_words.dart';
import 'package:whispaste/widgets/find_replace.dart' show styleRanges;

class _FakeBackend implements SpellCheckBackend {
  _FakeBackend(this.wrong);

  final Set<String> wrong;
  final List<List<String>> calls = [];

  @override
  Future<List<String>> languages() async => const ['de_DE', 'en_US'];

  @override
  Future<List<bool>> checkWords(String language, List<String> words) async {
    calls.add(List.of(words));
    return [for (final w in words) !wrong.contains(w)];
  }

  @override
  Future<List<String>> suggest(String language, String word) async => [
    '$word!',
  ];
}

List<String> _texts(List<SpellWord> words) => [for (final w in words) w.text];

void main() {
  group('spellWords', () {
    test('keeps prose words with positions and skips non-prose', () {
      final cases = <String, List<String>>{
        'Hallo Welt': ['Hallo', 'Welt'],
        "don't stop": ["don't", 'stop'],
        'E-Mail-Adresse': ['Mail', 'Adresse'],
        'a I x': [],
        'NASA und ABC': ['und'],
        'v2 abc_def 2026 ok': ['ok'],
        'siehe `codeFehler` hier': ['siehe', 'hier'],
        'Link https://exampel.org/pfad ende': ['Link', 'ende'],
        'mail an foo.bar@exampel.org bitte': ['mail', 'an', 'bitte'],
        '[Text](https://x.y/abc) weiter': ['Text', 'weiter'],
        '```\nfehlr im code\n``` danach': ['danach'],
        '你好世界 und': ['und'],
        'Café Ünïcode': ['Café', 'Ünïcode'],
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(_texts(spellWords(key)), value, reason: key);
      }
      final words = spellWords('ab cd');
      expect(words, const [SpellWord(0, 2, 'ab'), SpellWord(3, 5, 'cd')]);
    });
  });

  group('error positions', () {
    const errors = [SpellWord(0, 4, 'Hlalo'), SpellWord(10, 14, 'Wlet')];

    test('spellWordAt finds the word at the caret, end inclusive', () {
      expect(spellWordAt(errors, 0), errors[0]);
      expect(spellWordAt(errors, 4), errors[0]);
      expect(spellWordAt(errors, 7), isNull);
      expect(spellWordAt(errors, 14), errors[1]);
      expect(spellWordAt(errors, 20), isNull);
    });

    test('shiftSpellErrors keeps, moves or drops errors around an edit', () {
      const old = 'abc fehlr xyz wrot';
      const list = [SpellWord(4, 9, 'fehlr'), SpellWord(14, 18, 'wrot')];
      // Insert before both: both move.
      expect(shiftSpellErrors(list, old, 'XX$old'), const [
        SpellWord(6, 11, 'fehlr'),
        SpellWord(16, 20, 'wrot'),
      ]);
      // Edit inside the first: it is dropped, the second moves.
      expect(shiftSpellErrors(list, old, 'abc fehler xyz wrot'), const [
        SpellWord(15, 19, 'wrot'),
      ]);
      // Append after both: both stay.
      expect(shiftSpellErrors(list, old, '$old!'), list);
      // Typing a letter onto a word changes it: that error is dropped.
      expect(shiftSpellErrors(list, old, '${old}e'), [list.first]);
      expect(shiftSpellErrors(list, old, 'abc Xfehlr xyz wrot'), const [
        SpellWord(15, 19, 'wrot'),
      ]);
      expect(identical(shiftSpellErrors(list, old, old), list), isTrue);
    });

    test('nextSpellError walks on and wraps both ways', () {
      expect(nextSpellError(errors, 0, forward: true), errors[1]);
      expect(nextSpellError(errors, 12, forward: true), errors[0]);
      expect(nextSpellError(errors, 20, forward: false), errors[1]);
      expect(nextSpellError(errors, 12, forward: false), errors[0]);
      expect(nextSpellError(errors, 2, forward: false), errors[1]);
      expect(nextSpellError(const [], 0, forward: true), isNull);
    });
  });

  group('language', () {
    test('normalizeSpellTag unifies separators and case', () {
      expect(normalizeSpellTag('de_DE'), 'de-DE');
      expect(normalizeSpellTag('DE-de'), 'de-DE');
      expect(normalizeSpellTag('zh_hans_cn'), 'zh-Hans-CN');
      expect(normalizeSpellTag(' en '), 'en');
      expect(normalizeSpellTag(''), '');
    });

    test('resolveSpellLanguage picks the fitting system tag', () {
      String? pick(
        String setting, {
        String dictation = 'auto',
        String app = 'en',
        List<String> available = const ['en_GB', 'en_US', 'de_AT', 'de_DE'],
      }) => resolveSpellLanguage(
        setting: setting,
        dictationLanguage: dictation,
        appLanguage: app,
        available: available,
      );

      // Auto: dictation language first, region repeating the language wins.
      expect(pick('auto', dictation: 'de'), 'de_DE');
      // Auto without a fixed dictation language: the app language.
      expect(pick('auto'), 'en_GB');
      expect(pick('auto', available: const ['en', 'en_US']), 'en');
      // Explicit choice matched across separator styles.
      expect(pick('de-AT', dictation: 'en'), 'de_AT');
      // An unknown region of a known language falls back to that language.
      expect(pick('de-CH'), 'de_DE');
      // Nothing fits, or no checker at all.
      expect(pick('auto', app: 'ru'), isNull);
      expect(pick('auto', available: const []), isNull);
    });
  });

  group('SpellChecker', () {
    test(
      'caches answers, honours accepted words and forgets on request',
      () async {
        final backend = _FakeBackend({'Fehlr', 'Wrot'});
        final checker = SpellChecker(backend);
        final words = spellWords('Fehlr und Wrot und Fehlr');

        final first = await checker.misspelled('de_DE', words);
        expect(_texts(first), ['Fehlr', 'Wrot', 'Fehlr']);
        expect(backend.calls, [
          ['Fehlr', 'und', 'Wrot'],
        ]);

        // Same words again: answered from the cache.
        await checker.misspelled('de_DE', words);
        expect(backend.calls, hasLength(1));

        // Accepted words (lower case) count as correct.
        final accepted = await checker.misspelled(
          'de_DE',
          words,
          accepted: const {'wrot'},
        );
        expect(_texts(accepted), ['Fehlr', 'Fehlr']);

        // Another language has its own cache.
        await checker.misspelled('en_US', words);
        expect(backend.calls, hasLength(2));

        checker.forget('Fehlr');
        await checker.misspelled('de_DE', words);
        expect(backend.calls.last, ['Fehlr']);
      },
    );

    test('asks in batches of batchSize', () async {
      final backend = _FakeBackend(const {});
      final checker = SpellChecker(backend);
      final text = List.generate(
        SpellChecker.batchSize + 3,
        (i) =>
            'w${String.fromCharCode(97 + i % 26)}'
            '${String.fromCharCode(97 + i ~/ 26 % 26)}',
      ).join(' ');
      final words = spellWords(text);
      expect(
        words.map((w) => w.text).toSet().length,
        greaterThan(SpellChecker.batchSize),
      );
      await checker.misspelled('de_DE', words);
      expect(backend.calls.first, hasLength(SpellChecker.batchSize));
      expect(
        backend.calls.fold<int>(0, (n, c) => n + c.length),
        words.map((w) => w.text).toSet().length,
      );
    });
  });

  test('styleRanges splits a flat span at the error ranges', () {
    const extra = TextStyle(decoration: TextDecoration.underline);
    const tint = TextStyle(fontWeight: FontWeight.bold);
    const span = TextSpan(
      children: [
        TextSpan(text: 'abc '),
        TextSpan(text: 'defg', style: tint),
        TextSpan(text: ' hij'),
      ],
    );
    final out = styleRanges(span, const [
      TextRange(start: 2, end: 6),
      TextRange(start: 9, end: 12),
    ], extra);
    final pieces = [
      for (final c in out.children!.cast<TextSpan>())
        (
          c.text,
          c.style?.decoration == TextDecoration.underline,
          c.style?.fontWeight == FontWeight.bold,
        ),
    ];
    expect(pieces, [
      ('ab', false, false),
      ('c ', true, false),
      ('de', true, true),
      ('fg', false, true),
      (' ', false, false),
      ('hij', true, false),
    ]);
    // A nested span is left alone.
    const nested = TextSpan(
      children: [
        TextSpan(children: [TextSpan(text: 'x')]),
      ],
    );
    expect(
      identical(
        styleRanges(nested, const [TextRange(start: 0, end: 1)], extra),
        nested,
      ),
      isTrue,
    );
  });
}

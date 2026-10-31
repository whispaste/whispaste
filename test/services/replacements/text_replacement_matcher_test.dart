import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  group('applyExactReplacements', () {
    test('exact trigger is replaced, matching pre-v20 behavior', () {
      final result = applyExactReplacements('see you omw', const [
        TextReplacementRule(triggers: ['omw'], replacement: 'on my way'),
      ]);
      expect(result, 'see you on my way');
    });

    test('is case-insensitive', () {
      final result = applyExactReplacements('Sent via MFG', const [
        TextReplacementRule(
          triggers: ['mfg'],
          replacement: 'Mit freundlichen Grüßen',
        ),
      ]);
      expect(result, 'Sent via Mit freundlichen Grüßen');
    });

    test('does not match inside a longer word', () {
      final result = applyExactReplacements('reformwork', const [
        TextReplacementRule(triggers: ['form'], replacement: 'FORM'),
      ]);
      expect(result, 'reformwork');
    });

    test('fuzzy-mode rules are ignored by the exact pass', () {
      final result = applyExactReplacements('get user buy idee', const [
        TextReplacementRule(
          triggers: ['get user by id'],
          replacement: 'getUserById',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.85,
        ),
      ]);
      expect(result, 'get user buy idee');
    });
  });

  group('wordless triggers', () {
    test('a single punctuation character never fires', () {
      final result = applyExactReplacements(
        'Hallo Welt, wie geht es dir?',
        const [
          TextReplacementRule(triggers: ['?'], replacement: 'X'),
        ],
      );
      expect(result, 'Hallo Welt, wie geht es dir?');
    });

    test('a wordless trigger is replaced literally mid-sentence', () {
      final result = applyExactReplacements('Pfeil a -> b', const [
        TextReplacementRule(triggers: ['->'], replacement: '→'),
      ]);
      expect(result, 'Pfeil a → b');
    });

    test('a wordless trigger is replaced at every occurrence', () {
      final result = applyExactReplacements('a -> b -> c', const [
        TextReplacementRule(triggers: ['->'], replacement: '→'),
      ]);
      expect(result, 'a → b → c');
    });

    test('a wordless trigger is replaced inside a word', () {
      final result = applyExactReplacements('x->y', const [
        TextReplacementRule(triggers: ['->'], replacement: '→'),
      ]);
      expect(result, 'x→y');
    });

    test('ellipsis trigger is replaced literally', () {
      final result = applyExactReplacements('Warte ... und sieh', const [
        TextReplacementRule(triggers: ['...'], replacement: '…'),
      ]);
      expect(result, 'Warte … und sieh');
    });

    test('a wordless trigger is taken as literal text, not as a pattern', () {
      final result = applyExactReplacements('ab aab a.*b', const [
        TextReplacementRule(triggers: ['.*'], replacement: 'X'),
      ]);
      expect(result, 'ab aab aXb');
    });

    test('a wordless trigger does not match at every word boundary', () {
      final result = applyExactReplacements('eins zwei drei', const [
        TextReplacementRule(triggers: ['->'], replacement: '→'),
      ]);
      expect(result, 'eins zwei drei');
    });

    test('word and symbol triggers in mixed rules both take effect', () {
      final result = applyExactReplacements('omw -> ok', const [
        TextReplacementRule(triggers: ['omw'], replacement: 'on my way'),
        TextReplacementRule(triggers: ['->'], replacement: '→'),
      ]);
      expect(result, 'on my way → ok');
    });

    test('word and symbol triggers within one rule both take effect', () {
      final result = applyExactReplacements('omw -> ok', const [
        TextReplacementRule(triggers: ['omw', '->'], replacement: 'X'),
      ]);
      expect(result, 'X X ok');
    });

    test('a wordless trigger never fires in a similar-match rule', () {
      final result = applyFuzzyReplacements('a -> b .... c', const [
        TextReplacementRule(
          triggers: ['->', '....'],
          replacement: 'X',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.75,
        ),
      ]);
      expect(result, 'a -> b .... c');
    });

    test('a wordless trigger next to a real one does not match everywhere', () {
      final result = applyExactReplacements('see you omw now', const [
        TextReplacementRule(triggers: ['...', 'omw'], replacement: 'on my way'),
      ]);
      expect(result, 'see you on my way now');
    });

    test('a wordless line-break trigger does not insert breaks', () {
      final result = applyExactReplacements('a - b - c', const [
        TextReplacementRule(triggers: ['-'], replacement: r'\n'),
      ]);
      expect(result, 'a - b - c');
    });
  });

  group('applyFuzzyReplacements', () {
    test('a near-pronunciation variant is recognized', () {
      final result = applyFuzzyReplacements('call get user buy idee now', [
        const TextReplacementRule(
          triggers: ['get user by id'],
          replacement: 'getUserById',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.85,
        ),
      ]);
      expect(result, 'call getUserById now');
    });

    test('too great a distance is NOT replaced', () {
      const rule = TextReplacementRule(
        triggers: ['get user by id'],
        replacement: 'getUserById',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: 0.85,
      );
      final result = applyFuzzyReplacements(
        'completely unrelated sentence here',
        [rule],
      );
      expect(result, 'completely unrelated sentence here');
    });

    test('strict rejects what tolerant accepts for the same input', () {
      const text = 'get user buy idee';
      const strict = TextReplacementRule(
        triggers: ['get user by id'],
        replacement: 'getUserById',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: 0.92,
      );
      const tolerant = TextReplacementRule(
        triggers: ['get user by id'],
        replacement: 'getUserById',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: 0.75,
      );

      expect(applyFuzzyReplacements(text, [strict]), text);
      expect(applyFuzzyReplacements(text, [tolerant]), 'getUserById');
    });

    test('a window scoring exactly at the threshold is accepted', () {
      // "über" vs "uber" scores exactly 0.75 (LCS 3 over 4+4 code points).
      const text = 'die über';
      const atThreshold = TextReplacementRule(
        triggers: ['uber'],
        replacement: 'Uber',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: 0.75,
      );
      const justAbove = TextReplacementRule(
        triggers: ['uber'],
        replacement: 'Uber',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: 0.76,
      );

      expect(applyFuzzyReplacements(text, [atThreshold]), 'die Uber');
      expect(applyFuzzyReplacements(text, [justAbove]), text);
    });

    test('target phrases below the minimum length are never fuzzy-matched', () {
      const text = 'the id is missing';
      const rule = TextReplacementRule(
        triggers: ['id'],
        replacement: 'ID',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: 0.5,
      );
      expect(applyFuzzyReplacements(text, [rule]), text);
    });

    test('overlapping candidates keep the higher-scoring one', () {
      // "getUserById" and "getUserByld" both score highly against the exact
      // phrase; only one (non-overlapping) replacement must land.
      final result = applyFuzzyReplacements('please get user by id here', [
        const TextReplacementRule(
          triggers: ['get user by id'],
          replacement: 'getUserById',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.85,
        ),
      ]);
      expect(result, 'please getUserById here');
    });

    test('exact-mode rules are ignored by the fuzzy pass', () {
      const text = 'see you omw';
      const rule = TextReplacementRule(
        triggers: ['omw'],
        replacement: 'on my way',
      );
      expect(applyFuzzyReplacements(text, [rule]), text);
    });
  });

  group('applyTextReplacements (combined pipeline)', () {
    test('runs exact then fuzzy, both taking effect', () {
      final result = applyTextReplacements('omw to get user buy idee', const [
        TextReplacementRule(triggers: ['omw'], replacement: 'on my way'),
        TextReplacementRule(
          triggers: ['get user by id'],
          replacement: 'getUserById',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.85,
        ),
      ]);
      expect(result, 'on my way to getUserById');
    });
  });

  group('replacement escapes', () {
    test(r'\n in the replacement inserts a line break', () {
      final result = applyExactReplacements('Gruß sig', const [
        TextReplacementRule(triggers: ['sig'], replacement: r'Best\n\nMax'),
      ]);
      expect(result, 'Gruß Best\n\nMax');
    });

    test(r'\\n stays a literal backslash-n', () {
      final result = applyExactReplacements('set dir', const [
        TextReplacementRule(triggers: ['dir'], replacement: r'Pfad\\n'),
      ]);
      expect(result, 'set Pfad\\n');
    });

    test(r'\\ in the replacement inserts one backslash', () {
      final result = applyExactReplacements('x path', const [
        TextReplacementRule(triggers: ['path'], replacement: r'C:\\new'),
      ]);
      expect(result, 'x C:\\new');
    });

    test('other backslashes are kept as typed', () {
      final result = applyExactReplacements('x go', const [
        TextReplacementRule(triggers: ['go'], replacement: r'a\tb'),
      ]);
      expect(result, r'x a\tb');
    });

    test('spaces around an inserted break are dropped, runs stay intact', () {
      final result = applyExactReplacements('hi there', const [
        TextReplacementRule(triggers: ['hi'], replacement: r'Hallo \n Welt'),
      ]);
      expect(result, 'Hallo\nWelt there');
    });

    test('a run of line breaks is not collapsed', () {
      final result = applyExactReplacements('x y', const [
        TextReplacementRule(triggers: ['y'], replacement: r'a\n\n\nb'),
      ]);
      expect(result, 'x a\n\n\nb');
    });

    test('"Hello, new paragraph. Next" gives "Hello,\\n\\nNext"', () {
      final result = applyExactReplacements(
        'Hello, new paragraph. Next',
        const [
          TextReplacementRule(
            triggers: ['new paragraph'],
            replacement: r'\n\n',
          ),
        ],
      );
      expect(result, 'Hello,\n\nNext');
    });

    test('glue is only taken on the side that has the break', () {
      // Replacement starts with text, ends with a break: the space before
      // the trigger stays, the punctuation after it goes.
      final result = applyExactReplacements('Hi sig. Next', const [
        TextReplacementRule(triggers: ['sig'], replacement: r'Best\n'),
      ]);
      expect(result, 'Hi Best\nNext');
    });

    test('a plain replacement keeps its punctuation and spaces', () {
      final result = applyExactReplacements('Hello, btw. Next', const [
        TextReplacementRule(triggers: ['btw'], replacement: 'by the way'),
      ]);
      expect(result, 'Hello, by the way. Next');
    });

    test('fuzzy line-break replacement takes the same glue', () {
      final result = applyFuzzyReplacements('Hello, new paragrph. Next', const [
        TextReplacementRule(
          triggers: ['new paragraph'],
          replacement: r'\n\n',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.85,
        ),
      ]);
      expect(result, 'Hello,\n\nNext');
    });
  });

  group('CompiledTextReplacements and CompiledRulesCache', () {
    List<TextReplacementRule> exactRules(int count) => [
      for (var i = 0; i < count; i++)
        TextReplacementRule(triggers: ['zzterm$i'], replacement: 'Ersatz$i'),
    ];

    test('the fuzzy pass stops at its window budget, deterministically', () {
      const sentence =
          'Das ist ein ganz normaler Satz mit Wörtern zur Prüfung. ';
      final buffer = StringBuffer();
      while (buffer.length < 300) {
        buffer.write(sentence);
      }
      final text = buffer.toString();
      final rules = [
        for (var i = 0; i < 1000; i++)
          TextReplacementRule(
            triggers: ['zzfuzzy$i begriff'],
            replacement: 'Ersatz$i',
            matchMode: TextReplacementMatchMode.fuzzy,
            fuzzyThreshold: 0.85,
          ),
      ];
      final compiled = CompiledTextReplacements(rules, fuzzyWindowBudget: 50);
      final first = compiled.applyFuzzyOnly(text);
      expect(compiled.fuzzyBudgetExceeded, isTrue);
      expect(compiled.applyFuzzyOnly(text), first);
    });

    test('a rule can match a word that an earlier rule just inserted', () {
      final compiled = CompiledTextReplacements([
        const TextReplacementRule(triggers: ['alpha'], replacement: 'beta'),
        const TextReplacementRule(triggers: ['beta'], replacement: 'gamma'),
      ]);
      expect(compiled.apply('alpha'), 'gamma');
    });

    test('the cache recompiles only when a rule changes', () {
      final cache = CompiledRulesCache();
      final rules = exactRules(3);
      final first = cache.forRules(rules);
      expect(identical(cache.forRules(exactRules(3)), first), isTrue);
      final changed = [
        ...rules,
      ]..[1] = const TextReplacementRule(triggers: ['other'], replacement: 'x');
      expect(identical(cache.forRules(changed), first), isFalse);
    });
  });
}

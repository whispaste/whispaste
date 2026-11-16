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

  group('exactFallbackTriggers', () {
    const fuzzy = TextReplacementMatchMode.fuzzy;
    test('names the short and wordless triggers of a similar entry', () {
      expect(exactFallbackTriggers(fuzzy, ['WhisPaste', 'WP', '...', '']), [
        'WP',
        '...',
      ]);
    });
    test('an entry with only long triggers is not affected', () {
      expect(
        exactFallbackTriggers(fuzzy, ['WhisPaste', 'Kubernetes']),
        isEmpty,
      );
    });
    test('an exact entry is never affected', () {
      expect(
        exactFallbackTriggers(TextReplacementMatchMode.exact, ['WP']),
        isEmpty,
      );
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

    test('punctuation next to a fuzzy match is kept', () {
      const rule = TextReplacementRule(
        triggers: ['whispaste'],
        replacement: 'WhisPaste',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: fuzzyThresholdStrict,
      );
      expect(
        applyFuzzyReplacements('Ich nutze Whis Paste.', [rule]),
        'Ich nutze WhisPaste.',
      );
      expect(
        applyFuzzyReplacements('Siehe (whispaste), danach', [rule]),
        'Siehe (WhisPaste), danach',
      );
    });

    test('a trigger with outer punctuation matches its words', () {
      const rule = TextReplacementRule(
        triggers: ['"whispaste"'],
        replacement: 'WhisPaste',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: fuzzyThresholdStrict,
      );
      expect(
        applyFuzzyReplacements('mit whispaste!', [rule]),
        'mit WhisPaste!',
      );
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

    test('a short trigger of a similar entry fires exactly, not by sound', () {
      const rule = TextReplacementRule(
        triggers: ['WhisPaste', 'WP'],
        replacement: 'WhisPaste',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: fuzzyThresholdStrict,
      );
      expect(
        applyTextReplacements('open wp now', [rule]),
        'open WhisPaste now',
      );
      // Not similar: a near miss of the short trigger stays untouched.
      expect(applyTextReplacements('open wq now', [rule]), 'open wq now');
      // The long trigger of the same entry stays similar.
      expect(
        applyTextReplacements('open Whis Paste now', [rule]),
        'open WhisPaste now',
      );
    });

    test('exact fallback of a similar entry runs in the exact pass', () {
      const similar = TextReplacementRule(
        triggers: ['WhisPaste', 'WP'],
        replacement: 'X',
        matchMode: TextReplacementMatchMode.fuzzy,
        fuzzyThreshold: fuzzyThresholdStrict,
      );
      // The fuzzy pass alone never sees the short trigger.
      expect(applyFuzzyReplacements('open wp', [similar]), 'open wp');
      expect(applyExactReplacements('open wp', [similar]), 'open X');
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

    group('another word form is not a recognition error', () {
      TextReplacementRule strict(String trigger, String replacement) =>
          TextReplacementRule(
            triggers: [trigger],
            replacement: replacement,
            matchMode: TextReplacementMatchMode.fuzzy,
            fuzzyThreshold: fuzzyThresholdStrict,
          );

      test('the trigger plus appended letters is left alone', () {
        expect(
          applyFuzzyReplacements('Die Projekte laufen.', [
            strict('projekt', 'Projekt X'),
          ]),
          'Die Projekte laufen.',
        );
        expect(
          applyFuzzyReplacements('zwei Containern', [
            strict('container', 'Container'),
          ]),
          'zwei Containern',
        );
        expect(
          applyFuzzyReplacements('alle Meetings heute', [
            strict('meeting', 'Jour fixe'),
          ]),
          'alle Meetings heute',
        );
      });

      test('the window plus appended letters is left alone', () {
        expect(
          applyFuzzyReplacements('jeden Freitag', [
            strict('freitags', 'freitags (remote)'),
          ]),
          'jeden Freitag',
        );
      });

      test(
        'another form of one word in a multi-word trigger is left alone',
        () {
          expect(
            applyFuzzyReplacements('neue Projekte Ideen sammeln', [
              strict('projekt ideen', 'Projektideen'),
            ]),
            'neue Projekte Ideen sammeln',
          );
          expect(
            applyFuzzyReplacements('the weekly meetings notes', [
              strict('weekly meeting notes', 'Jour fixe notes'),
            ]),
            'the weekly meetings notes',
          );
        },
      );

      test('only a typical ending makes a word form (maintainer '
          '2026-11-01)', () {
        // "r" is no ending in any app language: a recognition error.
        expect(
          applyFuzzyReplacements('ich teste whispe paste heute', [
            strict('whisper paste', 'WhisPaste'),
          ]),
          'ich teste WhisPaste heute',
        );
        // "e" is a German plural ending: another form, left alone.
        expect(
          applyFuzzyReplacements('der Projekte Plan', [
            strict('projekt plan', 'Projektplan'),
          ]),
          'der Projekte Plan',
        );
      });

      test('each app language has its endings', () {
        for (final (text, trigger) in const [
          ('die Projekte', 'projekt'), // de
          ('all meetings', 'meeting'), // en
          ('los proyectos', 'proyecto'), // es
          ('os projetos', 'projeto'), // pt
          ('новые проекты', 'проект'), // ru
          ('הוא סטודנטי', 'סטודנט'), // he
        ]) {
          expect(
            applyFuzzyReplacements(text, [strict(trigger, 'X')]),
            text,
            reason: trigger,
          );
        }
      });

      test('a misheard word in a multi-word trigger still matches', () {
        expect(
          applyFuzzyReplacements('neue Projekt Ideeen sammeln', [
            strict('projekt ideen', 'Projektideen'),
          ]),
          'neue Projektideen sammeln',
        );
      });

      test('a misheard word still matches', () {
        // An inserted letter inside the word, not at its end.
        expect(
          applyFuzzyReplacements('wir nutzen Whispaaste.', [
            strict('whispaste', 'WhisPaste'),
          ]),
          'wir nutzen WhisPaste.',
        );
      });

      test('the trigger itself still matches in any case', () {
        expect(
          applyFuzzyReplacements('das Projekt', [
            strict('projekt', 'Projekt X'),
          ]),
          'das Projekt X',
        );
      });
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

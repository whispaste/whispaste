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
}

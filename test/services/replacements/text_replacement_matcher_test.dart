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
}

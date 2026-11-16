import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  group('literal special-character triggers', () {
    for (final trigger in [
      'C++',
      '.NET',
      '@handle',
      'a.b+c@example.org',
      '-flag',
      'flag-',
    ]) {
      test('$trigger keeps every special character', () {
        final rules = [
          TextReplacementRule(triggers: [trigger], replacement: '結果'),
        ];
        expect(
          applyExactReplacements('$trigger ($trigger)!', rules),
          '結果 (結果)!',
        );
        for (final neighbor in ['é', 'Ж', '中', 'א', '𐐀', '7', '_', '\u0301']) {
          final embedded = '$neighbor$trigger $trigger$neighbor';
          expect(applyExactReplacements(embedded, rules), embedded);
        }
      });
    }

    test('missing or changed symbols do not fire a literal trigger', () {
      expect(
        applyExactReplacements('C C+ NET handle a b c example org', const [
          TextReplacementRule(
            triggers: ['C++', '.NET', '@handle', 'a.b+c@example.org'],
            replacement: 'X',
          ),
        ]),
        'C C+ NET handle a b c example org',
      );
    });

    test('combining marks and mixed scripts form whole words', () {
      expect(
        applyExactReplacements('cafe\u0301 東京Ж @שלום', const [
          TextReplacementRule(triggers: ['cafe'], replacement: 'wrong'),
          TextReplacementRule(triggers: ['東京'], replacement: 'wrong'),
          TextReplacementRule(triggers: ['@שלום'], replacement: 'héllo++'),
        ]),
        'cafe\u0301 東京Ж héllo++',
      );
      expect(
        applyExactReplacements('cafe\u0301', const [
          TextReplacementRule(triggers: ['cafe\u0301'], replacement: 'coffee'),
        ]),
        'coffee',
      );
    });

    test('spoken phrase separators remain flexible', () {
      expect(
        applyExactReplacements('new—paragraph new  paragraph', const [
          TextReplacementRule(triggers: ['new paragraph'], replacement: 'X'),
        ]),
        'X X',
      );
    });
  });

  group('longest trigger across rules', () {
    test('a shorter prefix or suffix never hides a longer trigger', () {
      const short = TextReplacementRule(
        triggers: ['York', 'New'],
        replacement: 'short',
      );
      const long = TextReplacementRule(
        triggers: ['New York'],
        replacement: 'NYC',
      );
      for (final rules in [
        [short, long],
        [long, short],
      ]) {
        expect(applyExactReplacements('New York, York', rules), 'NYC, short');
      }
    });

    test('priority uses each trigger, including overlapping occurrences', () {
      const rules = [
        TextReplacementRule(
          triggers: ['unrelated very long phrase', 'a b'],
          replacement: 'short',
        ),
        TextReplacementRule(triggers: ['b c d'], replacement: 'long'),
      ];
      final hits = [0, 0];
      expect(
        applyExactReplacements('a b c d a b', rules, hits: hits),
        'a long short',
      );
      expect(hits, [1, 1]);
      expect(
        applyExactReplacements('a b a b a', const [
          TextReplacementRule(triggers: ['a b a'], replacement: 'X'),
          TextReplacementRule(triggers: ['a b'], replacement: 'Y'),
        ]),
        'X b a',
      );
    });

    test('equal-length ties use rule order and count only the winner', () {
      final hits = [0, 0];
      expect(
        applyExactReplacements('東京 Ж', const [
          TextReplacementRule(triggers: ['東京 Ж'], replacement: 'first'),
          TextReplacementRule(triggers: ['東京 Ж'], replacement: 'second'),
        ], hits: hits),
        'first',
      );
      expect(hits, [1, 0]);
    });

    test('short fuzzy fallbacks participate in the same exact selection', () {
      expect(
        applyTextReplacements('C++ guide', const [
          TextReplacementRule(
            triggers: ['C++'],
            replacement: 'short',
            matchMode: TextReplacementMatchMode.fuzzy,
          ),
          TextReplacementRule(triggers: ['C++ guide'], replacement: 'long'),
        ]),
        'long',
      );
    });

    test('line-break glue cannot swallow an adjacent symbol trigger', () {
      expect(
        applyExactReplacements('new paragraph... Next', const [
          TextReplacementRule(triggers: ['new paragraph'], replacement: r'\n'),
          TextReplacementRule(triggers: ['...'], replacement: 'ellipsis'),
        ]),
        '\nellipsis Next',
      );
    });
  });

  group('cascade in rule order', () {
    test('later rules replace text earlier rules inserted', () {
      const rules = [
        TextReplacementRule(triggers: ['alpha'], replacement: 'C++'),
        TextReplacementRule(triggers: ['C++'], replacement: '東京 Ж'),
        TextReplacementRule(triggers: ['東京 Ж'], replacement: 'done'),
      ];
      final hits = [0, 0, 0];
      expect(applyExactReplacements('alpha', rules, hits: hits), 'done');
      expect(hits, [1, 1, 1]);
      // Reverse order does not cascade.
      expect(applyExactReplacements('alpha', rules.reversed.toList()), 'C++');
    });

    test('one rule does not rematch its own output', () {
      expect(
        applyExactReplacements('a', const [
          TextReplacementRule(triggers: ['a'], replacement: 'a a'),
        ]),
        'a a',
      );
    });

    test('longest-first still holds when the long rule comes later', () {
      expect(
        applyExactReplacements('New York', const [
          TextReplacementRule(triggers: ['New'], replacement: 'Old'),
          TextReplacementRule(triggers: ['New York'], replacement: 'NYC'),
          TextReplacementRule(triggers: ['NYC'], replacement: 'Big Apple'),
        ]),
        'Big Apple',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/utils/string_similarity.dart';

void main() {
  group('stringSimilarity', () {
    test('identical strings score 1.0', () {
      expect(stringSimilarity('whispaste', 'whispaste'), 1.0);
    });

    test('two empty strings score 1.0', () {
      expect(stringSimilarity('', ''), 1.0);
    });

    test('an empty string against a non-empty one scores 0.0', () {
      expect(stringSimilarity('', 'abc'), 0.0);
      expect(stringSimilarity('abc', ''), 0.0);
    });

    test('completely disjoint strings score 0.0', () {
      expect(stringSimilarity('abc', 'xyz'), 0.0);
    });

    test('kitten/sitting: LCS "ittn" (4) gives 2*4/(6+7) = 8/13', () {
      expect(stringSimilarity('kitten', 'sitting'), closeTo(8 / 13, 1e-12));
    });

    test('abc/abd: LCS "ab" (2) gives 4/6', () {
      expect(stringSimilarity('abc', 'abd'), closeTo(4 / 6, 1e-12));
    });

    test('is symmetric', () {
      expect(
        stringSimilarity('kitten', 'sitting'),
        stringSimilarity('sitting', 'kitten'),
      );
      expect(
        stringSimilarity('ab', 'abcdef'),
        stringSimilarity('abcdef', 'ab'),
      );
    });

    test('does not fold case (callers lowercase)', () {
      // LCS "itten" (5) over 6+6 code points: 10/12.
      expect(stringSimilarity('Kitten', 'kitten'), closeTo(10 / 12, 1e-12));
    });

    test('umlaut counts as one code point', () {
      // "über" vs "uber": LCS "ber" (3), 2*3/(4+4) = 0.75 exactly.
      expect(stringSimilarity('über', 'uber'), 0.75);
    });

    test('compares Unicode code points, not UTF-16 code units', () {
      // Emoji is one code point but two UTF-16 units. By code points:
      // LCS 1 over 2+2 gives 0.5. By UTF-16 units it would be 4/6.
      expect(stringSimilarity('😀a', '😀b'), 0.5);
    });

    test('always stays within 0.0..1.0', () {
      const samples = ['', 'a', 'ab', 'Größe', '😀😀', 'lorem ipsum', 'x'];
      for (final a in samples) {
        for (final b in samples) {
          final s = stringSimilarity(a, b);
          expect(s, inInclusiveRange(0.0, 1.0), reason: '"$a" vs "$b"');
        }
      }
    });
  });
}

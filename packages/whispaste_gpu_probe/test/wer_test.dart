import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/src/wer.dart';

void main() {
  group('normalizeForWer', () {
    test('lowercases text', () {
      expect(normalizeForWer('Hello World'), equals('hello world'));
    });

    test('removes punctuation', () {
      expect(normalizeForWer('Hello, world!'), equals('hello world'));
    });

    test('collapses whitespace', () {
      expect(normalizeForWer('  hello   world  '), equals('hello world'));
    });

    test('handles mixed casing, punctuation, and whitespace', () {
      expect(
        normalizeForWer('  The Quick, Brown Fox.  '),
        equals('the quick brown fox'),
      );
    });
  });

  group('computeWer — golden tests (AC2)', () {
    test('identical transcripts → 0.0', () {
      expect(computeWer('hello world', 'hello world'), equals(0.0));
    });

    test('completely wrong hypothesis → 1.0', () {
      // reference: "one two three" (3 words), hypothesis: "x y z" (3 wrong words)
      // 3 substitutions / 3 reference words = 1.0
      expect(computeWer('x y z', 'one two three'), equals(1.0));
    });

    test('1 substitution in 4-word reference → 0.25', () {
      // reference: "the cat sat here", hypothesis: "the cat sat there"
      // 1 substitution / 4 reference words = 0.25
      expect(computeWer('the cat sat there', 'the cat sat here'), equals(0.25));
    });

    test('1 insertion (extra word in hypothesis) → 0.25', () {
      // reference: "the cat sat" (3 words), hypothesis: "the big cat sat" (4 words)
      // 1 insertion / 3 reference words ≈ 0.333...
      final wer = computeWer('the big cat sat', 'the cat sat');
      expect(wer, closeTo(1.0 / 3.0, 1e-9));
    });

    test('1 deletion (missing word in hypothesis) → 0.25', () {
      // reference: "the cat sat here" (4 words), hypothesis: "the cat here" (3 words)
      // 1 deletion / 4 reference words = 0.25
      expect(computeWer('the cat here', 'the cat sat here'), equals(0.25));
    });
  });

  group('computeWer — edge cases', () {
    test('AC3: empty hypothesis vs non-empty reference → 1.0', () {
      expect(computeWer('', 'hello world'), equals(1.0));
    });

    test('both empty → 0.0', () {
      expect(computeWer('', ''), equals(0.0));
    });

    test(
      'non-empty hypothesis vs empty reference → 0.0 (no reference words)',
      () {
        // edge: empty reference has 0 words → WER is defined as 0.0 by convention
        expect(computeWer('hello', ''), equals(0.0));
      },
    );

    test('AC4: deterministic — same inputs always produce same output', () {
      final wer1 = computeWer('hello world', 'hello there');
      final wer2 = computeWer('hello world', 'hello there');
      expect(wer1, equals(wer2));
    });

    test('normalization applied — casing and punctuation ignored', () {
      // "Hello, World!" vs "hello world" → identical after normalization → WER 0.0
      expect(computeWer('Hello, World!', 'hello world'), equals(0.0));
    });
  });
}

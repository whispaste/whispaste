import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/floating_overlay/live_text_tail.dart';

void main() {
  bool fitsChars(String s, int max) => s.length <= max;

  group('tailThatFits', () {
    test('returns text unchanged when it already fits', () {
      expect(tailThatFits('Hallo Welt', (s) => fitsChars(s, 20)), 'Hallo Welt');
    });

    test('returns empty text unchanged', () {
      expect(tailThatFits('', (s) => fitsChars(s, 5)), '');
    });

    test('keeps the newest words behind a leading ellipsis', () {
      const text = 'eins zwei drei vier fünf sechs sieben';
      final result = tailThatFits(text, (s) => fitsChars(s, 20));
      expect(result, '…fünf sechs sieben');
      expect(result, isNot(contains('vier')));
    });

    test('keeps as many trailing words as fit (longest fitting tail)', () {
      const text = 'a bb ccc dddd eeeee';
      // "…dddd eeeee" = 11 chars, "…ccc dddd eeeee" = 15 chars.
      expect(tailThatFits(text, (s) => fitsChars(s, 14)), '…dddd eeeee');
      expect(tailThatFits(text, (s) => fitsChars(s, 15)), '…ccc dddd eeeee');
    });

    test('trims a single over-long last word from its start', () {
      const text = 'kurz Donaudampfschifffahrtsgesellschaft';
      final result = tailThatFits(text, (s) => fitsChars(s, 10));
      expect(result, '…ellschaft');
      expect(result.length, lessThanOrEqualTo(10));
      expect(text.endsWith(result.substring(1)), isTrue);
    });

    test('collapses whitespace runs and trims the input', () {
      expect(
        tailThatFits('  eins   zwei\n drei  ', (s) => fitsChars(s, 40)),
        'eins zwei drei',
      );
    });
  });
}

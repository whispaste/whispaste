import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/utils/word_count.dart';

/// The pre-optimization implementation, kept here only as a regression
/// oracle: `computeWordCountFast` must agree with it on every case below,
/// since it replaced this exact expression at five call sites.
int _legacyWordCount(String text) {
  final t = text.trim();
  return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
}

/// Builds `'hello<sep>world'` (and `<sep>again` variants) from an explicit
/// code point, never a literal typed character - several of the separators
/// under test (VT, FF, U+2028/2029, U+2000-U+200A) are invisible/uneditable
/// in a normal editor and would be unverifiable if typed directly.
String _joinedBy(List<String> words, int separatorCodeUnit) {
  return words.join(String.fromCharCode(separatorCodeUnit));
}

void main() {
  group('computeWordCountFast', () {
    test('empty string is zero words', () {
      expect(computeWordCountFast(''), 0);
    });

    test('whitespace-only string is zero words', () {
      expect(computeWordCountFast('   \t\n  '), 0);
    });

    test('counts simple space-separated words', () {
      expect(computeWordCountFast('hello world'), 2);
    });

    test('collapses runs of whitespace', () {
      expect(computeWordCountFast('hello    world'), 2);
    });

    test('ignores leading and trailing whitespace', () {
      expect(computeWordCountFast('  hello world  '), 2);
    });

    test('counts across newlines and tabs', () {
      expect(computeWordCountFast('line one\nline\ttwo'), 4);
    });

    test('single word has no separators', () {
      expect(computeWordCountFast('word'), 1);
    });

    // Regression coverage for the gap in the original fast-path (which only
    // checked space/tab/LF/CR via bare code-unit comparison): non-breaking
    // space and other Unicode space separators must still count as word
    // boundaries, matching `RegExp(r'\s+')` - otherwise pasted web content
    // (NBSP is extremely common there) silently undercounts in the editable
    // transcript view (history_detail_panel.dart).
    test('non-breaking space (U+00A0) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x00A0)), 2);
    });

    test('vertical tab (U+000B) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x000B)), 2);
    });

    test('form feed (U+000C) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x000C)), 2);
    });

    test('Unicode space separators (U+2000-U+200A) separate words', () {
      for (var cu = 0x2000; cu <= 0x200A; cu++) {
        expect(
          computeWordCountFast(_joinedBy(['hello', 'world'], cu)),
          2,
          reason: 'U+${cu.toRadixString(16)} should separate words',
        );
      }
    });

    test('ideographic space (U+3000) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x3000)), 2);
    });

    test('line separator (U+2028) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x2028)), 2);
    });

    test('paragraph separator (U+2029) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x2029)), 2);
    });

    test('narrow no-break space (U+202F) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x202F)), 2);
    });

    test('medium mathematical space (U+205F) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x205F)), 2);
    });

    test('BOM/zero-width no-break space (U+FEFF) separates words', () {
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0xFEFF)), 2);
    });

    test('Mongolian vowel separator (U+180E) is NOT whitespace', () {
      // Unlike every code point above, U+180E was reclassified out of \s in
      // modern Unicode/regex semantics - this pins the exclusion rather than
      // assuming it, so "join everything in range" logic can't creep back in.
      expect(computeWordCountFast(_joinedBy(['hello', 'world'], 0x180E)), 1);
    });

    test('agrees with the legacy regex implementation across ASCII cases', () {
      final cases = [
        '',
        '   ',
        'hello world',
        '  leading and trailing  ',
        'multiple    internal   spaces',
        'line\nbreaks\nhere',
        'tabs\ttoo',
        'emoji 🎙️ transcript works too',
        'a',
        'a b',
      ];
      for (final c in cases) {
        expect(
          computeWordCountFast(c),
          _legacyWordCount(c),
          reason: 'mismatch for input: ${c.codeUnits}',
        );
      }
    });

    test(
      'agrees with the legacy regex implementation for NBSP-joined text',
      () {
        final joined = _joinedBy(['hello', 'world', 'again'], 0x00A0);
        expect(computeWordCountFast(joined), _legacyWordCount(joined));
      },
    );
  });
}

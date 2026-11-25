import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/markdown_outline.dart';

void main() {
  group('markdownOutline', () {
    test('reads ATX headings with level, title and line span', () {
      const text = '# Intro\nbody\n\n## Part **one** ##\ntext\n### Deep';
      final outline = markdownOutline(text);
      expect(outline.map((h) => h.level), [1, 2, 3]);
      expect(outline.map((h) => h.title), ['Intro', 'Part one', 'Deep']);
      expect(outline[0].start, 0);
      expect(outline[0].end, '# Intro'.length);
      expect(
        text.substring(outline[1].start, outline[1].end),
        startsWith('##'),
      );
      expect(outline[2].end, text.length);
    });

    test('skips fenced code, escaped and non-heading hashes', () {
      const text =
          '```\n# not a heading\n```\n'
          r'\# escaped'
          '\n#hashtag\n    # indented code\n## Real';
      final outline = markdownOutline(text);
      expect(outline.map((h) => h.title), ['Real']);
    });

    test('a longer fence is only closed by one as long', () {
      const text = '````\n```\n# inside\n````\n# after';
      expect(markdownOutline(text).map((h) => h.title), ['after']);
    });

    test('keeps CRLF out of the span and allows an empty heading', () {
      const text = '# A\r\n#\r\nrest';
      final outline = markdownOutline(text);
      expect(outline, hasLength(2));
      expect(outline[0].end, 3);
      expect(outline[1].title, isEmpty);
      expect(outline[1].start, 5);
      expect(outline[1].end, 6);
    });

    test('text without headings has an empty outline', () {
      expect(markdownOutline(''), isEmpty);
      expect(markdownOutline('Just a dictation.\nSecond line.'), isEmpty);
    });
  });

  group('next and previous heading', () {
    const text = 'lead\n# A\nbody a\n## B\nbody b';
    final outline = markdownOutline(text);
    final inBodyA = text.indexOf('body a') + 2;
    final atEndOfB = outline[1].end;

    test('next is the first heading after the caret line', () {
      expect(nextHeadingIndex(outline, 0), 0);
      expect(nextHeadingIndex(outline, inBodyA), 1);
      // Right after a jump the caret sits at the heading's end.
      expect(nextHeadingIndex(outline, outline[0].end), 1);
      expect(nextHeadingIndex(outline, atEndOfB), isNull);
    });

    test('previous is the own section heading from the body, else the one '
        'before', () {
      expect(previousHeadingIndex(outline, text, inBodyA), 0);
      expect(previousHeadingIndex(outline, text, atEndOfB), 0);
      expect(previousHeadingIndex(outline, text, outline[0].end), isNull);
      expect(previousHeadingIndex(outline, text, 2), isNull);
      expect(previousHeadingIndex(outline, text, text.length), 1);
    });

    test('the heading at the caret is the last one starting before it', () {
      expect(outlineIndexAt(outline, 0), -1);
      expect(outlineIndexAt(outline, inBodyA), 0);
      expect(outlineIndexAt(outline, text.length), 1);
    });
  });
}

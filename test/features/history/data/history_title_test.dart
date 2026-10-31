/// Unit tests for [deriveHistoryTitle] — pure title derivation from content.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/data/history_title.dart';

void main() {
  group('deriveHistoryTitle', () {
    test('returns the trimmed content when at or under 60 characters', () {
      expect(
        deriveHistoryTitle('  Great, thanks for the quick turnaround.  '),
        'Great, thanks for the quick turnaround.',
      );
    });

    test('returns empty string for empty content', () {
      expect(deriveHistoryTitle(''), '');
    });

    test('returns empty string for whitespace-only content', () {
      expect(deriveHistoryTitle('   \n  \t'), '');
    });

    test('cuts at the last word boundary within 60 chars and appends an '
        'ellipsis when the boundary is past position 20', () {
      const content =
          'This is a fairly long sentence that will definitely need to be '
          'truncated for the title.';
      final title = deriveHistoryTitle(content);
      expect(title.endsWith('…'), isTrue);
      expect(title.length, lessThanOrEqualTo(61)); // 60 chars + ellipsis
      expect(content.startsWith(title.substring(0, title.length - 1)), isTrue);
    });

    test('falls back to a hard cut at 60 chars when there is no word boundary '
        'past position 20 (single long "word")', () {
      final content = 'a' * 100;
      final title = deriveHistoryTitle(content);
      expect(title, '${'a' * 60}…');
    });

    test('does not truncate content at exactly 60 characters', () {
      final content = 'a' * 60;
      expect(deriveHistoryTitle(content), content);
    });

    test('line breaks from spoken paragraphs become spaces in the title', () {
      expect(
        deriveHistoryTitle('Sehr geehrte Damen,\n\nvielen Dank.'),
        'Sehr geehrte Damen, vielen Dank.',
      );
    });
  });
}

/// Unit tests for [deriveNoteTitle] — pure title derivation from content.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_title.dart';

void main() {
  group('deriveNoteTitle', () {
    test('returns null for empty content', () {
      expect(deriveNoteTitle(''), isNull);
    });

    test('returns null for whitespace-only content', () {
      expect(deriveNoteTitle('   \n  \n\t'), isNull);
    });

    test('returns the single line, trimmed', () {
      expect(deriveNoteTitle('  Grocery list  '), 'Grocery list');
    });

    test('returns the first non-blank line, ignoring the rest', () {
      expect(
        deriveNoteTitle('Meeting notes\nDiscussed Q3 goals\nAction items'),
        'Meeting notes',
      );
    });

    test('skips leading blank lines', () {
      expect(deriveNoteTitle('\n\n  \nActual title\nBody'), 'Actual title');
    });

    test('caps long lines at ~80 characters with an ellipsis', () {
      final longLine = 'a' * 120;
      final title = deriveNoteTitle(longLine)!;
      expect(title.length, 81); // 80 chars + ellipsis
      expect(title.endsWith('…'), isTrue);
    });

    test('does not truncate lines at or under 80 characters', () {
      final line = 'a' * 80;
      expect(deriveNoteTitle(line), line);
    });
  });
}

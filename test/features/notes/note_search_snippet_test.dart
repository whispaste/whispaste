/// Unit tests for [noteSearchSnippet] — the excerpt around the first search
/// match in the notes hit list (#872).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_search_snippet.dart';

void main() {
  group('noteSearchSnippet', () {
    test('returns null for a blank query or no match', () {
      expect(noteSearchSnippet('Some text', '   '), isNull);
      expect(noteSearchSnippet('Some text', 'absent'), isNull);
      expect(noteSearchSnippet('', 'x'), isNull);
    });

    test('splits a short note around the match, no cuts', () {
      final s = noteSearchSnippet('Buy milk and bread', 'milk')!;
      expect(s.before, 'Buy ');
      expect(s.match, 'milk');
      expect(s.after, ' and bread');
      expect(s.leadingCut, isFalse);
      expect(s.trailingCut, isFalse);
    });

    test('matches case-insensitively and keeps the original casing', () {
      final s = noteSearchSnippet('Call ANNA tomorrow', 'anna')!;
      expect(s.match, 'ANNA');
    });

    test('treats regex characters in the query literally', () {
      final s = noteSearchSnippet('Price (net) 5.00', '(net)')!;
      expect(s.match, '(net)');
      expect(noteSearchSnippet('abc', 'a.c'), isNull);
    });

    test('uses the first match', () {
      final s = noteSearchSnippet('one target two target', 'target')!;
      expect(s.before, 'one ');
      expect(s.after, ' two target');
    });

    test('cuts long text before the match at a word boundary', () {
      final content = '${'word ' * 30}needle end';
      final s = noteSearchSnippet(content, 'needle', contextBefore: 12)!;
      expect(s.leadingCut, isTrue);
      expect(s.before, 'word word ');
      expect(s.match, 'needle');
    });

    test('never opens the excerpt with a word fragment', () {
      final s = noteSearchSnippet(
        'alpha bravocharlie needle',
        'needle',
        contextBefore: 10,
      )!;
      expect(s.before, '');
      expect(s.leadingCut, isTrue);
    });

    test('cuts long text after the match', () {
      final content = 'needle ${'tail ' * 50}';
      final s = noteSearchSnippet(content, 'needle', contextAfter: 10)!;
      expect(s.leadingCut, isFalse);
      expect(s.trailingCut, isTrue);
      expect(s.after.length, lessThanOrEqualTo(10));
    });

    test('trailing whitespace alone is no cut', () {
      final s = noteSearchSnippet('needle   \n\n', 'needle', contextAfter: 2)!;
      expect(s.trailingCut, isFalse);
      expect(s.after, '');
    });

    test('collapses line breaks and whitespace runs to one space', () {
      final s = noteSearchSnippet('first\n\n  line\tneedle\nnext', 'needle')!;
      expect(s.before, 'first line ');
      expect(s.after, ' next');
    });

    test('searchFrom skips earlier matches and bounds the excerpt', () {
      const content = 'needle title\nbody with needle';
      final from = content.indexOf('\n');
      final s = noteSearchSnippet(content, 'needle', searchFrom: from)!;
      expect(s.before, 'body with ');
      expect(s.leadingCut, isFalse);
      expect(
        noteSearchSnippet('needle title', 'needle', searchFrom: 12),
        isNull,
      );
    });
  });
}

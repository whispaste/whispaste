/// The terms list works on the one stored `customVocabulary` string: reading
/// single entries, adding, renaming, removing and putting back, without
/// changing the separator style the user chose (#620).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/dictionary/role_terms.dart';

void main() {
  group('reading legacy strings', () {
    test('splits at commas and line breaks, trims, drops blanks', () {
      expect(vocabularyTerms('  GitHub ,, Kubernetes\n\n  npm\n, '), [
        'GitHub',
        'Kubernetes',
        'npm',
      ]);
    });

    test('a trailing comma and an empty text give no phantom entry', () {
      expect(vocabularyTerms('a, b,'), ['a', 'b']);
      expect(vocabularyTerms(''), isEmpty);
      expect(vocabularyTerms(' \n , '), isEmpty);
    });

    test('duplicates in old text stay visible as entries', () {
      expect(vocabularyTerms('npm, NPM'), ['npm', 'NPM']);
    });
  });

  group('encodeVocabulary', () {
    test('uses lines when the old text had a line break, else commas', () {
      expect(encodeVocabulary(['a', 'b'], style: 'x\ny'), 'a\nb');
      expect(encodeVocabulary(['a', 'b'], style: 'x, y'), 'a, b');
      expect(encodeVocabulary(['a', 'b'], style: ''), 'a, b');
    });
  });

  group('addVocabularyTerm', () {
    test('appends and keeps the stored text as it was', () {
      expect(addVocabularyTerm('a,b', 'c').vocabulary, 'a,b, c');
      expect(addVocabularyTerm('a\nb', ' c ').vocabulary, 'a\nb\nc');
      expect(addVocabularyTerm('', 'c').vocabulary, 'c');
    });

    test('refuses a duplicate in any letter case and names the entry', () {
      final r = addVocabularyTerm('GitHub, npm', 'github');
      expect(r.vocabulary, 'GitHub, npm');
      expect(r.duplicateOf, 0);
      expect(addVocabularyTerm('a\nb', 'B').duplicateOf, 1);
    });

    test('an empty term changes nothing', () {
      final r = addVocabularyTerm('a, b', '  ');
      expect(r.vocabulary, 'a, b');
      expect(r.duplicateOf, isNull);
    });
  });

  group('addVocabularyTerms', () {
    test('splits typed text at commas and line breaks', () {
      final r = addVocabularyTerms('a', 'Dr. Müller, PhD\n npm');
      expect(r.vocabulary, 'a, Dr. Müller, PhD, npm');
      expect(r.added, ['Dr. Müller', 'PhD', 'npm']);
      expect(r.duplicates, isEmpty);
    });

    test('skips duplicates, also within the input', () {
      final r = addVocabularyTerms('a, b', 'B, c, C');
      expect(r.vocabulary, 'a, b, c');
      expect(r.added, ['c']);
      expect(r.duplicates, ['B', 'C']);
    });

    test('a comma or line break means several entries', () {
      expect(vocabularyTextHoldsSeveral('Dr. Müller, PhD'), isTrue);
      expect(vocabularyTextHoldsSeveral('a\nb'), isTrue);
      expect(vocabularyTextHoldsSeveral('Dr. Müller'), isFalse);
      expect(vocabularyTextHoldsSeveral('PhD,'), isFalse);
    });
  });

  group('renameVocabularyTerm', () {
    test('changes one entry and keeps the style', () {
      expect(renameVocabularyTerm('a, b, c', 1, 'x').vocabulary, 'a, x, c');
      expect(renameVocabularyTerm('a\nb\nc', 2, 'x').vocabulary, 'a\nb\nx');
    });

    test('a change of letter case alone is allowed', () {
      final r = renameVocabularyTerm('github, npm', 0, 'GitHub');
      expect(r.vocabulary, 'GitHub, npm');
      expect(r.duplicateOf, isNull);
    });

    test('refuses a spelling another entry has', () {
      final r = renameVocabularyTerm('a, b, c', 0, 'C');
      expect(r.vocabulary, 'a, b, c');
      expect(r.duplicateOf, 2);
    });

    test('the same spelling or a bad input leaves the text untouched', () {
      expect(renameVocabularyTerm('a,b', 0, 'a').vocabulary, 'a,b');
      expect(renameVocabularyTerm('a,b', 0, ' ').vocabulary, 'a,b');
      expect(renameVocabularyTerm('a,b', 5, 'x').vocabulary, 'a,b');
      expect(renameVocabularyTerm('a,b', -1, 'x').vocabulary, 'a,b');
    });
  });

  group('removeVocabularyTerm and insertVocabularyTerm', () {
    test('remove drops one entry and keeps the style', () {
      expect(removeVocabularyTerm('a, b, c', 1), 'a, c');
      expect(removeVocabularyTerm('a\nb\nc', 0), 'b\nc');
      expect(removeVocabularyTerm('a', 0), '');
      expect(removeVocabularyTerm('a, b', 9), 'a, b');
    });

    test('insert puts a removed term back at its place', () {
      final removed = removeVocabularyTerm('a, b, c', 1);
      expect(insertVocabularyTerm(removed, 1, 'b'), 'a, b, c');
      expect(insertVocabularyTerm('a\nc', 1, 'b'), 'a\nb\nc');
      expect(insertVocabularyTerm('a', 9, 'b'), 'a, b');
      expect(insertVocabularyTerm('', 0, 'b'), 'b');
    });

    test('insert does not create a duplicate or an empty entry', () {
      expect(insertVocabularyTerm('a, b', 0, 'B'), 'a, b');
      expect(insertVocabularyTerm('a, b', 0, ' '), 'a, b');
    });
  });

  group('moveVocabularyTermUp', () {
    test('swaps with the entry above and keeps the style', () {
      expect(moveVocabularyTermUp('a, b, c', 2), 'a, c, b');
      expect(moveVocabularyTermUp('a\nb\nc', 1), 'b\na\nc');
    });

    test('the first entry and a wrong index change nothing', () {
      expect(moveVocabularyTermUp('a, b', 0), 'a, b');
      expect(moveVocabularyTermUp('a, b', 5), 'a, b');
      expect(moveVocabularyTermUp('a, b', -1), 'a, b');
    });
  });
}

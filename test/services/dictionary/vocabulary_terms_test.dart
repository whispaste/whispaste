/// How the stored term list is written for the recognition (#145).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/vocabulary_terms.dart';

void main() {
  group('vocabularyPrompt', () {
    test('drops empty entries and stray spaces of a comma list', () {
      expect(vocabularyPrompt(' GitHub,, npm ,JSON, '), 'GitHub, npm, JSON');
    });

    test('keeps one term per line when the list was written that way', () {
      expect(vocabularyPrompt('GitHub\n\n npm \r\nJSON,'), 'GitHub\nnpm\nJSON');
    });

    test('an empty or blank vocabulary sends nothing', () {
      expect(vocabularyPrompt(''), '');
      expect(vocabularyPrompt(' ,\n , '), '');
    });
  });
}

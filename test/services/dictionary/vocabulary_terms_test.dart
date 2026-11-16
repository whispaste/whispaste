/// The dictionary list and the recognition count the same text against the
/// prompt budget, and a term moved up survives the cut first (#145).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/features/dictionary/role_terms.dart'
    show moveVocabularyTermUp;
import 'package:whispaste/services/dictionary/term_budget.dart';
import 'package:whispaste/services/dictionary/vocabulary_terms.dart';

/// One token per started 4 characters.
int _tokens(String text) => (text.length / 4).ceil();

Future<int?> _cut(String stored, {List<String>? counted}) => firstLeftOutTerm(
  vocabularyTerms(stored),
  provider: SttProviderType.onDevice,
  engine: OnDeviceEngine.whisper,
  style: stored,
  countTokens: (text) async {
    counted?.add(text);
    return _tokens(text);
  },
);

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

  group('list and recognition count alike', () {
    test('the full text the list counts is the text the engine gets', () async {
      // Messy stored text, long enough to need the exact count.
      final stored = [for (var i = 0; i < 40; i++) ' term$i ,'].join(' ,');
      final counted = <String>[];
      await _cut(stored, counted: counted);
      expect(counted.first, vocabularyPrompt(stored));
    });

    test(
      'a cut found by the list is where the sent prompt overflows',
      () async {
        final stored = [for (var i = 0; i < 40; i++) 'term$i'].join(',  ');
        final cut = (await _cut(stored))!;
        final sent = vocabularyTerms(vocabularyPrompt(stored));
        String prefix(int n) => encodeVocabulary(sent.take(n), style: stored);
        expect(_tokens(prefix(cut)), lessThanOrEqualTo(63));
        expect(_tokens(prefix(cut + 1)), greaterThan(63));
      },
    );
  });

  group('priority', () {
    test('a term moved up past the cut reaches the recognition', () async {
      var stored = [for (var i = 0; i < 40; i++) 'term$i'].join(', ');
      final cut = (await _cut(stored))!;
      expect(cut, lessThan(39));
      // The last term, past the cut, moved up step by step to the top.
      for (var i = 39; i > 0; i--) {
        stored = moveVocabularyTermUp(stored, i);
      }
      final terms = vocabularyTerms(stored);
      final newCut = (await _cut(stored))!;
      expect(terms.first, 'term39');
      expect(newCut, greaterThan(0));
    });

    test('the first term is kept when the list is over the budget', () async {
      final stored = [
        'Kubernetes',
        for (var i = 0; i < 60; i++) 'x$i',
      ].join(', ');
      expect(await _cut(stored), greaterThan(0));
    });
  });
}

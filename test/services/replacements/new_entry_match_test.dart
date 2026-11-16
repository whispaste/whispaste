import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/symbol_template_pack.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  group('newEntryMatch', () {
    test('a trigger of four or more characters starts similar and strict', () {
      final match = newEntryMatch(['kubernetes']);
      expect(match.mode, TextReplacementMatchMode.fuzzy);
      expect(match.fuzzyThreshold, fuzzyThresholdStrict);
    });

    test('a trigger below the minimum length stays exact', () {
      final match = newEntryMatch(['omw']);
      expect(match.mode, TextReplacementMatchMode.exact);
      expect(match.fuzzyThreshold, isNull);
    });

    test('a punctuation trigger stays exact', () {
      expect(newEntryMatch(['....']).mode, TextReplacementMatchMode.exact);
      expect(newEntryMatch(['-->']).mode, TextReplacementMatchMode.exact);
    });

    test('one short trigger keeps the whole entry exact', () {
      // A similar rule skips short triggers, so "omw" would stop firing.
      expect(
        newEntryMatch(['omw', 'on my way']).mode,
        TextReplacementMatchMode.exact,
      );
    });

    test('blank triggers do not count', () {
      expect(
        newEntryMatch(['whispaste', '  ']).mode,
        TextReplacementMatchMode.fuzzy,
      );
      expect(newEntryMatch(['', ' ']).mode, TextReplacementMatchMode.exact);
    });

    test(
      'the symbol templates start similar, all their triggers are words',
      () {
        for (final template in symbolTemplatePack) {
          expect(
            newEntryMatch(template.triggers).mode,
            TextReplacementMatchMode.fuzzy,
            reason: template.triggers.join('|'),
          );
        }
      },
    );
  });
}

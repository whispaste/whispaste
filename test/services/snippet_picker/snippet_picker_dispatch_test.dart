import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_dispatch.dart';

void main() {
  group('snippetPickerTriggerMatches', () {
    test('matches when the whole transcript equals the trigger exactly '
        'after normalization', () {
      expect(snippetPickerTriggerMatches('snippets', '  Snippets.  '), isTrue);
    });

    test('does not match when the trigger is only a substring of the '
        'transcript', () {
      expect(
        snippetPickerTriggerMatches('snippets', 'open snippets please'),
        isFalse,
      );
    });

    test('returns false when nothing matches', () {
      expect(
        snippetPickerTriggerMatches('snippets', 'unrelated text'),
        isFalse,
      );
    });

    test('an empty trigger (feature disabled) never matches', () {
      expect(snippetPickerTriggerMatches('', 'snippets'), isFalse);
    });

    test('a whitespace-only trigger never matches', () {
      expect(snippetPickerTriggerMatches('   ', 'snippets'), isFalse);
    });

    test('a whitespace-only transcript never matches even against a '
        'valid trigger', () {
      expect(snippetPickerTriggerMatches('snippets', '   '), isFalse);
    });

    test('is case-insensitive and punctuation-tolerant like Automations', () {
      expect(snippetPickerTriggerMatches('Snippets', 'snippets!'), isTrue);
    });
  });
}

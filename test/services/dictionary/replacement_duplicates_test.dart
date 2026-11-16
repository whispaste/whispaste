import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/replacement_duplicates.dart';

void main() {
  group('normalizeTriggerKey', () {
    test('ignores case and punctuation between words', () {
      expect(
        normalizeTriggerKey('Mit-freundlichen  Grüßen'),
        'mit freundlichen grüßen',
      );
      expect(
        normalizeTriggerKey('mit freundlichen grüßen'),
        'mit freundlichen grüßen',
      );
    });

    test('a phrase without letters or digits normalises to nothing', () {
      expect(normalizeTriggerKey(' ... - '), '');
    });
  });

  group('duplicateReplacementIds', () {
    test('flags every entry that shares a normalised trigger', () {
      final ids = duplicateReplacementIds(const [
        TriggerOwner(id: 'a', triggers: ['mfg']),
        TriggerOwner(id: 'b', triggers: ['MFG', 'other']),
        TriggerOwner(id: 'c', triggers: ['lg']),
      ]);
      expect(ids, {'a', 'b'});
    });

    test('a collision inside a single entry is not a duplicate', () {
      final ids = duplicateReplacementIds(const [
        TriggerOwner(id: 'a', triggers: ['mfg', 'MFG']),
      ]);
      expect(ids, isEmpty);
    });

    test('an entry is reported once however many collisions it has', () {
      final ids = duplicateReplacementIds(const [
        TriggerOwner(id: 'a', triggers: ['x y', 'z']),
        TriggerOwner(id: 'b', triggers: ['x-y']),
        TriggerOwner(id: 'c', triggers: ['z']),
      ]);
      expect(ids, {'a', 'b', 'c'});
    });

    test('no entries means no duplicates', () {
      expect(duplicateReplacementIds(const []), isEmpty);
    });
  });
}

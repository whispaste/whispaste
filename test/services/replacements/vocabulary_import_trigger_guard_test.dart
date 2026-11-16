/// Guard for the vocabulary import: every identifier it can offer is a valid
/// trigger that fires, so the "never fires" hint of the CSV preview and the
/// replacement editor is never needed on this path.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';
import 'package:whispaste/services/replacements/vocabulary_import_scanner.dart';
import 'package:whispaste/services/replacements/vocabulary_import_service.dart';

void main() {
  test('every extracted identifier fires as an exact trigger', () {
    final found = extractIdentifiers({
      'a.dart':
          'class RecordingOrchestrator {\n'
          '  void start() { computeImportDiff(x); }\n'
          '}\n'
          'const int ok = 1;',
      'b.py': 'def get_user_by_id(id):\n    pass',
    });
    expect(found, isNotEmpty);

    for (final identifier in found) {
      expect(
        exactTriggerNeverFires(identifier),
        isFalse,
        reason: '$identifier would never fire',
      );
    }
  });

  test('identifiers below the import minimum are never offered', () {
    expect(vocabularyImportMinIdentifierLength, greaterThan(1));
  });
}

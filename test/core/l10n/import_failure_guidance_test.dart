import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Import failures name the cause and the next step. Each of these messages
/// has a cause sentence and an action sentence in every shipped language.
const _guidedKeys = [
  'historyImportFailureCopy',
  'historyImportFailureDecode',
  'historyImportFailureTranscription',
  'historyImportFailureSave',
];

void main() {
  test(
    'import failure messages give a cause and a next step, in all six languages',
    () {
      for (final lang in ['de', 'en', 'es', 'he', 'pt', 'ru']) {
        final arb =
            jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
                as Map<String, dynamic>;
        for (final key in _guidedKeys) {
          final text = (arb[key] as String?)?.trim() ?? '';
          final sentences = RegExp(r'[.!?](\s|$)').allMatches(text).length;
          expect(
            sentences,
            greaterThanOrEqualTo(2),
            reason: '$lang $key: $text',
          );
        }
      }
    },
  );
}

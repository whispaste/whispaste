import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The copy-interrupted message (slow or changed source) exists and is not
/// empty in every shipped language.
void main() {
  test(
    'historyImportFailureCopyInterrupted is set in every shipped language',
    () {
      for (final lang in [
        'de',
        'en',
        'es',
        'he',
        'pt',
        'ru',
        'fr',
        'it',
        'zh',
      ]) {
        final arb =
            jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
                as Map<String, dynamic>;
        final text = arb['historyImportFailureCopyInterrupted'];
        expect(text, isA<String>(), reason: lang);
        expect((text as String).trim(), isNotEmpty, reason: lang);
        // Chinese ends a sentence with the full-width stop.
        expect(text.trimRight(), matches(RegExp(r'[.。]$')), reason: lang);
      }
    },
  );
}

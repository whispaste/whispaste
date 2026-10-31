/// The save-later notice (BIZ-38) must not promise an endless retry.
/// Checks the wording in every ARB file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = ['de', 'en', 'es', 'pt', 'ru', 'he'];

void main() {
  test('no ARB promises an endless retry or quotes the text', () {
    for (final locale in _locales) {
      final text =
          (jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
                  as Map<String, dynamic>)['pendingAudioSaveLater']
              as String;
      expect(text, isNot(contains('immer')), reason: locale);
      expect(text, isNot(contains('always')), reason: locale);
      expect(text, isNot(contains('"')), reason: locale);
    }
  });
}

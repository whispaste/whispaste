/// R-08 acceptance: every dictionary-package string exists, is not empty, and
/// is present in all six app languages. The codec and the planner stay free of
/// I/O, network and plugin imports.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _languages = ['de', 'en', 'es', 'he', 'pt', 'ru'];

Map<String, dynamic> _arb(String language) =>
    jsonDecode(File('lib/core/l10n/app_$language.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('every dictionaryCsv string is non-empty in all six languages', () {
    final keys = [
      for (final key in _arb('de').keys)
        if (key.startsWith('dictionaryCsv')) key,
    ];
    expect(keys, isNotEmpty);

    for (final language in _languages) {
      final arb = _arb(language);
      for (final key in keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$key missing in $language');
        expect(
          (value as String).trim(),
          isNotEmpty,
          reason: '$key empty in $language',
        );
      }
    }
  });

  test('codec and planner import no I/O, network or plugin code', () {
    const files = [
      'lib/services/dictionary/replacement_csv.dart',
      'lib/services/dictionary/replacement_import_plan.dart',
    ];
    const forbidden = [
      'dart:io',
      'package:http',
      'package:dio',
      'package:file_selector',
      'package:drift',
      'telemetry',
      'package:flutter/',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final name in forbidden) {
        expect(source.contains(name), isFalse, reason: '$path mentions $name');
      }
    }
  });
}

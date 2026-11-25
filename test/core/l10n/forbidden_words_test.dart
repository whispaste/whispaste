import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WhisPaste never calls its support options "donations" (internal-notes §7).
/// Support is "Unterstützung" / "Sponsoring" in every language. This guard
/// scans every string value in every ARB file, including @-metadata, for the
/// translated equivalents of "Spende".
final _forbidden = <String, RegExp>{
  'Spende (de)': RegExp('spende', caseSensitive: false),
  'donation (en)': RegExp('donat', caseSensitive: false),
  'donación (es)': RegExp('donaci', caseSensitive: false),
  'donar (es)': RegExp(r'\bdonar\b', caseSensitive: false),
  'doação (pt)': RegExp('doaç', caseSensitive: false),
  'doar (pt)': RegExp(r'\bdoar\b', caseSensitive: false),
  'пожертвование (ru)': RegExp('пожертв', caseSensitive: false),
  'תרומה (he)': RegExp('תרומ'),
  'תורם (he)': RegExp('תורם'),
  // Whole words only, so "donne", "données" and "dont" stay allowed.
  'don (fr)': RegExp(r"(?<!\p{L})dons?(?![\p{L}'’])", unicode: true),
  'donazione (it)': RegExp('donazion', caseSensitive: false),
  'donare (it)': RegExp(r'\bdonar[ei]\b', caseSensitive: false),
  '捐 (zh)': RegExp('捐'),
};

void _collectStrings(Object? node, void Function(String) onString) {
  if (node is String) {
    onString(node);
  } else if (node is Map) {
    for (final value in node.values) {
      _collectStrings(value, onString);
    }
  } else if (node is List) {
    for (final value in node) {
      _collectStrings(value, onString);
    }
  }
}

void main() {
  test('no translated "donation" term appears in any ARB file', () {
    final arbFiles = Directory('lib/core/l10n')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.arb'))
        .toList();
    expect(arbFiles, isNotEmpty);

    final violations = <String>[];
    for (final file in arbFiles) {
      final decoded = jsonDecode(file.readAsStringSync());
      _collectStrings(decoded, (value) {
        for (final entry in _forbidden.entries) {
          if (entry.value.hasMatch(value)) {
            violations.add('${file.path}: ${entry.key} in "$value"');
          }
        }
      });
    }

    expect(
      violations,
      isEmpty,
      reason: 'Forbidden donation terms found:\n${violations.join('\n')}',
    );
  });
}

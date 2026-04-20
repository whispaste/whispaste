import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Detects AI-generated German text that uses ASCII digraphs instead of real
/// umlauts (e.g. "fuer" instead of "für"). These patterns are never valid in
/// modern German and indicate an encoding or model output problem.
///
/// We intentionally use a curated blocklist rather than a blanket ae/oe/ue
/// scan because many legitimate German words contain those sequences
/// (e.g. "Israel", "Poet", "Duell", "Aero").
final _brokenUmlautPatterns = [
  // ü replacements
  RegExp(r'\bfuer\b', caseSensitive: false),
  RegExp(r'\bueber\b', caseSensitive: false),
  RegExp(r'\bzurueck\b', caseSensitive: false),
  RegExp(r'\bkuerzel\b', caseSensitive: false),
  RegExp(r'\bwuerden?\b', caseSensitive: false),
  RegExp(r'\bmuessen\b', caseSensitive: false),
  RegExp(r'\bkoennen\b', caseSensitive: false),
  RegExp(r'\bfuenf\b', caseSensitive: false),
  RegExp(r'\bfuegen?\b', caseSensitive: false),
  RegExp(r'\bgruess', caseSensitive: false),
  RegExp(r'\bpruef', caseSensitive: false),
  RegExp(r'\bwuensch', caseSensitive: false),
  RegExp(r'\bbuero\b', caseSensitive: false),
  // ö replacements
  RegExp(r'\boeffn', caseSensitive: false),
  RegExp(r'\bkoennt', caseSensitive: false),
  RegExp(r'\bmoecht', caseSensitive: false),
  RegExp(r'\bhoer', caseSensitive: false),
  RegExp(r'\bgehoer', caseSensitive: false),
  // ä replacements
  RegExp(r'\btaeglich\b', caseSensitive: false),
  RegExp(r'\bwaehle?\b', caseSensitive: false),
  RegExp(r'\bhaette\b', caseSensitive: false),
  RegExp(r'\bhaehnchen\b', caseSensitive: false),
  RegExp(r'\bmaessig\b', caseSensitive: false),
  RegExp(r'\bstandaerdm', caseSensitive: false),
  RegExp(r'\baerger', caseSensitive: false),
  RegExp(r'\baendern?\b', caseSensitive: false),
  // ß replacements
  RegExp(r'\bstrasse\b', caseSensitive: false),
  RegExp(r'\bgroesse\b', caseSensitive: false),
  RegExp(r'\bschliessen\b', caseSensitive: false),
  RegExp(r'\bheiss\b', caseSensitive: false),
];

/// Detects mojibake — UTF-8 bytes misinterpreted as Latin-1/Windows-1252.
/// These sequences are never valid in any language and indicate encoding
/// corruption at the file or pipeline level.
final _mojibakePatterns = [
  RegExp(r'Ã¤'), // ä
  RegExp(r'Ã¶'), // ö
  RegExp(r'Ã¼'), // ü
  RegExp(r'ÃŸ'), // ß
  RegExp(r'Ã„'), // Ä
  RegExp(r'Ã–'), // Ö
  RegExp(r'Ãœ'), // Ü
  RegExp(r'â€"'), // —
  RegExp(r'â€œ'), // "
  RegExp(r'â€\u009d'), // "
  RegExp(r'â€™'), // '
  RegExp(r'ï»¿'), // BOM as mojibake
  RegExp(r'�'), // Unicode replacement character
];

/// Characters that MUST appear in substantial German text.
final _germanChars = RegExp('[üöäßÜÖÄ]');

void main() {
  group('German encoding integrity', () {
    late Map<String, dynamic> arbDe;

    setUpAll(() {
      final arbFile = File('lib/core/l10n/app_de.arb');
      expect(arbFile.existsSync(), isTrue,
          reason: 'German ARB file must exist');
      arbDe = jsonDecode(arbFile.readAsStringSync()) as Map<String, dynamic>;
    });

    test('ARB DE file has actual German text (sanity check)', () {
      // Just verify the file is genuine German, not all-ASCII
      final allText = arbDe.values.whereType<String>().join(' ');
      expect(allText.length, greaterThan(100),
          reason: 'German ARB file should have substantial text');
      // At least some values must contain German special characters
      final valuesWithUmlauts = arbDe.values
          .whereType<String>()
          .where((v) => _germanChars.hasMatch(v))
          .length;
      expect(valuesWithUmlauts, greaterThan(5),
          reason:
              'German ARB should have multiple values with umlauts, found $valuesWithUmlauts');
    });

    test('ARB values have no broken ASCII-digraph umlauts', () {
      final violations = <String>[];

      for (final entry in arbDe.entries) {
        if (entry.key.startsWith('@')) continue;
        final value = entry.value;
        if (value is! String) continue;

        for (final pattern in _brokenUmlautPatterns) {
          if (pattern.hasMatch(value)) {
            violations.add(
              '  "${entry.key}": found "${pattern.pattern}" in "$value"',
            );
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'German ARB contains ASCII-digraph umlauts:\n${violations.join('\n')}');
    });

    test('ARB values have no mojibake encoding corruption', () {
      final violations = <String>[];

      for (final entry in arbDe.entries) {
        if (entry.key.startsWith('@')) continue;
        final value = entry.value;
        if (value is! String) continue;

        for (final pattern in _mojibakePatterns) {
          if (pattern.hasMatch(value)) {
            violations.add(
              '  "${entry.key}": found mojibake "${pattern.pattern}" in "$value"',
            );
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'German ARB contains mojibake:\n${violations.join('\n')}');
    });

    test('screenshot demo data has no broken umlauts', () {
      final testFile = File('test/screenshots/store_screenshots_test.dart');
      if (!testFile.existsSync()) return;

      final content = testFile.readAsStringSync();
      final violations = <String>[];

      for (final pattern in _brokenUmlautPatterns) {
        final matches = pattern.allMatches(content);
        for (final m in matches) {
          final lineNum = content.substring(0, m.start).split('\n').length;
          violations.add(
            '  line $lineNum: "${m.group(0)}" (pattern: ${pattern.pattern})',
          );
        }
      }

      expect(violations, isEmpty,
          reason:
              'Screenshot test has broken umlauts:\n${violations.join('\n')}');
    });

    test('OG image config has no broken umlauts', () {
      final ogFile = File('tools/og-image/generate.cjs');
      if (!ogFile.existsSync()) return;

      final content = ogFile.readAsStringSync();
      final violations = <String>[];

      for (final pattern in _brokenUmlautPatterns) {
        final matches = pattern.allMatches(content);
        for (final m in matches) {
          final lineNum = content.substring(0, m.start).split('\n').length;
          violations.add(
            '  line $lineNum: "${m.group(0)}" (pattern: ${pattern.pattern})',
          );
        }
      }

      expect(violations, isEmpty,
          reason: 'OG config has broken umlauts:\n${violations.join('\n')}');
    });

    test('store screenshot config has no broken umlauts', () {
      final configFile = File('tools/appstore-screens/config.js');
      if (!configFile.existsSync()) return;

      final content = configFile.readAsStringSync();
      final violations = <String>[];

      for (final pattern in _brokenUmlautPatterns) {
        final matches = pattern.allMatches(content);
        for (final m in matches) {
          final lineNum = content.substring(0, m.start).split('\n').length;
          violations.add(
            '  line $lineNum: "${m.group(0)}" (pattern: ${pattern.pattern})',
          );
        }
      }

      expect(violations, isEmpty,
          reason:
              'Store config has broken umlauts:\n${violations.join('\n')}');
    });
  });
}

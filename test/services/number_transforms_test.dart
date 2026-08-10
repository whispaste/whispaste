/// Unit tests for [toNumericOnly] — German number engine (Slice 1).
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/number_transforms.dart';

void main() {
  group('toNumericOnly — DE §8.1 (30 Fälle)', () {
    // #1: `null` ist das deutsche Zahlwort für 0, kein Dart-null.
    test('null → 0', () {
      expect(toNumericOnly('null'), '0');
    });

    test('eins → 1', () {
      expect(toNumericOnly('eins'), '1');
    });

    test('sieben → 7', () {
      expect(toNumericOnly('sieben'), '7');
    });

    test('zehn → 10', () {
      expect(toNumericOnly('zehn'), '10');
    });

    test('elf → 11', () {
      expect(toNumericOnly('elf'), '11');
    });

    test('zwölf → 12', () {
      expect(toNumericOnly('zwölf'), '12');
    });

    test('dreizehn → 13', () {
      expect(toNumericOnly('dreizehn'), '13');
    });

    test('sechzehn → 16', () {
      expect(toNumericOnly('sechzehn'), '16');
    });

    test('siebzehn → 17', () {
      expect(toNumericOnly('siebzehn'), '17');
    });

    test('neunzehn → 19', () {
      expect(toNumericOnly('neunzehn'), '19');
    });

    test('zwanzig → 20', () {
      expect(toNumericOnly('zwanzig'), '20');
    });

    test('einundzwanzig → 21', () {
      expect(toNumericOnly('einundzwanzig'), '21');
    });

    test('zweiundvierzig → 42', () {
      expect(toNumericOnly('zweiundvierzig'), '42');
    });

    test('sechsundsechzig → 66', () {
      expect(toNumericOnly('sechsundsechzig'), '66');
    });

    test('siebenundsiebzig → 77', () {
      expect(toNumericOnly('siebenundsiebzig'), '77');
    });

    test('neunundneunzig → 99', () {
      expect(toNumericOnly('neunundneunzig'), '99');
    });

    test('dreißig → 30', () {
      expect(toNumericOnly('dreißig'), '30');
    });

    test('dreissig → 30', () {
      expect(toNumericOnly('dreissig'), '30');
    });

    test('hundert → 100', () {
      expect(toNumericOnly('hundert'), '100');
    });

    test('einhundert → 100', () {
      expect(toNumericOnly('einhundert'), '100');
    });

    test('hundertfünfundzwanzig → 125', () {
      expect(toNumericOnly('hundertfünfundzwanzig'), '125');
    });

    test('hundertundzwanzig → 120', () {
      expect(toNumericOnly('hundertundzwanzig'), '120');
    });

    test('zweihundertdrei → 203', () {
      expect(toNumericOnly('zweihundertdrei'), '203');
    });

    test('tausend → 1000', () {
      expect(toNumericOnly('tausend'), '1000');
    });

    test('eintausend → 1000', () {
      expect(toNumericOnly('eintausend'), '1000');
    });

    test('zweitausendfünfhundertdreiundzwanzig → 2523', () {
      expect(toNumericOnly('zweitausendfünfhundertdreiundzwanzig'), '2523');
    });

    test('ein und zwanzig (getrennt) → 21', () {
      expect(toNumericOnly('ein und zwanzig'), '21');
    });

    test('fünf komma zwei → 5,2', () {
      expect(toNumericOnly('fünf komma zwei'), '5,2');
    });

    test('fünf punkt zwei → 5.2', () {
      expect(toNumericOnly('fünf punkt zwei'), '5.2');
    });

    test('zwölf komma fünfundzwanzig → 12,25', () {
      expect(toNumericOnly('zwölf komma fünfundzwanzig'), '12,25');
    });
  });

  group('toNumericOnly — §8.3 (DE-Auswahl)', () {
    test('Fall 1: minus drei → -3', () {
      expect(toNumericOnly('minus drei'), '-3');
    });

    test('Fall 3: fünf komma zwei minus drei → 5,2-3 (Nutzer-Mail)', () {
      expect(toNumericOnly('fünf komma zwei minus drei'), '5,2-3');
    });

    test('Fall 4: Fünf Komma zwei minus drei. → 5,2-3 (Großschreibung + Schlusspunkt)',
        () {
      expect(toNumericOnly('Fünf Komma zwei minus drei.'), '5,2-3');
    });

    test('Fall 5: Fünf Komma zwei, minus drei. → 5,2-3 (Satz-Komma verworfen)',
        () {
      expect(toNumericOnly('Fünf Komma zwei, minus drei.'), '5,2-3');
    });

    test('Fall 7: 5,2 minus 3 → 5,2-3 (Ziffern + Wort-Vorzeichen)', () {
      expect(toNumericOnly('5,2 minus 3'), '5,2-3');
    });

    test('Fall 8: 5,2-3 → 5,2-3 (Idempotenz, perfekte Eingabe)', () {
      expect(toNumericOnly('5,2-3'), '5,2-3');
    });

    test('Fall 10: fünf komma zwei Millimeter → null (Alles-oder-Nichts)', () {
      expect(toNumericOnly('fünf komma zwei Millimeter'), isNull);
    });

    test('Fall 12: fünf plus zwei → null (+ nicht im Alphabet)', () {
      expect(toNumericOnly('fünf plus zwei'), isNull);
    });

    test('Fall 13: Hallo Welt → null (Prosa bleibt unangetastet)', () {
      expect(toNumericOnly('Hallo Welt'), isNull);
    });

    test('Fall 14: leer → null', () {
      expect(toNumericOnly(''), isNull);
    });

    test('Fall 15: . → null (nur Satzzeichen ⇒ leeres Ergebnis)', () {
      expect(toNumericOnly('.'), isNull);
    });
  });

  group('toNumericOnly — §8.3 Fall 9: Idempotenz-Property', () {
    // Alle 30 Fälle aus §8.1 als Liste für die Idempotenz-Prüfung.
    final idempotentCases = <String, String>{
      'null': '0',
      'eins': '1',
      'sieben': '7',
      'zehn': '10',
      'elf': '11',
      'zwölf': '12',
      'dreizehn': '13',
      'sechzehn': '16',
      'siebzehn': '17',
      'neunzehn': '19',
      'zwanzig': '20',
      'einundzwanzig': '21',
      'zweiundvierzig': '42',
      'sechsundsechzig': '66',
      'siebenundsiebzig': '77',
      'neunundneunzig': '99',
      'dreißig': '30',
      'dreissig': '30',
      'hundert': '100',
      'einhundert': '100',
      'hundertfünfundzwanzig': '125',
      'hundertundzwanzig': '120',
      'zweihundertdrei': '203',
      'tausend': '1000',
      'eintausend': '1000',
      'zweitausendfünfhundertdreiundzwanzig': '2523',
      'ein und zwanzig': '21',
      'fünf komma zwei': '5,2',
      'fünf punkt zwei': '5.2',
      'zwölf komma fünfundzwanzig': '12,25',
    };

    test('toNumericOnly(toNumericOnly(x)) == toNumericOnly(x) für alle DE-Fälle',
        () {
      for (final entry in idempotentCases.entries) {
        final once = toNumericOnly(entry.key);
        expect(once, isNotNull, reason: 'Erster Durchlauf sollte nicht null sein für: ${entry.key}');
        final twice = toNumericOnly(once!);
        expect(twice, once, reason: 'Idempotenz fehlschlägt für: ${entry.key}');
      }
    });
  });

  group('toNumericOnly — §8.3 Fall 16/17: Alphabet-Property', () {
    test('Alle nicht-null Ausgaben passen auf ^[0-9.,-]+', () {
      final testCases = [
        'null',
        'eins',
        'sieben',
        'zehn',
        'elf',
        'zwölf',
        'dreizehn',
        'sechzehn',
        'siebzehn',
        'neunzehn',
        'zwanzig',
        'einundzwanzig',
        'zweiundvierzig',
        'sechsundsechzig',
        'siebenundsiebzig',
        'neunundneunzig',
        'dreißig',
        'dreissig',
        'hundert',
        'einhundert',
        'hundertfünfundzwanzig',
        'hundertundzwanzig',
        'zweihundertdrei',
        'tausend',
        'eintausend',
        'zweitausendfünfhundertdreiundzwanzig',
        'ein und zwanzig',
        'fünf komma zwei',
        'fünf punkt zwei',
        'zwölf komma fünfundzwanzig',
        'minus drei',
        'fünf komma zwei minus drei',
        'Fünf Komma zwei minus drei.',
        'Fünf Komma zwei, minus drei.',
        '5,2 minus 3',
        '5,2-3',
      ];

      final alphabetRegex = RegExp(r'^[0-9.,-]+$');
      for (final input in testCases) {
        final result = toNumericOnly(input);
        if (result != null) {
          expect(
            alphabetRegex.hasMatch(result),
            true,
            reason: 'Ausgabe "$result" für Eingabe "$input" passt nicht auf das Zielalphabet',
          );
        }
      }
    });

    test('Keine Ausgabe enthält ein Leerzeichen (≥1000 zufällige Token-Folgen)',
        () {
      final random = Random(42); // Fester Seed für Determinismus.
      final alphabetRegex = RegExp(r'^[0-9.,-]+$');

      // Generiere zufällige Token-Folgen aus dem deutschen Lexikon.
      final numberWords = [
        'eins', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', 'acht',
        'neun', 'zehn', 'elf', 'zwölf', 'zwanzig', 'dreißig', 'hundert',
        'tausend', 'komma', 'punkt', 'minus',
      ];

      var hasNonNullOutput = false;
      for (var i = 0; i < 1000; i++) {
        final length = random.nextInt(10) + 1; // 1–10 Token.
        final tokens = List.generate(length, (_) => numberWords[random.nextInt(numberWords.length)]);
        final input = tokens.join(' ');
        final result = toNumericOnly(input);
        if (result != null) {
          hasNonNullOutput = true;
          expect(
            !result.contains(' '),
            true,
            reason: 'Ausgabe "$result" enthält ein Leerzeichen',
          );
          expect(
            alphabetRegex.hasMatch(result),
            true,
            reason: 'Ausgabe "$result" passt nicht auf das Zielalphabet',
          );
        }
      }
      expect(hasNonNullOutput, true, reason: 'Mindestens eine nicht-null Ausgabe erwartet.');
    });
  });

  group('toNumericOnly — §7.2/§6.4 E1: Import-Reinheit', () {
    test('Engine-Datei enthält keine package:-Imports', () {
      final file = File('lib/services/number_transforms.dart');
      expect(file.existsSync(), isTrue, reason: 'Engine-Datei muss existieren.');
      final lines = file.readAsLinesSync();
      final packageImports = lines.where((line) => line.startsWith("import 'package:")).toList();
      expect(
        packageImports,
        isEmpty,
        reason: 'package:-Imports gefunden in:\n${packageImports.join('\n')}\nDie Engine darf nur dart:core importieren.',
      );
    });
  });
}

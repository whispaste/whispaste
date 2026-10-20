import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  group('encodeReplacementsCsv', () {
    test('writes a BOM, the header and CRLF records', () {
      final csv = encodeReplacementsCsv(const [
        ReplacementCsvRow(
          triggers: ['mfg'],
          replacement: 'Mit freundlichen Grüßen',
        ),
      ]);
      expect(csv.startsWith('﻿'), isTrue);
      expect(
        csv.substring(1),
        'triggers,replacement,match_mode,threshold\r\n'
        'mfg,Mit freundlichen Grüßen,exact,\r\n',
      );
    });

    test('quotes fields with commas, quotes and line breaks', () {
      final csv = encodeReplacementsCsv(const [
        ReplacementCsvRow(
          triggers: ['a', 'b'],
          replacement: 'Zeile, "eins"\nZeile zwei',
        ),
      ]);
      expect(csv, contains('a|b,"Zeile, ""eins""\nZeile zwei",exact,'));
    });
  });

  group('round trip', () {
    test('export then import gives back the same entries', () {
      const rows = [
        ReplacementCsvRow(
          triggers: ['mfg', 'm f g'],
          replacement: 'Mit freundlichen Grüßen',
        ),
        ReplacementCsvRow(
          triggers: ['pipe|name', r'back\slash'],
          replacement: r'Zeile\nZwei',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: fuzzyThresholdStrict,
        ),
        ReplacementCsvRow(
          triggers: ['Ünterstützung'],
          replacement: 'Поддержка, 支持',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: 0.8,
        ),
      ];
      final result = parseReplacementsCsv(encodeReplacementsCsv(rows));

      expect(result.errors, isEmpty);
      expect(result.rows.map((r) => r.triggers), [
        ['mfg', 'm f g'],
        ['pipe|name', r'back\slash'],
        ['Ünterstützung'],
      ]);
      expect(result.rows[1].matchMode, TextReplacementMatchMode.fuzzy);
      expect(result.rows[1].fuzzyThreshold, fuzzyThresholdStrict);
      expect(result.rows[2].fuzzyThreshold, 0.8);
      expect(result.rows[0].replacement, 'Mit freundlichen Grüßen');
    });
  });

  group('parseReplacementsCsv', () {
    test('accepts a file without header, BOM or final newline', () {
      final result = parseReplacementsCsv('lg,Liebe Grüße');
      expect(result.errors, isEmpty);
      expect(result.rows.single.triggers, ['lg']);
      expect(result.rows.single.matchMode, TextReplacementMatchMode.exact);
    });

    test('an empty match mode is exact and an empty threshold is standard', () {
      final result = parseReplacementsCsv(
        'triggers,replacement,match_mode,threshold\n'
        'omw,on my way,,\n'
        'teh,the,fuzzy,\n',
      );
      expect(result.rows[0].matchMode, TextReplacementMatchMode.exact);
      expect(result.rows[0].fuzzyThreshold, isNull);
      expect(result.rows[1].matchMode, TextReplacementMatchMode.fuzzy);
      expect(result.rows[1].fuzzyThreshold, fuzzyThresholdStandard);
    });

    test('accepts named and numeric thresholds, with a decimal comma', () {
      final result = parseReplacementsCsv(
        'a,x,fuzzy,tolerant\nb,y,fuzzy,"0,75"\nc,z,fuzzy,1\n',
      );
      expect(result.errors, isEmpty);
      expect(result.rows[0].fuzzyThreshold, fuzzyThresholdTolerant);
      expect(result.rows[1].fuzzyThreshold, 0.75);
      expect(result.rows[2].fuzzyThreshold, 1.0);
    });

    test('reports each bad record with its physical line and skips it', () {
      final result = parseReplacementsCsv(
        'triggers,replacement,match_mode,threshold\n'
        'ok,fine\n'
        ' ,no trigger\n'
        'x,\n'
        'y\n'
        'z,w,sometimes\n'
        'v,u,fuzzy,nope\n'
        'q,r,fuzzy,0.3\n',
      );
      expect(result.rows.map((r) => r.triggers.single), ['ok']);
      expect(
        {for (final e in result.errors) e.line: e.reason},
        {
          3: ReplacementCsvErrorReason.emptyTrigger,
          4: ReplacementCsvErrorReason.emptyReplacement,
          5: ReplacementCsvErrorReason.missingFields,
          6: ReplacementCsvErrorReason.unknownMatchMode,
          7: ReplacementCsvErrorReason.invalidThreshold,
          8: ReplacementCsvErrorReason.invalidThreshold,
        },
      );
    });

    test('keeps the line number right after a quoted line break', () {
      final result = parseReplacementsCsv('a,"one\ntwo",exact\nb,\n');
      expect(result.rows.single.replacement, 'one\ntwo');
      expect(result.errors.single.line, 3);
      expect(
        result.errors.single.reason,
        ReplacementCsvErrorReason.emptyReplacement,
      );
    });

    test('a trigger over the length limit is refused', () {
      final long = 'x' * (replacementCsvMaxTriggerLength + 1);
      final result = parseReplacementsCsv('$long,ok\n');
      expect(result.rows, isEmpty);
      expect(
        result.errors.single.reason,
        ReplacementCsvErrorReason.triggerTooLong,
      );
    });

    test('an input over the byte limit is not read at all', () {
      final huge = 'a,b\n' * (replacementCsvMaxBytes ~/ 4 + 10);
      final result = parseReplacementsCsv(huge);
      expect(result.tooLarge, isTrue);
      expect(result.rows, isEmpty);
    });

    test('stops after the row limit and says so', () {
      final buffer = StringBuffer();
      for (var i = 0; i < replacementCsvMaxRows + 5; i++) {
        buffer.write('t$i,r$i\n');
      }
      final result = parseReplacementsCsv(buffer.toString());
      expect(result.rows, hasLength(replacementCsvMaxRows));
      expect(result.truncated, isTrue);
    });
  });

  group('formula neutralisation (WP-43a C-M-1)', () {
    test('a cell starting with a formula character is prefixed on export', () {
      final csv = encodeReplacementsCsv([
        const ReplacementCsvRow(
          triggers: ['=HYPERLINK("http://x")'],
          replacement: '+SUM(1;1)',
        ),
        const ReplacementCsvRow(triggers: ['@cmd'], replacement: '-1+1'),
      ]);
      expect(csv, contains("'=HYPERLINK"));
      expect(csv, contains("'+SUM"));
      expect(csv, contains("'@cmd"));
      expect(csv, contains("'-1+1"));
    });

    test('neutralised cells read back exactly, including a literal quote', () {
      final rows = [
        const ReplacementCsvRow(triggers: ['=alpha'], replacement: "'=beta"),
        const ReplacementCsvRow(triggers: ["''x"], replacement: '\tTab'),
      ];
      final parsed = parseReplacementsCsv(encodeReplacementsCsv(rows));
      expect(parsed.errors, isEmpty);
      expect(parsed.rows.map((r) => r.triggers.single).toList(), [
        '=alpha',
        "''x",
      ]);
      expect(parsed.rows.map((r) => r.replacement).toList(), [
        "'=beta",
        '\tTab',
      ]);
    });

    test('a file written with a leading formula cell is read as text', () {
      final parsed = parseReplacementsCsv(
        "triggers,replacement\r\n'=x,Ersatz\r\n",
      );
      expect(parsed.rows.single.triggers, ['=x']);
    });
  });

  group('line endings and quotes (WP-43a C-M-2)', () {
    test('CR-only line endings split records instead of joining them', () {
      final parsed = parseReplacementsCsv(
        'triggers,replacement\rhallo,Hallo Welt\rtest,Test',
      );
      expect(parsed.errors, isEmpty);
      expect(parsed.rows.map((r) => r.triggers.single), ['hallo', 'test']);
    });

    test('a quote in the middle of an unquoted field is kept as text', () {
      final parsed = parseReplacementsCsv(
        'hallo,Er sagt "Hi" und geht\r\ntest,Test\r\n',
      );
      expect(parsed.errors, isEmpty);
      expect(parsed.rows.length, 2);
      expect(parsed.rows.first.replacement, 'Er sagt "Hi" und geht');
      expect(parsed.rows.last.triggers.single, 'test');
    });
  });
}

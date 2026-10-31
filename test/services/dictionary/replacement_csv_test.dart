import 'dart:convert';

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

  group('package metadata (R-08)', () {
    test('export writes the metadata record first and import reads it', () {
      final csv = encodeReplacementsCsv(
        const [
          ReplacementCsvRow(triggers: ['mfg'], replacement: 'Gruß'),
        ],
        meta: ReplacementCsvMeta(
          name: 'Support, Team',
          created: DateTime(2026, 10, 18),
        ),
      );
      expect(
        csv.substring(1),
        '#whispaste-dictionary,format=1,type=replacements,'
        '"name=Support, Team",created=2026-10-18\r\n'
        'triggers,replacement,match_mode,threshold\r\n'
        'mfg,Gruß,exact,\r\n',
      );
      final result = parseReplacementsCsv(csv);
      expect(result.refusal, isNull);
      expect(result.errors, isEmpty);
      expect(result.meta?.name, 'Support, Team');
      expect(result.meta?.created, DateTime(2026, 10, 18));
      expect(result.rows.single.replacement, 'Gruß');
    });

    test('a file without metadata is read as before', () {
      final result = parseReplacementsCsv(
        '﻿triggers,replacement,match_mode,threshold\r\nmfg,Gruß,exact,\r\n',
      );
      expect(result.meta, isNull);
      expect(result.refusal, isNull);
      expect(result.rows.single.triggers, ['mfg']);
    });

    test('the name is sanitised and cut to 80 characters', () {
      final result = parseReplacementsCsv(
        '#whispaste-dictionary,format=1,'
        'name=  A\u0007${'b' * 100}\u202E  \r\n'
        'mfg,x\r\n',
      );
      expect(result.meta?.name, isNotNull);
      expect(result.meta!.name!.length, 80);
      expect(result.meta!.name!.startsWith('Ab'), isTrue);
      expect(result.meta!.name!.contains('\u0007'), isFalse);
      expect(result.meta!.name!.contains('\u202E'), isFalse);
    });

    test('an invalid or impossible date is ignored, not refused', () {
      for (final date in ['18.10.2026', '2026-02-30', '2026-1-1', '']) {
        final result = parseReplacementsCsv(
          '#whispaste-dictionary,format=1,created=$date\r\nmfg,x\r\n',
        );
        expect(result.refusal, isNull, reason: date);
        expect(result.meta?.created, isNull, reason: date);
        expect(result.rows, hasLength(1), reason: date);
      }
    });

    test('a missing, empty or newer format refuses the whole file', () {
      for (final first in [
        '#whispaste-dictionary,type=replacements',
        '#whispaste-dictionary,format=',
        '#whispaste-dictionary,format=2,type=replacements',
      ]) {
        final result = parseReplacementsCsv('$first\r\nmfg,x\r\nlg,y\r\n');
        expect(
          result.refusal,
          ReplacementCsvRefusal.unsupportedFormat,
          reason: first,
        );
        expect(result.rows, isEmpty, reason: first);
        expect(result.errors, isEmpty, reason: first);
      }
    });

    test('an unknown package type refuses the file', () {
      final result = parseReplacementsCsv(
        '#whispaste-dictionary,format=1,type=snippets\r\nmfg,x\r\n',
      );
      expect(result.refusal, ReplacementCsvRefusal.unsupportedType);
      expect(result.rows, isEmpty);
    });

    test('a missing type counts as replacements', () {
      final result = parseReplacementsCsv(
        '#whispaste-dictionary,format=1\r\nmfg,x\r\n',
      );
      expect(result.refusal, isNull);
      expect(result.rows.single.triggers, ['mfg']);
    });

    test('the marker counts only as the first record', () {
      final result = parseReplacementsCsv(
        'mfg,x\r\n#whispaste-dictionary,format=9\r\n',
      );
      expect(result.refusal, isNull);
      expect(result.rows.map((r) => r.triggers.single), [
        'mfg',
        '#whispaste-dictionary',
      ]);
    });
  });

  group('field separator', () {
    test('a semicolon file with a header is read (German Excel)', () {
      final result = parseReplacementsCsv(
        'triggers;replacement;match_mode;threshold\r\n'
        'mfg;Mit freundlichen Grüßen;exact;\r\n',
      );
      expect(result.errors, isEmpty);
      expect(result.rows.single.replacement, 'Mit freundlichen Grüßen');
    });

    test('a semicolon metadata record sets the separator for the file', () {
      final result = parseReplacementsCsv(
        '#whispaste-dictionary;format=1;name=Test\r\n'
        'mfg;Gruß\r\n',
      );
      expect(result.meta?.name, 'Test');
      expect(result.rows.single.triggers, ['mfg']);
    });

    test('a comma file keeps semicolons inside its fields', () {
      final result = parseReplacementsCsv('mfg,Hallo; Welt\r\n');
      expect(result.errors, isEmpty);
      expect(result.rows.single.replacement, 'Hallo; Welt');
    });
  });

  group('byte decoding', () {
    test('valid UTF-8 with umlauts and Cyrillic decodes', () {
      final text = decodeReplacementsCsvBytes(utf8.encode('mfg,Grüße,Привет'));
      expect(text, 'mfg,Grüße,Привет');
    });

    test('invalid UTF-8 is refused', () {
      expect(decodeReplacementsCsvBytes([0x6d, 0x66, 0x67, 0xe4]), isNull);
    });

    test('a NUL byte is refused, even where UTF-8 accepts it', () {
      expect(decodeReplacementsCsvBytes([0x6d, 0x00, 0x66]), isNull);
    });

    test('UTF-16 text is refused', () {
      // UTF-16 LE BOM followed by "mfg": the bytes contain NUL bytes.
      final bytes = [0xff, 0xfe, 0x6d, 0x00, 0x66, 0x00, 0x67, 0x00];
      expect(decodeReplacementsCsvBytes(bytes), isNull);
    });
  });

  group('forbidden characters', () {
    String row(String cell) => 'mfg,$cell\r\n';

    test('C0 and DEL controls in a field make the row fail', () {
      for (final c in ['\u0001', '\u000b', '\u001b', '\u007f', '\u0085']) {
        final result = parseReplacementsCsv(row('a${c}b'));
        expect(
          result.errors.single.reason,
          ReplacementCsvErrorReason.controlCharacter,
          reason: c.codeUnits.toString(),
        );
        expect(result.errors.single.line, 1);
      }
    });

    test('bidi embedding and isolate controls make the row fail', () {
      for (final c in ['\u202E', '\u2066']) {
        final result = parseReplacementsCsv('mfg$c,x\r\n');
        expect(
          result.errors.single.reason,
          ReplacementCsvErrorReason.controlCharacter,
        );
      }
    });

    test('a line break inside a quoted field is kept (round trip)', () {
      final result = parseReplacementsCsv('mfg,"Zeile eins\nZeile zwei"\r\n');
      expect(result.errors, isEmpty);
      expect(result.rows.single.replacement, 'Zeile eins\nZeile zwei');
    });

    test('a tab inside a field is allowed', () {
      final result = parseReplacementsCsv('mfg,a\tb\r\n');
      expect(result.errors, isEmpty);
      expect(result.rows.single.replacement, 'a\tb');
    });

    test('the error reports the line of the offending row', () {
      final result = parseReplacementsCsv('mfg,x\r\nlg,a\u0001\r\nsig,y\r\n');
      expect(result.errors.single.line, 2);
      expect(result.rows.map((r) => r.triggers.single), ['mfg', 'sig']);
    });
  });

  group('formula cells', () {
    test('import keeps formula-like text as text, removing one apostrophe', () {
      final result = parseReplacementsCsv(
        "triggers,replacement\r\n'=HYPERLINK,'=1+1\r\n+1,-x\r\n",
      );
      expect(result.errors, isEmpty);
      expect(result.rows[0].triggers, ['=HYPERLINK']);
      expect(result.rows[0].replacement, '=1+1');
      expect(result.rows[1].triggers, ['+1']);
      expect(result.rows[1].replacement, '-x');
    });
  });

  group('limits (R-08)', () {
    test('50 triggers are accepted, 51 are refused', () {
      final ok = List.generate(50, (i) => 'trigger$i').join('|');
      final tooMany = List.generate(51, (i) => 'trigger$i').join('|');
      final result = parseReplacementsCsv('$ok,x\r\n$tooMany,x\r\n');
      expect(result.rows, hasLength(1));
      expect(
        result.errors.single.reason,
        ReplacementCsvErrorReason.tooManyTriggers,
      );
      expect(result.errors.single.line, 2);
    });

    test('trigger length 200 is accepted, 201 is refused', () {
      final result = parseReplacementsCsv(
        '${'a' * 200},x\r\n${'b' * 201},x\r\n',
      );
      expect(result.rows, hasLength(1));
      expect(
        result.errors.single.reason,
        ReplacementCsvErrorReason.triggerTooLong,
      );
    });

    test('replacement length 5000 is accepted, 5001 is refused', () {
      final result = parseReplacementsCsv(
        'a,${'x' * 5000}\r\nb,${'y' * 5001}\r\n',
      );
      expect(result.rows, hasLength(1));
      expect(
        result.errors.single.reason,
        ReplacementCsvErrorReason.replacementTooLong,
      );
    });

    test('more than 5000 rows are cut and the result is truncated', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 5001; i++) {
        buffer.write('t$i,r$i\r\n');
      }
      final result = parseReplacementsCsv(buffer.toString());
      expect(result.truncated, isTrue);
      expect(result.rows.length + result.errors.length, 5000);
    });

    test('an input above 1 MiB is refused before reading', () {
      final result = parseReplacementsCsv(
        'mfg,${'x' * (replacementCsvMaxBytes + 1)}\r\n',
      );
      expect(result.tooLarge, isTrue);
      expect(result.rows, isEmpty);
    });
  });
}

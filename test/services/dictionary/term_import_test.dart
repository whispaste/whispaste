import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/term_import.dart';

void main() {
  List<String?> parse(String text, [String name = 'terms.csv']) =>
      decodeTermImport(utf8.encode(text), filename: name);

  test(
    'example files detect text, CSV pairs, JSON export and local settings',
    () {
      for (final name in [
        'terms.txt',
        'pairs.csv',
        'local_vocabulary.json',
        'export_words.json',
      ]) {
        expect(
          decodeTermImport(
            File('test/fixtures/dictionary/$name').readAsBytesSync(),
            filename: name,
          ),
          ['Kubernetes', 'OpenAI', 'Straße'],
          reason: name,
        );
      }
    },
  );

  test(
    'headers are optional; CSV quoting, separators and line endings survive',
    () {
      for (final input in [
        '\uFEFFterm\r\nKubernetes\r\nOpenAI',
        'Kubernetes\nOpenAI\n',
        'wrong,right\nkubernets,Kubernetes\nopen ai,OpenAI',
        'kubernets;Kubernetes\ropen ai;OpenAI',
        'from\tto\r\nkubernets\tKubernetes\r\nopen ai\tOpenAI',
      ]) {
        expect(parse(input), ['Kubernetes', 'OpenAI']);
      }
      expect(parse('"semi;colon","quoted ""word"""'), ['quoted "word"']);
      expect(parse('"multi\nline"'), ['multi\nline']);
      expect(parse('term\n"word,word"'), ['word,word']);
      expect(parse('wrong,wrong\nright,right'), ['wrong', 'right']);
    },
  );

  test(
    'JSON word and correction containers keep only the corrected spelling',
    () {
      for (final input in [
        '{"customWords":[{"word":"OpenAI"}]}',
        '{"dictionary":[{"phrase":"OpenAI"}]}',
        '{"words":[{"text":"OpenAI"}]}',
        '{"replacements":[{"from":"open ai","to":"OpenAI"}]}',
        '[{"original":"open ai","replacement":"OpenAI"}]',
      ]) {
        expect(parse(input, 'settings.json'), ['OpenAI']);
      }
    },
  );

  test('UTF-16 BOM exports decode in either byte order', () {
    for (final little in [true, false]) {
      final bytes = <int>[
        if (little) ...[255, 254] else ...[254, 255],
      ];
      for (final c in 'term\r\nStraße'.codeUnits) {
        bytes.addAll(little ? [c & 255, c >> 8] : [c >> 8, c & 255]);
      }
      expect(decodeTermImport(bytes, filename: 'terms.txt'), ['Straße']);
    }
  });

  test(
    'unknown, binary, malformed and oversized files fail without a partial list',
    () {
      for (final input in [
        '',
        '"unfinished',
        '"closed"garbage',
        '{bad json',
        '{"settings":true}',
        '<plist>word</plist>',
        'word\u0000word',
      ]) {
        expect(() => parse(input), throwsFormatException, reason: input);
      }
      expect(() => parse('word', 'dictionary.db'), throwsFormatException);
      expect(
        () => decodeTermImport([255], filename: 'terms.txt'),
        throwsFormatException,
      );
      expect(
        () => decodeTermImport(
          List.filled(termImportMaxBytes + 1, 65),
          filename: 'terms.txt',
        ),
        throwsFormatException,
      );
      expect(
        () => parse(List.filled(termImportMaxRows + 1, 'alpha').join('\n')),
        throwsFormatException,
      );
      expect(
        parse(List.filled(termImportMaxRows, 'alpha').join('\n')),
        hasLength(termImportMaxRows),
      );
    },
  );

  test(
    'preview classifies duplicates, bad fields, limits and trigger conflicts',
    () {
      final rows = planTermImport(
        [
          ' Kubernetes ',
          'OPENAI',
          'kubernetes',
          null,
          '',
          '...',
          'a' * 61,
          'one,two',
          'one\ntwo',
          'trigger',
          '語' * 60,
        ],
        vocabulary: 'OpenAI',
        triggers: ['trigger'],
      );
      expect(rows.map((r) => r.status), [
        TermImportStatus.fresh,
        TermImportStatus.existing,
        TermImportStatus.existing,
        ...List.filled(7, TermImportStatus.invalid),
        TermImportStatus.fresh,
      ]);
      expect(
        planTermImport(parse('a,b,c'), vocabulary: '').single.status,
        TermImportStatus.invalid,
      );
    },
  );

  test(
    'confirmation merges selected terms into the latest vocabulary without overwriting',
    () {
      expect(
        mergeImportedTerms(
          'OpenAI\nUnrelated',
          ['OPENAI', 'Kubernetes', 'trigger'],
          triggers: ['trigger'],
        ),
        'OpenAI\nUnrelated\nKubernetes',
      );
    },
  );

  test('CSV export round trips Unicode, quotes and formula-like terms', () {
    const terms = [
      'Straße',
      'שלום',
      'two "words"',
      '=Formula',
      "'=Literal",
      'semi;colon',
    ];
    final csv = encodeTermsCsv(terms);
    expect(csv, contains('"\'=Formula"'));
    expect(parse(csv), terms);
    expect(mergeImportedTerms('', parse(csv).cast<String>()), terms.join(', '));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/history/data/export_service.dart';

final _sampleEntries = [
  const ExportEntry(
    id: 'e1',
    title: 'Meeting notes',
    text: 'Discuss roadmap for Q3.',
    timestamp: '2026-04-05 10:30:00',
    duration: 45.0,
    language: 'en',
    tags: ['work', 'meeting'],
    pinned: true,
    model: 'whisper-large-v3',
    isLocal: true,
  ),
  const ExportEntry(
    id: 'e2',
    title: 'Quick reminder',
    text: 'Buy groceries.',
    timestamp: '2026-04-05 14:00:00',
    duration: 5.2,
    language: 'de',
  ),
];

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('export_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ExportService', () {
    test('exports TXT format', () async {
      final path = '${tempDir.path}/test.txt';
      final bytes = await ExportService.export(_sampleEntries, ExportFormat.txt, path);

      expect(bytes, greaterThan(0));
      final content = File(path).readAsStringSync();
      expect(content, contains('Meeting notes'));
      expect(content, contains('Buy groceries.'));
      expect(content, contains('---')); // separator between entries
    });

    test('exports Markdown format', () async {
      final path = '${tempDir.path}/test.md';
      final bytes = await ExportService.export(_sampleEntries, ExportFormat.md, path);

      expect(bytes, greaterThan(0));
      final content = File(path).readAsStringSync();
      expect(content, contains('# Meeting notes'));
      expect(content, contains('**Language:** EN'));
      expect(content, contains('`work`'));
    });

    test('exports JSON format', () async {
      final path = '${tempDir.path}/test.json';
      final bytes = await ExportService.export(_sampleEntries, ExportFormat.json, path);

      expect(bytes, greaterThan(0));
      final content = File(path).readAsStringSync();
      final parsed = jsonDecode(content) as List;
      expect(parsed, hasLength(2));
      expect(parsed[0]['title'], equals('Meeting notes'));
      expect(parsed[0]['tags'], equals(['work', 'meeting']));
      expect(parsed[1]['title'], equals('Quick reminder'));
    });

    test('exports CSV format with header', () async {
      final path = '${tempDir.path}/test.csv';
      final bytes = await ExportService.export(_sampleEntries, ExportFormat.csv, path);

      expect(bytes, greaterThan(0));
      final lines = File(path).readAsLinesSync();
      expect(lines.first, startsWith('ID,Title,Text'));
      expect(lines, hasLength(3)); // header + 2 entries
    });

    test('exports DOCX as valid ZIP', () async {
      final path = '${tempDir.path}/test.docx';
      final bytes = await ExportService.export(_sampleEntries, ExportFormat.docx, path);

      expect(bytes, greaterThan(0));
      final fileBytes = File(path).readAsBytesSync();
      // ZIP files start with PK header
      expect(fileBytes[0], equals(0x50)); // P
      expect(fileBytes[1], equals(0x4B)); // K
    });

    test('returns 0 for empty entries', () async {
      final path = '${tempDir.path}/empty.txt';
      final bytes = await ExportService.export([], ExportFormat.txt, path);
      expect(bytes, equals(0));
    });

    test('defaultFilename uses entry title for single entry', () {
      final name = ExportService.defaultFilename(
        [_sampleEntries.first],
        ExportFormat.md,
      );
      expect(name, equals('Meeting notes.md'));
    });

    test('defaultFilename uses generic name for multiple entries', () {
      final name = ExportService.defaultFilename(_sampleEntries, ExportFormat.json);
      expect(name, equals('whispaste-export.json'));
    });

    test('CSV escapes formula injection', () async {
      final entries = [
        const ExportEntry(
          id: 'evil',
          title: '=HYPERLINK("http://evil.com")',
          text: '+cmd|/C calc',
          timestamp: '2026-01-01 00:00:00',
        ),
      ];
      final path = '${tempDir.path}/evil.csv';
      await ExportService.export(entries, ExportFormat.csv, path);

      final content = File(path).readAsStringSync();
      // Formula chars should be prefixed with tab
      expect(content, isNot(contains(',=HYPERLINK')));
      expect(content, isNot(contains(',+cmd')));
    });
  });
}

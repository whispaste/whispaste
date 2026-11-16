/// Local vocabulary interchange. Pair formats contribute the corrected word;
/// importing terms never creates replacement rules or overwrites existing terms.
library;

import 'dart:convert';

import 'entry_validation.dart';
import 'vocabulary_terms.dart';

const termImportMaxBytes = 1024 * 1024;
const termImportMaxRows = 5000;

enum TermImportStatus { fresh, existing, invalid }

class TermImportRow {
  const TermImportRow(this.term, this.status);
  final String term;
  final TermImportStatus status;
}

/// Throws [FormatException] for unreadable, unknown or oversized documents.
/// A malformed document is never partially accepted.
List<String?> decodeTermImport(List<int> bytes, {required String filename}) {
  if (bytes.length > termImportMaxBytes) throw const FormatException('size');
  String text;
  if (bytes.length >= 2 &&
      ((bytes[0] == 255 && bytes[1] == 254) ||
          (bytes[0] == 254 && bytes[1] == 255))) {
    if (bytes.length.isOdd) throw const FormatException('encoding');
    final little = bytes[0] == 255;
    text = String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2)
        little
            ? bytes[i] + (bytes[i + 1] << 8)
            : (bytes[i] << 8) + bytes[i + 1],
    ]);
  } else {
    text = utf8.decode(bytes);
  }
  text = text.replaceFirst(RegExp('^\uFEFF'), '').trim();
  if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(text)) {
    throw const FormatException('binary');
  }
  if (text.isEmpty) throw const FormatException('empty');
  final extension = filename.split('.').last.toLowerCase();
  List<String?> terms;
  if (text.startsWith('[') || text.startsWith('{') || extension == 'json') {
    Object? data = jsonDecode(text);
    if (data is Map<String, dynamic>) {
      // Recognised vocabulary containers from local settings/export files.
      data =
          data['vocabulary'] ??
          data['customWords'] ??
          data['dictionary'] ??
          data['words'] ??
          data['replacements'];
    }
    if (data is! List) throw const FormatException('format');
    terms = [
      for (final item in data)
        switch (item) {
          final String value => value,
          final Map<String, dynamic> value => _jsonTerm(value),
          _ => null,
        },
    ];
  } else {
    if (!['csv', 'txt', 'tsv'].contains(extension) || text.startsWith('<')) {
      throw const FormatException('format');
    }
    final records = _records(text, _delimiter(text));
    if (records.isNotEmpty && _header(records.first)) records.removeAt(0);
    terms = [
      for (final row in records)
        row.length == 1
            ? _restoreCell(row.first)
            : row.length == 2
            ? _restoreCell(row.last)
            : null,
    ];
  }
  if (terms.isEmpty || terms.length > termImportMaxRows) {
    throw const FormatException('rows');
  }
  return terms;
}

String? _jsonTerm(Map<String, dynamic> item) {
  final value =
      item['replacement'] ??
      item['to'] ??
      item['correct'] ??
      item['word'] ??
      item['phrase'] ??
      item['text'];
  return value is String ? value : null;
}

String _restoreCell(String term) =>
    RegExp(r"^'+[=+\-@]").hasMatch(term) ? term.substring(1) : term;

bool _header(List<String> row) {
  final keys = row.map((s) => s.trim().toLowerCase()).toList();
  return (keys.length == 1 &&
          {
            'term',
            'word',
            'vocabulary',
            'begriff',
            'wort',
          }.contains(keys.first)) ||
      (keys.length == 2 &&
          {
            'wrong',
            'incorrect',
            'from',
            'source',
            'falsch',
            'trigger',
          }.contains(keys.first) &&
          {
            'right',
            'correct',
            'to',
            'replacement',
            'richtig',
            'target',
          }.contains(keys.last));
}

String _delimiter(String text) {
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted) {
      if ({',', ';', '\t'}.contains(c)) return c;
      if (c == '\r' || c == '\n') break;
    }
  }
  return ',';
}

/// RFC 4180 quoting, with CR, LF, CRLF, semicolon and tab separators.
List<List<String>> _records(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  var closed = false;
  void finishField() {
    row.add(field.toString());
    field = StringBuffer();
    closed = false;
  }

  void finishRow() {
    finishField();
    if (row.any((s) => s.trim().isNotEmpty)) rows.add(row);
    row = [];
    if (rows.length > termImportMaxRows + 1) {
      throw const FormatException('rows');
    }
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field.write(c);
      }
    } else if (c == delimiter) {
      finishField();
    } else if (c == '\n' || c == '\r') {
      finishRow();
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else if (c == '"' && field.isEmpty && !closed) {
      quoted = true;
    } else {
      if (closed && c.trim().isNotEmpty) throw const FormatException('quotes');
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('quotes');
  finishRow();
  return rows;
}

List<TermImportRow> planTermImport(
  Iterable<String?> candidates, {
  required String vocabulary,
  Iterable<String> triggers = const [],
}) {
  final seen = vocabularyTerms(vocabulary).map((s) => s.toLowerCase()).toSet();
  final result = <TermImportRow>[];
  for (final raw in candidates) {
    final term = raw?.trim() ?? '';
    final invalid =
        term.isEmpty ||
        RegExp(r'[,\r\n]').hasMatch(term) ||
        checkDictionaryEntry(term, existing: const [], triggers: triggers) !=
            null;
    final status = invalid
        ? TermImportStatus.invalid
        : seen.add(term.toLowerCase())
        ? TermImportStatus.fresh
        : TermImportStatus.existing;
    result.add(TermImportRow(term, status));
  }
  return result;
}

/// Re-evaluate at confirmation so concurrent additions cannot be overwritten.
String mergeImportedTerms(
  String vocabulary,
  Iterable<String> selected, {
  Iterable<String> triggers = const [],
}) {
  final added = planTermImport(
    selected,
    vocabulary: vocabulary,
    triggers: triggers,
  ).where((r) => r.status == TermImportStatus.fresh).map((r) => r.term);
  return encodeVocabulary([
    ...vocabularyTerms(vocabulary),
    ...added,
  ], style: vocabulary);
}

String encodeTermsCsv(Iterable<String> terms) {
  String cell(String s) {
    if (RegExp(r"^'*[=+\-@]").hasMatch(s)) s = "'$s";
    return '"${s.replaceAll('"', '""')}"';
  }

  return 'term\r\n${terms.map(cell).join('\r\n')}\r\n';
}

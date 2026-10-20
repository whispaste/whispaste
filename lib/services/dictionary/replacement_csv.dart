/// CSV import and export for the replacement dictionary (matrix 4.6).
///
/// Pure codec: no file access, no database. The UI reads the file through
/// the user's own selection (sandbox-safe) and hands the text here.
///
/// Layout, one entry per record:
///   triggers,replacement,match_mode,threshold
/// - `triggers`: one or more trigger phrases separated by `|`. A literal `|`
///   or `\` inside a phrase is written as `\|` or `\\`.
/// - `replacement`: the stored replacement text, escapes such as `\n` kept
///   as typed (the same syntax the editor documents).
/// - `match_mode`: `exact` (default when empty) or `fuzzy`.
/// - `threshold`: `strict`, `standard` or `tolerant` for fuzzy entries (the
///   three UI steps), or a number from 0.50 to 1.00. Empty for exact entries.
///
/// Parsing is lenient about line endings, a leading byte-order mark, a
/// missing final newline and a header row, and strict about content: every
/// bad record is reported with its line number and skipped, never guessed.
library;

import 'dart:convert';

import '../replacements/text_replacement_matcher.dart'
    show
        TextReplacementMatchMode,
        fuzzyThresholdStandard,
        fuzzyThresholdStrict,
        fuzzyThresholdTolerant;

/// Column names, in file order. The export writes this header, and the parser
/// skips a first record whose first field is `triggers`.
const List<String> replacementCsvHeader = [
  'triggers',
  'replacement',
  'match_mode',
  'threshold',
];

/// Files above this size are refused before parsing.
const int replacementCsvMaxBytes = 1024 * 1024;

/// Records above this count are not read; the result is marked truncated.
const int replacementCsvMaxRows = 5000;

/// Length limits per field. They keep one bad row from creating a
/// multi-megabyte trigger, which the matcher would then scan on every
/// dictation.
const int replacementCsvMaxTriggerLength = 200;
const int replacementCsvMaxReplacementLength = 5000;

/// One dictionary entry as it appears in a CSV file.
class ReplacementCsvRow {
  const ReplacementCsvRow({
    required this.triggers,
    required this.replacement,
    this.matchMode = TextReplacementMatchMode.exact,
    this.fuzzyThreshold,
  });

  final List<String> triggers;
  final String replacement;
  final TextReplacementMatchMode matchMode;

  /// Only set for [TextReplacementMatchMode.fuzzy].
  final double? fuzzyThreshold;
}

enum ReplacementCsvErrorReason {
  missingFields,
  emptyTrigger,
  triggerTooLong,
  emptyReplacement,
  replacementTooLong,
  unknownMatchMode,
  invalidThreshold,
}

class ReplacementCsvError {
  const ReplacementCsvError({required this.line, required this.reason});

  /// 1-based physical line where the record starts.
  final int line;
  final ReplacementCsvErrorReason reason;
}

class ReplacementCsvParseResult {
  const ReplacementCsvParseResult({
    required this.rows,
    required this.errors,
    this.truncated = false,
    this.tooLarge = false,
  });

  final List<ReplacementCsvRow> rows;
  final List<ReplacementCsvError> errors;

  /// More than [replacementCsvMaxRows] records; the rest were not read.
  final bool truncated;

  /// The input exceeded [replacementCsvMaxBytes]; nothing was read.
  final bool tooLarge;
}

/// Serialises [rows] with the header, a UTF-8 byte-order mark (so Excel
/// reads umlauts and Cyrillic correctly) and CRLF line endings.
String encodeReplacementsCsv(Iterable<ReplacementCsvRow> rows) {
  final out = StringBuffer('﻿')..write(_record(replacementCsvHeader));
  for (final row in rows) {
    out.write(
      _record([
        _neutraliseFormula(row.triggers.map(_escapeTrigger).join('|')),
        _neutraliseFormula(row.replacement),
        row.matchMode.name,
        _thresholdCell(row.matchMode, row.fuzzyThreshold),
      ]),
    );
  }
  return out.toString();
}

/// Parses [input] (the whole file as text). Never throws on bad content;
/// problems come back as [ReplacementCsvError]s.
ReplacementCsvParseResult parseReplacementsCsv(String input) {
  if (utf8.encode(input).length > replacementCsvMaxBytes) {
    return const ReplacementCsvParseResult(
      rows: [],
      errors: [],
      tooLarge: true,
    );
  }

  final records = _readRecords(input);
  final rows = <ReplacementCsvRow>[];
  final errors = <ReplacementCsvError>[];
  var truncated = false;
  var start = 0;
  if (records.isNotEmpty &&
      records.first.fields.first.trim().toLowerCase() == 'triggers') {
    start = 1;
  }

  for (var i = start; i < records.length; i++) {
    if (rows.length + errors.length >= replacementCsvMaxRows) {
      truncated = true;
      break;
    }
    final record = records[i];
    final result = _rowFromRecord(record.fields);
    if (result.$1 != null) {
      rows.add(result.$1!);
    } else {
      errors.add(ReplacementCsvError(line: record.line, reason: result.$2!));
    }
  }
  return ReplacementCsvParseResult(
    rows: rows,
    errors: errors,
    truncated: truncated,
  );
}

// ---------------------------------------------------------------------------
// Row validation
// ---------------------------------------------------------------------------

(ReplacementCsvRow?, ReplacementCsvErrorReason?) _rowFromRecord(
  List<String> fields,
) {
  if (fields.length < 2) {
    return (null, ReplacementCsvErrorReason.missingFields);
  }

  final triggers = _splitTriggers(
    _restoreFormula(fields[0]),
  ).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  if (triggers.isEmpty) {
    return (null, ReplacementCsvErrorReason.emptyTrigger);
  }
  if (triggers.any((t) => t.length > replacementCsvMaxTriggerLength)) {
    return (null, ReplacementCsvErrorReason.triggerTooLong);
  }

  final replacement = _restoreFormula(fields[1]);
  if (replacement.trim().isEmpty) {
    return (null, ReplacementCsvErrorReason.emptyReplacement);
  }
  if (replacement.length > replacementCsvMaxReplacementLength) {
    return (null, ReplacementCsvErrorReason.replacementTooLong);
  }

  final modeCell = fields.length > 2 ? fields[2].trim().toLowerCase() : '';
  final TextReplacementMatchMode mode;
  switch (modeCell) {
    case '':
    case 'exact':
      mode = TextReplacementMatchMode.exact;
    case 'fuzzy':
      mode = TextReplacementMatchMode.fuzzy;
    default:
      return (null, ReplacementCsvErrorReason.unknownMatchMode);
  }

  double? threshold;
  if (mode == TextReplacementMatchMode.fuzzy) {
    final cell = fields.length > 3 ? fields[3].trim().toLowerCase() : '';
    threshold = _parseThreshold(cell);
    if (threshold == null) {
      return (null, ReplacementCsvErrorReason.invalidThreshold);
    }
  }

  return (
    ReplacementCsvRow(
      triggers: triggers,
      replacement: replacement,
      matchMode: mode,
      fuzzyThreshold: threshold,
    ),
    null,
  );
}

double? _parseThreshold(String cell) {
  switch (cell) {
    case '':
    case 'standard':
      return fuzzyThresholdStandard;
    case 'strict':
      return fuzzyThresholdStrict;
    case 'tolerant':
      return fuzzyThresholdTolerant;
  }
  final value = double.tryParse(cell.replaceAll(',', '.'));
  if (value == null || value.isNaN || value < 0.5 || value > 1.0) {
    return null;
  }
  return value;
}

String _thresholdCell(TextReplacementMatchMode mode, double? threshold) {
  if (mode != TextReplacementMatchMode.fuzzy || threshold == null) return '';
  if (threshold == fuzzyThresholdStrict) return 'strict';
  if (threshold == fuzzyThresholdStandard) return 'standard';
  if (threshold == fuzzyThresholdTolerant) return 'tolerant';
  return threshold.toStringAsFixed(2);
}

// ---------------------------------------------------------------------------
// Trigger escaping
// ---------------------------------------------------------------------------

/// Splits a `triggers` cell on unescaped `|`. `\|` and `\\` are unescaped to
/// the literal character; any other backslash is kept as typed.
List<String> _splitTriggers(String raw) {
  final parts = <String>[];
  final current = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == r'\' && i + 1 < raw.length) {
      final next = raw[i + 1];
      if (next == '|' || next == r'\') {
        current.write(next);
        i++;
        continue;
      }
    }
    if (c == '|') {
      parts.add(current.toString());
      current.clear();
      continue;
    }
    current.write(c);
  }
  parts.add(current.toString());
  return parts;
}

String _escapeTrigger(String trigger) =>
    trigger.replaceAll(r'\', r'\\').replaceAll('|', r'\|');

// ---------------------------------------------------------------------------
// Formula neutralisation (WP-43a C-M-1)
// ---------------------------------------------------------------------------

/// A cell that spreadsheet programs would evaluate as a formula (or that
/// starts with a tab/CR) gets a leading apostrophe on export. Cells that
/// already begin with apostrophes followed by such a character get one more,
/// so the mapping is reversible: [_restoreFormula] removes exactly one
/// apostrophe from cells matching the same pattern with one extra apostrophe.
final _formulaCellOut = RegExp(r"^'*[=+\-@\t\r]");
final _formulaCellIn = RegExp(r"^'+[=+\-@\t\r]");

String _neutraliseFormula(String value) =>
    _formulaCellOut.hasMatch(value) ? "'$value" : value;

String _restoreFormula(String cell) =>
    _formulaCellIn.hasMatch(cell) ? cell.substring(1) : cell;

// ---------------------------------------------------------------------------
// RFC 4180 reader and writer
// ---------------------------------------------------------------------------

class _CsvRecord {
  const _CsvRecord(this.line, this.fields);

  final int line;
  final List<String> fields;
}

/// Reads all records. Quoted fields may contain commas, quotes (`""`) and
/// line breaks. Empty physical lines are skipped.
List<_CsvRecord> _readRecords(String input) {
  final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
  final scan = _CsvScan(text);
  for (var i = 0; i < text.length; i++) {
    i = scan.inQuotes ? scan.readQuoted(i) : scan.readUnquoted(i);
  }
  scan.finish();
  return scan.records;
}

/// State of one pass over the CSV text. The methods are the two modes of the
/// reader: inside a quoted field and outside one.
class _CsvScan {
  _CsvScan(this._text);

  final String _text;
  final List<_CsvRecord> records = [];
  var _fields = <String>[];
  final _field = StringBuffer();
  var inQuotes = false;
  var _line = 1;
  var _recordLine = 1;

  void _endRecord() {
    _fields.add(_field.toString());
    _field.clear();
    if (!(_fields.length == 1 && _fields.first.isEmpty)) {
      records.add(_CsvRecord(_recordLine, _fields));
    }
    _fields = <String>[];
  }

  void _newLine() {
    _endRecord();
    _line++;
    _recordLine = _line;
  }

  /// Consumes one character of a quoted field; returns the index of the last
  /// character consumed.
  int readQuoted(int i) {
    final c = _text[i];
    if (c == '"') {
      if (i + 1 < _text.length && _text[i + 1] == '"') {
        _field.write('"');
        return i + 1;
      }
      inQuotes = false;
      return i;
    }
    if (c == '\n') _line++;
    _field.write(c);
    return i;
  }

  /// Consumes one character outside quotes; returns the index of the last
  /// character consumed.
  int readUnquoted(int i) {
    final c = _text[i];
    final nextIsLf = i + 1 < _text.length && _text[i + 1] == '\n';
    // CRLF is one line break; a lone CR (classic Mac) is one too.
    if (c == '\r' && nextIsLf) return i;
    if (c == '\r' || c == '\n') {
      _newLine();
    } else if (c == ',') {
      _fields.add(_field.toString());
      _field.clear();
    } else if (c == '"' && _field.isEmpty) {
      // A quote opens a quoted field only at its start. Elsewhere it is text,
      // so it never swallows the rest of the file.
      inQuotes = true;
    } else {
      _field.write(c);
    }
    return i;
  }

  /// Ends the last record when the text does not end with a line break.
  void finish() {
    if (_field.isNotEmpty || _fields.isNotEmpty) {
      _endRecord();
    }
  }
}

String _record(List<String> fields) =>
    '${fields.map(_quoteField).join(',')}\r\n';

String _quoteField(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

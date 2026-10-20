/// CSV import and export for the replacement dictionary (matrix 4.6).
///
/// Pure codec: no file access, no database. The UI reads the file through
/// the user's own selection (sandbox-safe) and hands the bytes or text here.
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
/// Package files (`.csv`) start with one metadata record, written by the
/// export and optional on import:
///   #whispaste-dictionary,format=1,type=replacements,name=...,created=...
/// The format version is required; a file whose format or type this version
/// does not know is refused as a whole. A file without that record is read
/// as before.
///
/// Parsing is lenient about line endings, a leading byte-order mark, a
/// missing final newline, a header row, and a `;` field separator (German
/// Excel), and strict about content: every bad record is reported with its
/// line number and skipped, never guessed.
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

/// Every trigger of a row is compiled into the matcher and scanned on every
/// dictation, so a row cannot carry an unbounded number of them.
const int replacementCsvMaxTriggersPerRow = 50;

/// First field of the package metadata record (compared case-insensitively).
const String replacementCsvMetaMarker = '#whispaste-dictionary';

/// The only package format version this build reads and writes.
const int replacementCsvFormatVersion = 1;

/// The only package type this build reads and writes. Snippets are not part
/// of the replacement package (see the R-08 ticket, section 3.3a).
const String replacementCsvPackageType = 'replacements';

/// Package names are cut to this many characters.
const int replacementCsvMaxNameLength = 80;

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

/// Package metadata from the first record of a file. Both fields are optional.
class ReplacementCsvMeta {
  const ReplacementCsvMeta({this.name, this.created});

  /// Sanitised package name, or `null` when the file has none.
  final String? name;

  /// Export date, date only (time of day is dropped).
  final DateTime? created;
}

/// Why a whole file was refused, before any row was read.
enum ReplacementCsvRefusal {
  /// The metadata record has no `format=1` (missing, empty or another value).
  unsupportedFormat,

  /// The metadata record names a package type this build does not read.
  unsupportedType,
}

enum ReplacementCsvErrorReason {
  missingFields,
  emptyTrigger,
  triggerTooLong,
  tooManyTriggers,
  emptyReplacement,
  replacementTooLong,
  unknownMatchMode,
  invalidThreshold,
  controlCharacter,
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
    this.meta,
    this.refusal,
  });

  final List<ReplacementCsvRow> rows;
  final List<ReplacementCsvError> errors;

  /// More than [replacementCsvMaxRows] records; the rest were not read.
  final bool truncated;

  /// The input exceeded [replacementCsvMaxBytes]; nothing was read.
  final bool tooLarge;

  /// The package metadata, when the file has a metadata record.
  final ReplacementCsvMeta? meta;

  /// Set when the whole file is refused because of its metadata record.
  /// Then [rows] and [errors] are empty.
  final ReplacementCsvRefusal? refusal;
}

/// Serialises [rows] with the header, a UTF-8 byte-order mark (so Excel
/// reads umlauts and Cyrillic correctly) and CRLF line endings. With [meta],
/// a package metadata record is written first.
String encodeReplacementsCsv(
  Iterable<ReplacementCsvRow> rows, {
  ReplacementCsvMeta? meta,
}) {
  final out = StringBuffer('﻿');
  if (meta != null) out.write(_record(_metaFields(meta)));
  out.write(_record(replacementCsvHeader));
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

/// Decodes the raw bytes of a file as UTF-8. Returns `null` when the bytes are
/// not valid UTF-8 or contain a NUL byte (UTF-16 and Latin-1 files look like
/// one of the two), so the caller can refuse the file with one message.
String? decodeReplacementsCsvBytes(List<int> bytes) {
  if (bytes.contains(0)) return null;
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Parses [input] (the whole file as text). Never throws on bad content;
/// problems come back as [ReplacementCsvError]s or as a [refusal].
ReplacementCsvParseResult parseReplacementsCsv(String input) {
  if (utf8.encode(input).length > replacementCsvMaxBytes) {
    return const ReplacementCsvParseResult(
      rows: [],
      errors: [],
      tooLarge: true,
    );
  }

  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final records = _readRecords(text, _delimiterFor(text));
  final rows = <ReplacementCsvRow>[];
  final errors = <ReplacementCsvError>[];
  var truncated = false;

  ReplacementCsvMeta? meta;
  var start = 0;
  if (records.isNotEmpty && _isMetaRecord(records.first.fields)) {
    final parsed = _parseMeta(records.first.fields);
    if (parsed.refusal != null) {
      return ReplacementCsvParseResult(
        rows: const [],
        errors: const [],
        refusal: parsed.refusal,
      );
    }
    meta = parsed.meta;
    start = 1;
  }
  if (start < records.length && _isHeader(records[start].fields)) {
    start++;
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
    meta: meta,
  );
}

/// Makes a package name safe to store and show: control and format characters
/// removed, trimmed, cut to [replacementCsvMaxNameLength] characters.
String sanitizeReplacementPackageName(String raw) {
  final clean = raw.replaceAll(_unsafeNameCharacters, '').trim();
  final runes = clean.runes;
  if (runes.length <= replacementCsvMaxNameLength) return clean;
  return String.fromCharCodes(runes.take(replacementCsvMaxNameLength)).trim();
}

final _unsafeNameCharacters = RegExp(r'[\p{Cc}\p{Cf}]', unicode: true);

// ---------------------------------------------------------------------------
// Package metadata
// ---------------------------------------------------------------------------

List<String> _metaFields(ReplacementCsvMeta meta) {
  final name = meta.name == null
      ? ''
      : sanitizeReplacementPackageName(meta.name!);
  final created = meta.created;
  return [
    replacementCsvMetaMarker,
    'format=$replacementCsvFormatVersion',
    'type=$replacementCsvPackageType',
    if (name.isNotEmpty) 'name=$name',
    if (created != null) 'created=${_isoDate(created)}',
  ];
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

bool _isMetaRecord(List<String> fields) =>
    fields.first.trim().toLowerCase() == replacementCsvMetaMarker;

bool _isHeader(List<String> fields) =>
    fields.first.trim().toLowerCase() == 'triggers';

({ReplacementCsvMeta? meta, ReplacementCsvRefusal? refusal}) _parseMeta(
  List<String> fields,
) {
  final values = <String, String>{};
  for (final field in fields.skip(1)) {
    final eq = field.indexOf('=');
    if (eq <= 0) continue;
    values[field.substring(0, eq).trim().toLowerCase()] = field
        .substring(eq + 1)
        .trim();
  }
  if (values['format'] != '$replacementCsvFormatVersion') {
    return (meta: null, refusal: ReplacementCsvRefusal.unsupportedFormat);
  }
  final type = values['type'] ?? replacementCsvPackageType;
  if (type != replacementCsvPackageType) {
    return (meta: null, refusal: ReplacementCsvRefusal.unsupportedType);
  }
  final name = values['name'] == null
      ? ''
      : sanitizeReplacementPackageName(values['name']!);
  return (
    meta: ReplacementCsvMeta(
      name: name.isEmpty ? null : name,
      created: _parseIsoDate(values['created']),
    ),
    refusal: null,
  );
}

/// Accepts only `JJJJ-MM-TT` that names a real calendar day.
DateTime? _parseIsoDate(String? value) {
  if (value == null || !_isoDatePattern.hasMatch(value)) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _isoDate(parsed) != value) return null;
  return parsed;
}

final _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// The field separator: `;` when the first line is the metadata record or a
/// header written with `;` (German Excel), otherwise `,`.
String _delimiterFor(String text) {
  final firstLine = text.split(RegExp(r'[\r\n]')).first.trim().toLowerCase();
  if (firstLine.startsWith('$replacementCsvMetaMarker;') ||
      firstLine.startsWith('triggers;')) {
    return ';';
  }
  return ',';
}

// ---------------------------------------------------------------------------
// Row validation
// ---------------------------------------------------------------------------

/// Tab, CR and LF are allowed: a quoted field may span lines, and an entry
/// that holds a real line break (stored by an older version or an import)
/// must survive an export and re-import. Other C0 controls, DEL, C1 controls,
/// and the bidi embedding and isolate controls are rejected: they hide or
/// reorder text on screen.
final _forbiddenCharacters = RegExp(
  r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u202A-\u202E\u2066-\u2069]',
);

(ReplacementCsvRow?, ReplacementCsvErrorReason?) _rowFromRecord(
  List<String> fields,
) {
  if (fields.length < 2) {
    return (null, ReplacementCsvErrorReason.missingFields);
  }
  if (fields.any(_forbiddenCharacters.hasMatch)) {
    return (null, ReplacementCsvErrorReason.controlCharacter);
  }

  final triggers = _splitTriggers(
    _restoreFormula(fields[0]),
  ).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  if (triggers.isEmpty) {
    return (null, ReplacementCsvErrorReason.emptyTrigger);
  }
  if (triggers.length > replacementCsvMaxTriggersPerRow) {
    return (null, ReplacementCsvErrorReason.tooManyTriggers);
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
List<_CsvRecord> _readRecords(String text, String delimiter) {
  final scan = _CsvScan(text, delimiter);
  for (var i = 0; i < text.length; i++) {
    i = scan.inQuotes ? scan.readQuoted(i) : scan.readUnquoted(i);
  }
  scan.finish();
  return scan.records;
}

/// State of one pass over the CSV text. The methods are the two modes of the
/// reader: inside a quoted field and outside one.
class _CsvScan {
  _CsvScan(this._text, this._delimiter);

  final String _text;
  final String _delimiter;
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
    } else if (c == _delimiter) {
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

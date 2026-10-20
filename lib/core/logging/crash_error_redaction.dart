/// Makes an error object safe to hand to Sentry.
///
/// Sentry takes the exception value from `error.toString()`. drift's
/// `SqliteException.toString()` appends the statement and its bound
/// parameters, and those parameters are user content (transcript and note
/// text in history writes). Only the result code, message and operation are
/// kept; the statement and parameters are dropped.
library;

import 'dart:io' show FileSystemException;

import 'package:drift/native.dart' show SqliteException;
import 'package:path/path.dart' as p;

import 'user_path_scrubber.dart';

/// Returns the form of [error] that may leave the device or be written to
/// the log. Other exception types with user content in their toString() are
/// reduced here as well:
/// - [FormatException] renders its source text, which can be a document the
///   user imported. Only the message and offset are kept.
/// - [RangeError] is an [ArgumentError] and keeps its type. An int value is
///   kept, any other value becomes `<redacted>`.
/// - [ArgumentError] renders the invalid value. The message is kept, with
///   its paths redacted (see [redactPathsInText]).
/// - [FileSystemException] renders the full local path, which contains the
///   account name and the file name. Only the extension is kept.
/// - Any other error whose text holds a path is redacted the same way.
Object redactForCrashReport(Object error) {
  if (error is SqliteException) {
    return SqliteException(
      extendedResultCode: error.extendedResultCode,
      message: redactPathsInText(error.message),
      explanation: error.explanation,
      operation: error.operation,
      offset: error.offset,
    );
  }
  if (error is FormatException) {
    return FormatException(
      redactPathsInText(error.message),
      null,
      error.offset,
    );
  }
  if (error is RangeError) {
    final value = error.invalidValue;
    final shown = value is int ? '$value' : '<redacted>';
    final name = error.name;
    final where = name == null ? '' : ' ($name)';
    final bounds = error.start == null
        ? ''
        : ' range ${error.start}..${error.end ?? error.start}';
    final message = redactPathsInText(error.message.toString());
    return RangeError('Invalid value$where$bounds: $shown; $message');
  }
  if (error is ArgumentError) {
    final message = error.message;
    return ArgumentError(
      message is String ? redactPathsInText(message) : message,
    );
  }
  if (error is FileSystemException) {
    final path = error.path;
    final extension = path == null ? '' : _safeExtension(p.basename(path));
    return FileSystemException(
      redactPathsInText(error.message),
      extension.isEmpty ? null : extension,
      error.osError,
    );
  }
  final text = error.toString();
  final redacted = redactPathsInText(text);
  return redacted == text ? error : _RedactedError(redacted);
}

/// Extension of [fileName] with its dot (`.wav`), kept only when it is plain
/// ASCII of at most eight characters. Anything else, such as the second part
/// of "Max.Mustermann", becomes `.<ext>`. Empty when there is no extension.
String _safeExtension(String fileName) {
  final ext = p.extension(fileName);
  if (ext.isEmpty) return '';
  return _plainExtension.hasMatch(ext.substring(1)) ? ext : '.<ext>';
}

final _plainExtension = RegExp(r'^[A-Za-z0-9]{1,8}$');

/// Text for a crash report: the account name and home directories first, then
/// every path (see [shortenFileNamesInText]).
///
/// Percent-encoded separators (`%2F`, `%5C`, `%7E`, also encoded again as
/// `%252F`) would hide a path from the scanner, so a decoded copy is
/// redacted as well. Decoding repeats until the text is stable, at most
/// [_maxDecodeRounds] times. When that copy holds a path, the redacted copy
/// is returned.
String redactPathsInText(String text) {
  final redacted = _redactPlainPaths(text);
  if (!_encodedSeparator.hasMatch(text)) return redacted;
  var decoded = text;
  for (var round = 0; round < _maxDecodeRounds; round++) {
    final next = decoded.replaceAllMapped(
      _encodedSeparator,
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
    if (next == decoded) break;
    decoded = next;
  }
  final redactedDecoded = _redactPlainPaths(decoded);
  return redactedDecoded == decoded ? redacted : redactedDecoded;
}

const _maxDecodeRounds = 8;

/// The encoded separators plus `%25`, the encoded percent sign of a second
/// encoding round.
final _encodedSeparator = RegExp(r'%(2[Ff]|5[Cc]|7[Ee]|25)');

String _redactPlainPaths(String text) =>
    shortenFileNamesInText(scrubUserPaths(text));

/// Returns a copy of [values] with [redactPathsInText] applied to every
/// String leaf, recursing into nested maps and lists. Keys and non-string
/// values are kept as they are.
Map<String, dynamic> redactPathsInMap(Map<String, dynamic> values) => {
  for (final entry in values.entries) entry.key: _redactValue(entry.value),
};

Object? _redactValue(Object? value) => switch (value) {
  String() => redactPathsInText(value),
  Map() => redactPathsInMap(value.cast<String, dynamic>()),
  List() => [for (final item in value) _redactValue(item)],
  _ => value,
};

/// Longest path token that is shortened piecewise. A longer token becomes
/// `<long>` as a whole.
const _maxPathTokenLength = 512;

/// Characters that end a path: double quote, backtick, pipe, tab and line
/// breaks. Brackets, commas, apostrophes and angle brackets do not, since
/// file names can hold them ("O'Brien", "Notes (old)", "a, b").
const _pathTerminators = {0x22, 0x60, 0x7C, 0x0A, 0x0D, 0x09};

/// Characters a path can be wrapped in or followed by. They are trimmed from
/// the end of the last word before its extension is read.
const _closers = {
  0x27, // '
  0x22, // "
  0x29, // )
  0x5D, // ]
  0x7D, // }
  0x3E, // >
  0x2E, // .
  0x2C, // ,
  0x3B, // ;
  0x3A, // :
  0x21, // !
  0x3F, // ?
};

/// Extensions that make a token a path even when it starts inside a word,
/// as in "Max/Mustermann/Bericht.wav". Source files such as ".dart" are not
/// listed, so "package:whispaste/app.dart" stays readable.
const _knownExtensions = {
  'wav', 'mp3', 'm4a', 'flac', 'ogg', 'opus', 'aac', 'aif', 'aiff', 'wma', //
  'mp4', 'mov', 'mkv', 'webm', 'avi', //
  'txt', 'md', 'pdf', 'doc', 'docx', 'odt', 'rtf', 'csv', 'json', 'xml',
  'html', 'htm', 'pages', //
  'db', 'sqlite', 'sqlite3', 'bin', 'gguf', 'onnx', 'log', //
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic',
};

/// Web URL schemes that are left alone: they name servers, not local files.
/// `file://` is not among them, so a local file URL is still redacted.
const _webSchemes = ['http://', 'https://', 'ws://', 'wss://'];

bool _isSeparatorUnit(int c) => c == 0x2F || c == 0x5C; // "/" and "\"

bool _isSpaceUnit(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool _isWordUnit(int c) =>
    c == 0x5F ||
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A);

/// Characters before which a word starts: whitespace and opening quotes or
/// brackets. A path that starts inside a word is cut back to there.
bool _isWordBreak(int c) =>
    _isSpaceUnit(c) ||
    c == 0x22 ||
    c == 0x27 ||
    c == 0x60 ||
    c == 0x28 ||
    c == 0x5B ||
    c == 0x7B ||
    c == 0x3C;

/// Whether a path token starts at [i]. A separator starts one unless a space
/// follows it. A drive (`C:\`) or home (`~/`, `~anna/`) prefix starts one
/// too. A separator right after a word character is handled by the caller:
/// "1/2" and "and/or" stay, "Max/Bericht.wav" does not.
bool _startsPathAt(String text, int i) {
  if (i > 0 && _isWordUnit(text.codeUnitAt(i - 1))) return false;
  final c = text.codeUnitAt(i);
  final next = i + 1 < text.length ? text.codeUnitAt(i + 1) : -1;
  if (_isSeparatorUnit(c)) return next != -1 && next != 0x20;
  if (c == 0x7E) {
    // "~" or "~anna", then a separator. The name scan stops at the first
    // character that is not part of a name, so it stays linear.
    var j = i + 1;
    while (j < text.length) {
      final u = text.codeUnitAt(j);
      if (!_isWordUnit(u) && u != 0x2E && u != 0x2D) break;
      j++;
    }
    return j < text.length && _isSeparatorUnit(text.codeUnitAt(j));
  }
  final isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  if (isLetter && next == 0x3A && i + 2 < text.length) {
    return _isSeparatorUnit(text.codeUnitAt(i + 2)); // "C:"
  }
  return false;
}

/// End of a web URL that starts at [i], or null when none starts there.
int? _webUrlEnd(String text, int i) {
  if (i > 0 && _isWordUnit(text.codeUnitAt(i - 1))) return null;
  final c = text.codeUnitAt(i) | 0x20; // lower case for ASCII letters
  if (c != 0x68 && c != 0x77) return null; // "h" or "w"
  final head = text
      .substring(i, i + 8 > text.length ? text.length : i + 8)
      .toLowerCase();
  if (!_webSchemes.any(head.startsWith)) return null;
  var j = i;
  while (j < text.length) {
    final u = text.codeUnitAt(j);
    if (_isSpaceUnit(u) || _pathTerminators.contains(u)) break;
    j++;
  }
  return j;
}

/// Whether [c] at [j] marks a path: a separator, or a dot followed by a
/// letter or digit. A sentence-ending dot ("lesen.") is no mark.
bool _isPathMark(String text, int j, int c) =>
    _isSeparatorUnit(c) ||
    (c == 0x2E && j + 1 < text.length && _isWordUnit(text.codeUnitAt(j + 1)));

/// The text from a path start to the next terminator, read once.
///
/// The path ends after the word that holds its last path mark, if the last
/// segment there has a valid extension: "/a/b.wav nicht" ends after
/// "b.wav", "/a/Interview 2026.05 Anna.wav" stays whole, and a closing quote
/// or bracket after the extension stays outside. Otherwise the path runs to
/// the terminator. A path without an extension can so take the rest of a
/// sentence (`Datei in <path>`); that is accepted, privacy comes before
/// diagnosis.
///
/// Nothing here depends on where in the region the path starts: every start
/// lies at or before the last separator. So one region serves every start
/// inside it, and the whole scan stays linear.
class _PathRegion {
  factory _PathRegion.scan(String text, int from) {
    var lastMark = from;
    var lastSeparator = from - 1;
    var j = from;
    while (j < text.length) {
      final c = text.codeUnitAt(j);
      if (_pathTerminators.contains(c)) break;
      if (_isPathMark(text, j, c)) {
        lastMark = j;
        if (_isSeparatorUnit(c)) lastSeparator = j;
      }
      j++;
    }
    final terminator = j;
    var wordEnd = lastMark;
    while (wordEnd < terminator && text.codeUnitAt(wordEnd) != 0x20) {
      wordEnd++;
    }
    while (wordEnd - 1 > lastMark &&
        _closers.contains(text.codeUnitAt(wordEnd - 1))) {
      wordEnd--;
    }
    var dot = -1;
    for (var k = wordEnd - 1; k > lastSeparator; k--) {
      if (text.codeUnitAt(k) == 0x2E) {
        dot = k;
        break;
      }
    }
    final hasExtension =
        dot > lastSeparator + 1 &&
        wordEnd - dot - 1 <= 8 &&
        _plainExtension.hasMatch(text.substring(dot + 1, wordEnd));
    return _PathRegion._(
      terminator,
      hasExtension ? wordEnd : terminator,
      hasExtension ? text.substring(dot, wordEnd) : null,
    );
  }

  _PathRegion._(this.terminator, this.end, this.extension);

  /// Index of the terminator (or the text length).
  final int terminator;

  /// End (exclusive) of the path in this region.
  final int end;

  /// The extension with its dot (`.wav`), or null.
  final String? extension;

  bool get hasKnownExtension {
    final ext = extension;
    return ext != null &&
        _knownExtensions.contains(ext.substring(1).toLowerCase());
  }

  /// The replacement for the path from [start] to [end].
  String replacementFrom(int start) {
    if (end - start > _maxPathTokenLength) return '<long>';
    final ext = extension;
    return ext == null ? '<path>' : '<file>$ext';
  }
}

/// Replaces every path in [text] (see [_PathRegion]): `<file>.<ext>` when it
/// has a valid extension (DEV-235), `<path>` otherwise, `<long>` beyond 512
/// characters. A path that starts inside a word ("Max/Bericht.wav") counts
/// when it ends in a known media or document extension; it is then replaced
/// back to the start of that word. Web URLs stay as they are. Text without a
/// path is returned unchanged. The scan is linear.
String shortenFileNamesInText(String text) {
  final out = StringBuffer();
  var copied = 0;
  var changed = false;
  var wordStart = 0;
  _PathRegion? region;
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (_isWordBreak(c)) {
      wordStart = i + 1;
      i++;
      continue;
    }
    final urlEnd = _webUrlEnd(text, i);
    if (urlEnd != null) {
      i = urlEnd;
      continue;
    }
    var start = -1;
    if (_startsPathAt(text, i)) {
      start = i;
    } else if (_isSeparatorUnit(c) && i > 0) {
      if (region == null || i >= region.terminator) {
        region = _PathRegion.scan(text, i);
      }
      if (region.hasKnownExtension) {
        start = wordStart > copied ? wordStart : copied;
      }
    }
    if (start < 0) {
      i++;
      continue;
    }
    if (region == null || i >= region.terminator) {
      region = _PathRegion.scan(text, i);
    }
    out
      ..write(text.substring(copied, start))
      ..write(region.replacementFrom(start));
    copied = region.end;
    changed = true;
    i = region.end;
  }
  if (!changed) return text;
  return (out..write(text.substring(copied))).toString();
}

/// Stands in for an error whose text was redacted. Keeps the text only.
class _RedactedError implements Exception {
  const _RedactedError(this.text);

  final String text;

  @override
  String toString() => text;
}

/// Removes SqliteException bound parameters from text that already holds a
/// rendered exception, e.g. a log line built with `'$e'`.
///
/// Text that carries no SqliteException rendering ("Causing statement") is
/// returned unchanged. For a rendered one, everything from `, parameters: `
/// to the end of the text is replaced: parameters are written unescaped and
/// may span lines, so cutting at the first newline would leak transcript
/// text. The statement itself has no values (drift binds them as `?`).
String redactSqliteParametersInText(String text) {
  if (!text.contains('Causing statement')) return text;
  return text.replaceFirst(
    RegExp(r', parameters: [\s\S]*$'),
    ', parameters: <redacted>',
  );
}

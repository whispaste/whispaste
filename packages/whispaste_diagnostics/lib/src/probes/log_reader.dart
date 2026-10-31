/// Full and rotated log reader — path-sanitized.
///
/// Reads the primary log file and any rotated siblings (e.g.
/// `whispaste.log.1`, `whispaste.log.2`), concatenates them in
/// chronological order (oldest first), and applies the privacy sanitizer
/// to every line before returning.
///
/// Pure-Dart (no Flutter). Injectable [FileReader] seam for unit tests.
library;

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../privacy/sanitizer.dart';
import 'path_service.dart';

// ---------------------------------------------------------------------------
// Injectable seam
// ---------------------------------------------------------------------------

/// Reads the content of [path] as a list of lines, or returns null on error.
typedef FileReader = List<String>? Function(String path);

List<String>? _defaultFileReader(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    return f.readAsLinesSync();
  } on FileSystemException {
    return null;
  }
}

FileReader _fileReader = _defaultFileReader;

/// Overrides the file reader for tests.
@visibleForTesting
void setLogFileReaderForTesting(FileReader? reader) {
  _fileReader = reader ?? _defaultFileReader;
}

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// Result of reading the full + rotated log.
class LogReaderResult {
  const LogReaderResult({
    required this.primaryPath,
    required this.rotatedPaths,
    required this.lines,
    required this.totalLines,
  });

  /// Path to the primary log file (may not exist).
  final String primaryPath;

  /// Paths to any rotated log files that were read.
  final List<String> rotatedPaths;

  /// All log lines (sanitized), oldest first.
  final List<String> lines;

  /// Total number of lines across all files.
  final int totalLines;
}

// ---------------------------------------------------------------------------
// Pure helpers (exported for tests)
// ---------------------------------------------------------------------------

/// Sanitizes a single log line: strips paths and returns null when the line
/// contains sensitive data (the line is then omitted from the output).
@visibleForTesting
String? sanitizeLogLine(String line) {
  if (containsSensitiveData(line)) return null;
  return sanitizePaths(line);
}

/// Builds the list of rotated log paths to probe for a given [primaryPath].
///
/// Checks `<primary>.1` … `<primary>.<maxRotations>` (inclusive).
@visibleForTesting
List<String> rotatedLogPaths(String primaryPath, {int maxRotations = 5}) {
  return [for (var i = 1; i <= maxRotations; i++) '$primaryPath.$i'];
}

// ---------------------------------------------------------------------------
// Reader
// ---------------------------------------------------------------------------

/// Reads the full primary log and any rotated siblings, sanitizes all lines,
/// and returns a [LogReaderResult].
///
/// [logFilePath] — explicit path to the primary log file; when null, defaults
/// to the conventional WhisPaste log location.
/// [maxRotations] — how many rotated files to probe (`.1` … `.maxRotations`).
/// [fileReader] — injectable for tests; defaults to the real file system.
LogReaderResult readFullLog({
  String? logFilePath,
  int maxRotations = 5,
  FileReader? fileReader,
}) {
  final reader = fileReader ?? _fileReader;
  final primaryPath =
      logFilePath ?? p.join(appDataDir(), 'logs', 'whispaste.log');

  final rotated = rotatedLogPaths(primaryPath, maxRotations: maxRotations);

  // Read rotated files first (oldest), then the primary (newest).
  final allLines = <String>[];
  final readRotated = <String>[];

  for (final rotPath in rotated.reversed) {
    final lines = reader(rotPath);
    if (lines != null) {
      readRotated.add(rotPath);
      for (final line in lines) {
        final sanitized = sanitizeLogLine(line);
        if (sanitized != null) allLines.add(sanitized);
      }
    }
  }

  final primaryLines = reader(primaryPath);
  if (primaryLines != null) {
    for (final line in primaryLines) {
      final sanitized = sanitizeLogLine(line);
      if (sanitized != null) allLines.add(sanitized);
    }
  }

  return LogReaderResult(
    primaryPath: primaryPath,
    rotatedPaths: readRotated,
    lines: allLines,
    totalLines: allLines.length,
  );
}

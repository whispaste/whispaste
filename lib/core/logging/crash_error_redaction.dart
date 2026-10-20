/// Makes an error object safe to hand to Sentry.
///
/// Sentry takes the exception value from `error.toString()`. drift's
/// `SqliteException.toString()` appends the statement and its bound
/// parameters, and those parameters are user content (transcript and note
/// text in history writes). Only the result code, message and operation are
/// kept; the statement and parameters are dropped.
library;

import 'package:drift/native.dart' show SqliteException;

Object redactForCrashReport(Object error) {
  if (error is! SqliteException) return error;
  return SqliteException(
    extendedResultCode: error.extendedResultCode,
    message: error.message,
    explanation: error.explanation,
    operation: error.operation,
    offset: error.offset,
  );
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

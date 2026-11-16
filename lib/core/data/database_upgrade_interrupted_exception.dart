/// Thrown when a schema upgrade of the history database stopped on a
/// transient SQLite error (see HistoryDatabase.migration).
library;

import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// SQLite primary result codes that describe the file's surroundings, not its
/// content: BUSY, LOCKED, NOMEM, IOERR, FULL and CANTOPEN. The same upgrade
/// can succeed on a later attempt.
const Set<int> _transientResultCodes = {5, 6, 7, 10, 13, 14};

/// Whether [error] is a SQLite failure that a later attempt may not repeat.
/// Upgrade steps that tolerate data-dependent failures rethrow these.
bool isTransientSqliteFailure(Object error) =>
    error is SqliteException &&
    _transientResultCodes.contains(error.resultCode);

/// The upgrade was rolled back: the file keeps its old version, its old schema
/// and all its data. Retrying the open runs the upgrade again.
class DatabaseUpgradeInterruptedException implements Exception {
  const DatabaseUpgradeInterruptedException(this.cause);

  final SqliteException cause;

  @override
  String toString() =>
      'DatabaseUpgradeInterruptedException: the database upgrade stopped on '
      'SQLite code ${cause.extendedResultCode} and was rolled back.';
}

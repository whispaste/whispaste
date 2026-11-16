/// Checks that a copy of a SQLite file is complete: shared by the nested-path
/// move, the history backups (#562) and the encryption step (#1020).
library;

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// Opens the SQLite file at [path]. With [hexKey] (64 hex digits, the data
/// key of #1019) the connection is unlocked first: the history database is
/// encrypted at rest with SQLite3 Multiple Ciphers (#1020). A wrong key, or
/// none for an encrypted file, fails on the first statement with
/// "file is not a database".
Database openSqlite(
  String path, {
  OpenMode mode = OpenMode.readWriteCreate,
  String? hexKey,
}) {
  final db = sqlite3.open(path, mode: mode);
  if (hexKey != null) {
    try {
      applySqliteHexKey(db, hexKey);
    } catch (_) {
      db.close();
      rethrow;
    }
  }
  return db;
}

/// Unlocks [db] with [hexKey]; must run before any other statement.
void applySqliteHexKey(Database db, String hexKey) {
  if (!_hexKeyPattern.hasMatch(hexKey)) {
    throw ArgumentError('the database key must be 64 hex digits');
  }
  db.execute("PRAGMA hexkey = '$hexKey'");
}

final _hexKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// Throws unless [copy] passes `integrity_check` and holds as many rows per
/// user table as [source]. [sourceHexKey] and [copyHexKey] unlock an
/// encrypted side, see [openSqlite].
void verifySqliteCopy(
  String source,
  String copy, {
  String? sourceHexKey,
  String? copyHexKey,
}) {
  final src = openSqlite(source, mode: OpenMode.readOnly, hexKey: sourceHexKey);
  final Database dst;
  try {
    dst = openSqlite(copy, mode: OpenMode.readOnly, hexKey: copyHexKey);
  } catch (_) {
    src.close();
    rethrow;
  }
  try {
    final check = dst.select('PRAGMA integrity_check').single.columnAt(0);
    if (check != 'ok') throw StateError('integrity_check failed: $check');
    if (!mapEquals(sqliteRowCounts(src), sqliteRowCounts(dst))) {
      throw StateError('row counts differ between source and copy');
    }
  } finally {
    dst.close();
    src.close();
  }
}

/// Row count per user table; virtual (FTS) tables are left out because their
/// shadow tables are counted.
Map<String, int> sqliteRowCounts(Database db) {
  final counts = <String, int>{};
  final tables = db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND substr(name, 1, 7) <> 'sqlite_' "
    "AND sql NOT LIKE 'CREATE VIRTUAL%'",
  );
  for (final row in tables) {
    final name = row.columnAt(0) as String;
    final quoted = '"${name.replaceAll('"', '""')}"';
    counts[name] =
        db.select('SELECT COUNT(*) FROM $quoted').single.columnAt(0) as int;
  }
  return counts;
}

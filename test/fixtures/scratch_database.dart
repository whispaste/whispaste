import 'dart:io';

import 'package:drift/native.dart';

/// A real SQLite file for migration tests that close and reopen it, without
/// the per-commit file work (#1676).
///
/// Creating the schema on a fresh file runs dozens of statements outside a
/// transaction. With the defaults, each one creates a rollback journal file,
/// flushes it and the database to disk, and deletes it again. On the Windows
/// lab that took 1 to 4 s per test, and over 10 s when another job loaded the
/// same disk. These tests check the upgrade steps and the data they keep
/// across a close and a reopen, not crash safety, so:
/// - `synchronous = OFF`: commits are not flushed; the data still reaches the
///   file before the next open in the same process.
/// - `journal_mode = MEMORY`: the rollback journal stays in memory, so
///   transactions and their rollback still work, but no journal file is
///   created or deleted per commit. The mode is per connection and leaves
///   the file header unchanged.
///
/// Tests about WAL, the journal, fault injection or safety copies keep the
/// plain `NativeDatabase(file)`.
NativeDatabase scratchFileDatabase(File file) => NativeDatabase(
  file,
  setup: (db) {
    db.execute('PRAGMA synchronous = OFF');
    db.execute('PRAGMA journal_mode = MEMORY');
  },
);

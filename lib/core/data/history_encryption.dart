/// Encryption of the history database at rest (#1020).
///
/// The history (entries, dictionary, snippets, notes, settings) lives in one
/// SQLite file. package:sqlite3 is built with SQLite3 Multiple Ciphers
/// (`hooks: user_defines` in pubspec.yaml), which encrypts every page with
/// the data key of #1019 (ChaCha20, the library default). Without a key the
/// library behaves like plain SQLite, so a file written before this change
/// still opens and is converted once by [encryptHistoryDatabase].
///
/// The conversion never touches the original until a verified encrypted copy
/// exists: it writes a plain copy to a staging file (`VACUUM INTO`), encrypts
/// that copy (`PRAGMA hexrekey`), checks it against the original
/// (`integrity_check` plus row counts, opened with the key) and only then
/// renames it over `history.db` in one step. A failure or an interrupted run
/// leaves the plaintext original in use; the staging file is removed and the
/// next start tries again. The caller takes a verified backup through the
/// #562 path first ([backupBeforeRiskyStep]), so there is a way back even
/// if the renamed file later turned out unusable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../logging/app_logger.dart';
import 'sqlite_copy_check.dart';

final _log = AppLogger('HistoryEncryption');

/// Staging file next to `history.db` while it is converted.
String historyEncryptionStagingPath(String databasePath) =>
    '$databasePath.encrypting';

/// The data key as the 64 hex digits that `PRAGMA hexkey` takes.
String sqliteHexKey(List<int> key) {
  if (key.length != 32) {
    throw ArgumentError('the data key must be 32 bytes');
  }
  final buffer = StringBuffer();
  for (final b in key) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

final _plainHeader = ascii.encode('SQLite format 3\u0000');

/// Whether [path] is an unencrypted SQLite file. A plain file starts with
/// the fixed SQLite header; an encrypted one starts with random bytes. An
/// empty file counts as plain (SQLite writes the header on first use).
bool isPlainSqliteFile(String path) {
  final file = File(path);
  final RandomAccessFile handle;
  try {
    handle = file.openSync();
  } on FileSystemException {
    return false;
  }
  try {
    final length = handle.lengthSync();
    if (length == 0) return true;
    if (length < _plainHeader.length) return false;
    final head = handle.readSync(_plainHeader.length);
    return listEquals(head, _plainHeader);
  } finally {
    handle.closeSync();
  }
}

/// Outcome of [encryptHistoryDatabase].
enum HistoryEncryptionResult {
  /// The file was already encrypted, or there is no file.
  notNeeded,

  /// The file was converted; the encrypted file is in place.
  encrypted,

  /// The conversion did not complete; the plain original is still in use.
  failed,
}

/// The steps of [encryptHistoryDatabase], injectable so tests can fail any
/// one of them. The defaults are the real operations.
@visibleForTesting
class HistoryEncryptionOps {
  const HistoryEncryptionOps({
    this.writeEncryptedCopy = _writeEncryptedCopy,
    this.verifyCopy = _verifyEncryptedCopy,
    this.swapIn = _swapIn,
  });

  /// Writes [source] encrypted with [hexKey] to [staging].
  final void Function(String source, String staging, String hexKey)
  writeEncryptedCopy;

  /// Throws unless [staging] opens with [hexKey] and equals [source].
  final void Function(String source, String staging, String hexKey) verifyCopy;

  /// Moves [from] over [to] in one step.
  final void Function(String from, String to) swapIn;
}

/// Result of [encryptHistoryDatabase] with the error that kept the original.
class HistoryEncryption {
  const HistoryEncryption(this.result, {this.error});

  final HistoryEncryptionResult result;

  /// The error kind of a failed run (no message: it may hold a path).
  final String? error;
}

/// Converts the plain history database at [path] into one encrypted with
/// [hexKey]. Never throws. Must run while no connection to [path] is open
/// (before drift opens the file); blocks, so callers run it in an isolate.
///
/// A file with a rollback journal or WAL next to it is left for this start:
/// its last transaction is only complete once SQLite has opened it, and a
/// stale journal next to the swapped-in file would corrupt it.
HistoryEncryption encryptHistoryDatabase(
  String path,
  String hexKey, {
  @visibleForTesting HistoryEncryptionOps ops = const HistoryEncryptionOps(),
}) {
  final staging = historyEncryptionStagingPath(path);
  removeHistoryEncryptionLeftovers(path);
  if (!File(path).existsSync() || !isPlainSqliteFile(path)) {
    return const HistoryEncryption(HistoryEncryptionResult.notNeeded);
  }
  for (final side in ['-journal', '-wal']) {
    if (File('$path$side').existsSync()) {
      return HistoryEncryption(
        HistoryEncryptionResult.failed,
        error: 'pending$side',
      );
    }
  }
  try {
    ops.writeEncryptedCopy(path, staging, hexKey);
    ops.verifyCopy(path, staging, hexKey);
    ops.swapIn(staging, path);
    return const HistoryEncryption(HistoryEncryptionResult.encrypted);
  } catch (e) {
    removeHistoryEncryptionLeftovers(path);
    return HistoryEncryption(
      HistoryEncryptionResult.failed,
      error: e.runtimeType.toString(),
    );
  }
}

/// Removes the staging file of an interrupted [encryptHistoryDatabase].
/// Never throws.
void removeHistoryEncryptionLeftovers(String path) {
  final staging = historyEncryptionStagingPath(path);
  for (final f in [staging, '$staging-journal', '$staging-wal']) {
    try {
      final file = File(f);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException catch (e) {
      // Retried on the next start.
      _log.debug('Encryption leftover not removed yet', e);
    }
  }
}

void _writeEncryptedCopy(String source, String staging, String hexKey) {
  final src = sqlite3.open(source, mode: OpenMode.readOnly);
  try {
    final quoted = staging.replaceAll("'", "''");
    src.execute("VACUUM INTO '$quoted'");
  } finally {
    src.close();
  }
  final dst = sqlite3.open(staging, mode: OpenMode.readWrite);
  try {
    // rekey works in rollback-journal mode only; drift's default is DELETE,
    // an old WAL file is switched back first.
    dst.execute('PRAGMA journal_mode = DELETE');
    if (!_hexKeyPattern.hasMatch(hexKey)) {
      throw ArgumentError('the database key must be 64 hex digits');
    }
    dst.execute("PRAGMA hexrekey = '$hexKey'");
  } finally {
    dst.close();
  }
}

final _hexKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

void _verifyEncryptedCopy(String source, String staging, String hexKey) {
  if (isPlainSqliteFile(staging)) {
    throw StateError('the copy is not encrypted');
  }
  verifySqliteCopy(source, staging, copyHexKey: hexKey);
}

void _swapIn(String from, String to) {
  File(from).renameSync(to);
}

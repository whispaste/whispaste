/// Verified backups of the history database around risky steps (#562).
///
/// A copy is taken only right before a schema upgrade and before the move
/// out of the old nested Windows folder, never on an ordinary start:
/// deleted entries must not live on in day-old copies (north star, privacy is
/// a hard limit). The copies sit in `<app data>/history-backups/`.
///
/// Every copy is written with `VACUUM INTO` to a temporary file, checked
/// (`integrity_check` plus a row count per table against the source) and only
/// then renamed to its final name. An interrupted run leaves at most a
/// `*.tmp` file, which the next run removes; a copy with a final name is
/// always complete.
///
/// The copies go once the database has opened cleanly at
/// [HistoryBackupPolicy.cleanOpens] starts after the last copy, at the latest
/// after [HistoryBackupPolicy.maxAge]. The factory reset, the forgot-PIN wipe
/// and "delete all recordings" remove the folder at once
/// ([eraseHistoryBackups]); a folder that resists is retried at the next
/// start through its own marker ([retryPendingBackupErase]).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../logging/app_logger.dart';
import 'sqlite_copy_check.dart';

final _log = AppLogger('HistoryBackups');

/// Folder name below the app data folder.
const String historyBackupDirName = 'history-backups';

/// File next to the folder that asks the next start to remove it again.
const String historyBackupErasePendingName = 'history-backups.erase-pending';

const String _cleanOpensName = 'clean-opens';
const String _prefix = 'history-';
const String _suffix = '.db';
const String _tmpSuffix = '.tmp';

/// How many copies stay, how much space they take and when they go.
@immutable
class HistoryBackupPolicy {
  const HistoryBackupPolicy({
    this.keep = 3,
    this.maxTotalBytes = 512 * 1024 * 1024,
    this.cleanOpens = 3,
    this.maxAge = const Duration(days: 7),
  });

  /// Upper bound for the number of copies.
  final int keep;

  /// Upper bound for all copies together. The oldest go first; the newest
  /// one always stays, even if it alone exceeds the bound.
  final int maxTotalBytes;

  /// Clean opens after the newest copy that make every copy unnecessary.
  final int cleanOpens;

  /// Copies older than this go regardless of the open count.
  final Duration maxAge;
}

/// Outcome of [writeHistoryBackup], for the log and for tests.
enum HistoryBackupResult {
  /// The source file does not exist.
  noDatabase,

  /// A new verified copy was written.
  created,

  /// Writing or verifying the copy failed; nothing with a final name was
  /// added and the existing copies are untouched.
  failed,
}

/// [HistoryBackupResult] plus the failure text, sendable across isolates.
@immutable
class HistoryBackupOutcome {
  const HistoryBackupOutcome(
    this.result, [
    this.error,
    this.cleanupProblems = const [],
  ]);

  final HistoryBackupResult result;

  /// Kind of the error of a failed copy ([errorKind]: type plus code), null
  /// otherwise. Never the error text or a stack trace: both can carry the
  /// backup folder and with it the user name, and the caller logs this line,
  /// which also becomes a crash-report breadcrumb (#742).
  final String? error;

  /// File names (never paths or OS error text) of the old copies the thinning
  /// could not delete. The copy itself is fine; the caller logs them because
  /// the isolate has no log sinks (#602).
  final List<String> cleanupProblems;
}

/// The backup folder for [appDataDir].
String historyBackupDir(String appDataDir) =>
    p.join(appDataDir, historyBackupDirName);

/// `user_version` of the database at [path], or null when it cannot be read.
/// Cheap: no copy, read-only. [hexKey] unlocks an encrypted file (#1020).
int? storedSchemaVersion(String path, {String? hexKey}) {
  if (!File(path).existsSync()) return null;
  try {
    final db = openSqlite(path, mode: OpenMode.readOnly, hexKey: hexKey);
    try {
      return db.select('PRAGMA user_version').single.columnAt(0) as int;
    } finally {
      db.close();
    }
  } catch (e, st) {
    _log.warning('Could not read the history schema version', e, st);
    return null;
  }
}

/// True when the database at [path] will be upgraded by this build, i.e. a
/// copy is due before it opens.
bool historyUpgradePending(String path, int schemaVersion, {String? hexKey}) {
  final stored = storedSchemaVersion(path, hexKey: hexKey);
  return stored != null && stored > 0 && stored < schemaVersion;
}

/// Writes a new verified copy of [source] and prunes the folder to [policy].
/// Never throws: a copy that cannot be written must not keep the app from
/// starting. Must run while no other connection writes to [source].
/// Runs in a background isolate, where the log sinks are absent: a failure
/// is returned as [HistoryBackupOutcome.error] for the caller to log.
///
/// [hexKey] unlocks an encrypted [source] (#1020). `VACUUM INTO` then writes
/// the copy with the same key, so a backup of the encrypted database is
/// encrypted too; the check opens it with that key.
Future<HistoryBackupOutcome> writeHistoryBackup(
  String appDataDir, {
  required String source,
  required DateTime now,
  String? hexKey,
  HistoryBackupPolicy policy = const HistoryBackupPolicy(),
  @visibleForTesting void Function(String path) deleteFile = _deleteFile,
}) async {
  if (!File(source).existsSync()) {
    return const HistoryBackupOutcome(HistoryBackupResult.noDatabase);
  }
  final dir = Directory(historyBackupDir(appDataDir));
  try {
    dir.createSync(recursive: true);
    final leftovers = <String>[];
    _removeLeftoverTemps(dir, deleteFile, leftovers);
    final finalPath = p.join(dir.path, '$_prefix${_formatStamp(now)}$_suffix');
    final tmpPath = '$finalPath$_tmpSuffix';
    try {
      _writeVerifiedCopy(source, tmpPath, hexKey);
      File(tmpPath).renameSync(finalPath);
    } catch (e) {
      _deleteQuietly(tmpPath);
      return HistoryBackupOutcome(HistoryBackupResult.failed, errorKind(e));
    }
    // A fresh copy restarts the clean-open count.
    _deleteQuietly(p.join(dir.path, _cleanOpensName));
    final problems = pruneHistoryBackups(
      appDataDir,
      now: now,
      policy: policy,
      deleteFile: deleteFile,
    );
    return HistoryBackupOutcome(HistoryBackupResult.created, null, [
      ...leftovers,
      ...problems,
    ]);
  } catch (e) {
    return HistoryBackupOutcome(HistoryBackupResult.failed, errorKind(e));
  }
}

/// Records one clean open of the database. Removes every copy once
/// [HistoryBackupPolicy.cleanOpens] is reached, and copies older than
/// [HistoryBackupPolicy.maxAge] in any case. Never throws.
void noteCleanHistoryOpen(
  String appDataDir, {
  required DateTime now,
  HistoryBackupPolicy policy = const HistoryBackupPolicy(),
}) {
  final dir = Directory(historyBackupDir(appDataDir));
  if (!dir.existsSync()) return;
  try {
    // A copy cut off mid-write is plaintext history too.
    _removeLeftoverTemps(dir, _deleteFile);
    final counter = File(p.join(dir.path, _cleanOpensName));
    final opens =
        (counter.existsSync()
            ? int.tryParse(counter.readAsStringSync().trim()) ?? 0
            : 0) +
        1;
    if (opens >= policy.cleanOpens) {
      eraseHistoryBackups(appDataDir);
      return;
    }
    counter.writeAsStringSync('$opens');
    final problems = pruneHistoryBackups(appDataDir, now: now, policy: policy);
    if (problems.isNotEmpty) {
      _log.warning('History backups not fully pruned: ${problems.join('; ')}');
    }
  } catch (e, st) {
    _log.warning('History backups not pruned', e, st);
  }
}

/// Completed copies with a valid stamp, newest first. Temporary and foreign
/// files are ignored.
List<File> listHistoryBackups(String appDataDir) {
  final dir = Directory(historyBackupDir(appDataDir));
  if (!dir.existsSync()) return const [];
  final files = [
    for (final e in dir.listSync())
      if (e is File && _stampOf(e) != null) e,
  ]..sort((a, b) => _stampOf(b)!.compareTo(_stampOf(a)!));
  return files;
}

/// Drops copies stamped in the future (a wrong clock wrote them, so their
/// age is unknown) or older than [HistoryBackupPolicy.maxAge], then, oldest
/// first, every copy beyond [HistoryBackupPolicy.keep] or the size cap. The
/// newest valid copy is never dropped for count or size.
///
/// Returns the file names (never the folder path, which holds the user name)
/// that could not be deleted, so a caller in a background isolate can log
/// them (#602). [deleteFile] is injectable so tests can make a delete throw.
@visibleForTesting
List<String> pruneHistoryBackups(
  String appDataDir, {
  required DateTime now,
  HistoryBackupPolicy policy = const HistoryBackupPolicy(),
  void Function(String path) deleteFile = _deleteFile,
}) {
  final problems = <String>[];
  final valid = <File>[];
  for (final file in listHistoryBackups(appDataDir)) {
    final age = now.difference(_stampOf(file)!);
    if (age.isNegative || age > policy.maxAge) {
      _deleteQuietly(file.path, deleteFile, problems);
    } else {
      valid.add(file);
    }
  }
  var kept = 0;
  var total = 0;
  for (final file in valid) {
    final size = file.lengthSync();
    final fits =
        kept == 0 ||
        (kept < policy.keep && total + size <= policy.maxTotalBytes);
    if (!fits) break;
    kept++;
    total += size;
  }
  for (final file in valid.skip(kept)) {
    _deleteQuietly(file.path, deleteFile, problems);
  }
  return problems;
}

/// Removes the backup folder (factory reset, forgot-PIN wipe, delete all
/// recordings). A folder that resists is marked for [retryPendingBackupErase]
/// at the next start. Returns the paths that could not be removed.
List<String> eraseHistoryBackups(String appDataDir) {
  final dir = Directory(historyBackupDir(appDataDir));
  final marker = File(p.join(appDataDir, historyBackupErasePendingName));
  if (!dir.existsSync()) {
    _deleteQuietly(marker.path);
    return const [];
  }
  try {
    dir.deleteSync(recursive: true);
    _deleteQuietly(marker.path);
    return const [];
  } catch (e, st) {
    _log.warning(
      'Could not remove the history backups; retrying next start',
      e,
      st,
    );
    try {
      marker.writeAsStringSync('');
    } catch (e, st) {
      _log.warning('Could not mark the history backups for removal', e, st);
    }
    try {
      return [
        for (final f in dir.listSync(recursive: true))
          if (f is File) f.path,
      ];
    } catch (_) {
      return [dir.path];
    }
  }
}

/// Repeats an erase that failed in an earlier session. Never throws.
void retryPendingBackupErase(String appDataDir) {
  if (!File(p.join(appDataDir, historyBackupErasePendingName)).existsSync()) {
    return;
  }
  eraseHistoryBackups(appDataDir);
}

void _writeVerifiedCopy(String source, String tmpPath, String? hexKey) {
  _deleteQuietly(tmpPath);
  final src = openSqlite(source, mode: OpenMode.readOnly, hexKey: hexKey);
  try {
    final quoted = tmpPath.replaceAll("'", "''");
    src.execute("VACUUM INTO '$quoted'");
  } finally {
    src.close();
  }
  verifySqliteCopy(source, tmpPath, sourceHexKey: hexKey, copyHexKey: hexKey);
}

void _removeLeftoverTemps(
  Directory dir,
  void Function(String path) deleteFile, [
  List<String>? problems,
]) {
  for (final e in dir.listSync()) {
    if (e is File && e.path.endsWith(_tmpSuffix)) {
      _deleteQuietly(e.path, deleteFile, problems);
    }
  }
}

void _deleteFile(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
}

/// Deletes [path] and swallows a failure. A failure is recorded by file name
/// only: the OS error text and the folder path carry the user name and would
/// reach the log file and every crash report as a breadcrumb.
void _deleteQuietly(
  String path, [
  void Function(String path) deleteFile = _deleteFile,
  List<String>? problems,
]) {
  try {
    deleteFile(path);
  } catch (e) {
    final name = p.basename(path);
    problems?.add(name);
    _log.debug('Could not delete $name (${e.runtimeType})');
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `yyyyMMdd-HHmmss`, in UTC so a time zone change cannot reorder copies.
String _formatStamp(DateTime t) {
  final u = t.toUtc();
  return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}'
      '-${_two(u.hour)}${_two(u.minute)}${_two(u.second)}';
}

final _stampPattern = RegExp(
  r'^history-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.db$',
);

DateTime? _stampOf(File file) {
  final m = _stampPattern.firstMatch(p.basename(file.path));
  if (m == null) return null;
  final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime.utc(v[0], v[1], v[2], v[3], v[4], v[5]);
}

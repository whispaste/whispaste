/// A history database whose data key is lost, set aside unchanged (#1023,
/// part of #591).
///
/// When the history file is encrypted and the data key is known to be gone
/// (the store answers [DataKeyLost]: the marker is there, the key is missing
/// or another one), the start moves the file with its SQLite side files into
/// a folder of its own below `history_set_aside/` and opens a fresh, empty
/// history. Moving is a rename inside the app-data folder: the bytes stay as
/// they are, nothing is decrypted, rewritten or deleted. A copy of the key
/// marker goes along, so the folder names the key it needs.
///
/// Once the old key is back (recovery code or backup file, #1167), a later
/// start finds the folder whose file opens with that key and moves it back.
/// The history used in between goes into a set-aside folder of its own
/// (`…-interim`), so it is not lost either.
///
/// While any set-aside folder exists, sweeps that delete files no database
/// row refers to (orphaned recordings, import work, note images) pause: those
/// files belong to the history that is set aside.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show OpenMode;

import '../logging/app_logger.dart';
import 'history_encryption.dart';
import 'sqlite_copy_check.dart';

final _log = AppLogger('HistorySetAside');

/// Folder below the app-data folder that holds set-aside histories.
const historySetAsideDirName = 'history_set_aside';

/// Suffix of a folder that holds the history used while the old one was set
/// aside.
const historySetAsideInterimSuffix = '-interim';

/// SQLite side files that belong to the database file and move with it.
const _sideFileSuffixes = ['-wal', '-shm', '-journal'];

/// Name of the data-key marker (`data_key.json`, see `DataKeyStore`). Kept
/// as a literal here so this file does not pull in the key store.
const _markerFileName = 'data_key.json';

/// The set-aside folder of [appData].
String historySetAsideDir(String appData) =>
    p.join(appData, historySetAsideDirName);

/// Whether any history is set aside in [appData]. Never throws.
bool hasSetAsideHistory(String appData) {
  try {
    final root = Directory(historySetAsideDir(appData));
    if (!root.existsSync()) return false;
    return root
        .listSync(followLinks: false)
        .whereType<Directory>()
        .any((d) => File(p.join(d.path, p.basename(_dbName))).existsSync());
  } on FileSystemException {
    // Unknown: keep the sweeps paused rather than delete something.
    return true;
  }
}

/// File name every set-aside database keeps.
const _dbName = 'history.db';

/// Moves the history file at [dbPath] and its side files into a new folder
/// below [historySetAsideDir] and returns that folder. The marker of
/// [appData] is copied along when present. [suffix] is appended to the
/// folder name.
///
/// Throws a [FileSystemException] when the database could not be moved; the
/// file then stays where it was (side files that had moved are moved back).
String setAsideHistory(
  String appData,
  String dbPath, {
  required DateTime now,
  String suffix = '',
}) {
  final root = Directory(historySetAsideDir(appData))
    ..createSync(recursive: true);
  final folder = _freshFolder(root.path, '${_stamp(now)}$suffix');
  final moved = <(String, String)>[];
  try {
    final target = p.join(folder.path, _dbName);
    File(dbPath).renameSync(target);
    moved.add((dbPath, target));
    for (final suffix in _sideFileSuffixes) {
      final side = File('$dbPath$suffix');
      if (!side.existsSync()) continue;
      final sideTarget = '$target$suffix';
      side.renameSync(sideTarget);
      moved.add(('$dbPath$suffix', sideTarget));
    }
  } on FileSystemException {
    for (final (from, to) in moved.reversed) {
      try {
        File(to).renameSync(from);
      } on FileSystemException catch (e) {
        // Left in the folder; the folder is never deleted, so nothing is lost.
        _log.debug('Set-aside file not moved back after a failed move', e);
      }
    }
    if (moved.isEmpty) _deleteIfEmpty(folder);
    rethrow;
  }
  final marker = File(p.join(appData, _markerFileName));
  if (marker.existsSync()) {
    try {
      marker.copySync(p.join(folder.path, _markerFileName));
    } on FileSystemException catch (e) {
      // The marker copy only labels the folder; the file itself is safe.
      _log.debug('Key marker not copied into the set-aside folder', e);
    }
  }
  return folder.path;
}

/// The newest set-aside folder of [appData] whose encrypted database opens
/// with [hexKey], or null. Interim folders and plain files are skipped;
/// files are opened read-only, so nothing in them changes.
String? setAsideHistoryFor(String appData, String hexKey) {
  final root = Directory(historySetAsideDir(appData));
  if (!root.existsSync()) return null;
  final folders =
      root
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !d.path.endsWith(historySetAsideInterimSuffix))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  for (final folder in folders) {
    final db = p.join(folder.path, _dbName);
    if (!File(db).existsSync() || isPlainSqliteFile(db)) continue;
    if (_opensWith(db, hexKey)) return folder.path;
  }
  return null;
}

/// Puts the database in [folder] back to [dbPath]. A database already at
/// [dbPath] is set aside first as an interim folder, whose path is returned
/// (null when there was none). The folder of the restored file is removed
/// once only the marker copy is left in it.
///
/// Throws a [FileSystemException] when a step failed; the current database
/// is then back in place.
String? restoreSetAsideHistory(
  String appData,
  String dbPath,
  String folder, {
  required DateTime now,
}) {
  String? interim;
  if (File(dbPath).existsSync()) {
    interim = setAsideHistory(
      appData,
      dbPath,
      now: now,
      suffix: historySetAsideInterimSuffix,
    );
  }
  final source = p.join(folder, _dbName);
  final moved = <(String, String)>[];
  try {
    File(source).renameSync(dbPath);
    moved.add((source, dbPath));
    for (final suffix in _sideFileSuffixes) {
      final side = File('$source$suffix');
      if (!side.existsSync()) continue;
      side.renameSync('$dbPath$suffix');
      moved.add(('$source$suffix', '$dbPath$suffix'));
    }
  } on FileSystemException {
    for (final (from, to) in moved.reversed) {
      try {
        File(to).renameSync(from);
      } on FileSystemException catch (e) {
        // Stays where it is; nothing is deleted.
        _log.debug('Restored file not moved back after a failed restore', e);
      }
    }
    if (interim != null) {
      _moveBack(p.join(interim, _dbName), dbPath);
      _deleteIfOnlyMarker(Directory(interim));
    }
    rethrow;
  }
  _deleteIfOnlyMarker(Directory(folder));
  return interim;
}

void _moveBack(String from, String to) {
  try {
    File(from).renameSync(to);
    for (final suffix in _sideFileSuffixes) {
      final side = File('$from$suffix');
      if (side.existsSync()) side.renameSync('$to$suffix');
    }
  } on FileSystemException catch (e) {
    // Stays in the interim folder.
    _log.debug('Interim history not moved back', e);
  }
}

bool _opensWith(String path, String hexKey) {
  try {
    final db = openSqlite(path, mode: OpenMode.readOnly, hexKey: hexKey);
    try {
      db.select('SELECT count(*) FROM sqlite_master');
      return true;
    } finally {
      db.close();
    }
  } on Object {
    return false;
  }
}

Directory _freshFolder(String root, String name) {
  var candidate = Directory(p.join(root, name));
  var n = 2;
  while (candidate.existsSync()) {
    candidate = Directory(p.join(root, '$name-$n'));
    n++;
  }
  return candidate..createSync();
}

void _deleteIfEmpty(Directory folder) {
  try {
    if (folder.listSync().isEmpty) folder.deleteSync();
  } on FileSystemException catch (e) {
    // An empty folder left behind is harmless.
    _log.debug('Empty set-aside folder not removed', e);
  }
}

void _deleteIfOnlyMarker(Directory folder) {
  try {
    final names = folder.listSync().map((e) => p.basename(e.path)).toSet();
    if (names.difference({_markerFileName}).isEmpty) {
      folder.deleteSync(recursive: true);
    }
  } on FileSystemException catch (e) {
    // Harmless: an empty folder is skipped by every reader.
    _log.debug('Restored set-aside folder not removed', e);
  }
}

/// UTC timestamp for folder names, sortable as text.
String _stamp(DateTime now) {
  final u = now.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}-'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}';
}

/// Keeps the app's own data readable by the current user only (POSIX).
///
/// The dictation history holds the transcribed text, so the app-data folder
/// is set to 0700 and the files in it (history database with its `-wal` and
/// `-shm`, logs, install id, preferences) to 0600. This is the same rule as
/// for the audio folders ([UserAudioDirs]). Windows relies on the per-user
/// ACL of the roaming app-data folder and is left alone.
///
/// Best effort: a failure is logged once per path and never stops startup.
/// Only the folder itself, its regular files and `logs/` are touched; the
/// audio folders are handled by [UserAudioDirs] and model folders hold no
/// personal data.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';
import '../core/platform/posix_native.dart';

final _log = AppLogger('PrivateAppFiles');

const _ownerOnlyDir = 0x1C0; // 0700
const _ownerOnlyFile = 0x180; // 0600
const _permissionBits = 0x1FF; // 0777

/// Tightens each of [roots] and the files in it. Called at startup and by the
/// history database right after it has been opened, so a fresh install gets
/// its files private from the first launch. [posix] defaults to "not
/// Windows"; tests pass it explicitly.
Future<void> hardenPrivateAppFiles(
  Iterable<String> roots, {
  bool? posix,
}) async => hardenPrivateAppFilesSync(roots, posix: posix);

/// Synchronous form of [hardenPrivateAppFiles], for the database setup
/// callback.
void hardenPrivateAppFilesSync(Iterable<String> roots, {bool? posix}) {
  if (!(posix ?? !Platform.isWindows)) return;
  for (final root in roots.toSet()) {
    if (root.isEmpty) continue;
    try {
      _hardenFolder(root, recurseInto: const {'logs'});
    } on Exception catch (e) {
      _log.warning('Could not make app data private: $root: $e');
    }
  }
}

void _hardenFolder(String dir, {Set<String> recurseInto = const {}}) {
  // A symlinked app-data folder is the user's own choice (another disk);
  // its target is left as it is.
  if (FileSystemEntity.typeSync(dir, followLinks: false) !=
      FileSystemEntityType.directory) {
    return;
  }
  _restrict(dir, _ownerOnlyDir);
  for (final entity in Directory(dir).listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is File) {
      _restrict(entity.path, _ownerOnlyFile);
    } else if (entity is Directory && recurseInto.contains(name)) {
      _hardenFolder(entity.path);
    }
  }
}

void _restrict(String path, int mode) {
  if ((FileStat.statSync(path).mode & _permissionBits) == mode) return;
  if (!nativeChmod(path, mode)) {
    _log.warning('chmod ${mode.toRadixString(8)} failed: $path');
  }
}

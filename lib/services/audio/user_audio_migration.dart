/// Moves user audio out of the roaming profile on Windows, once (#265).
///
/// Earlier versions kept retained recordings, parked dictations and import
/// copies under `%APPDATA%\WhisPaste`. That folder roams with a domain
/// profile, so audio could be synced to other machines. These folders now
/// live under `%LOCALAPPDATA%\WhisPaste` ([userAudioRootDir]); this step
/// moves what an earlier version left behind.
///
/// It runs at every start before anything reads the audio folders, and does
/// nothing once the old folders are gone. A file that cannot be moved stays
/// where it is and is tried again at the next start; it is never deleted.
/// The recording journal stores absolute WAV paths, so entries that point
/// into the old folder are rewritten to the new one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../path_service.dart';

final _log = AppLogger('UserAudioMigration');

/// The folders that move, relative to the old and the new root.
const userAudioFolderNames = ['recordings', 'imports', 'pending-audio'];

/// Moves the audio folders from the app-data folder to [userAudioRootDir].
/// Windows only; never throws.
Future<void> migrateUserAudioToLocal() async {
  if (!Platform.isWindows) return;
  try {
    await moveUserAudio(from: appDataDir(), to: userAudioRootDir());
  } on Object catch (e) {
    _log.warning('Audio folders not moved: $e');
  }
}

/// Moves each of [userAudioFolderNames] from [from] to [to] and rewrites the
/// recording journal. Returns the number of files left behind.
Future<int> moveUserAudio({required String from, required String to}) async {
  if (p.equals(p.normalize(from), p.normalize(to))) return 0;
  var leftBehind = 0;
  for (final name in userAudioFolderNames) {
    final source = p.join(from, name);
    if (FileSystemEntity.typeSync(source, followLinks: false) ==
        FileSystemEntityType.notFound) {
      continue;
    }
    leftBehind += await _move(source, p.join(to, name));
  }
  await _rewriteJournal(
    journalDir: p.join(to, 'recordings', 'journal'),
    oldRecordings: p.join(from, 'recordings'),
    newRecordings: p.join(to, 'recordings'),
  );
  if (leftBehind > 0) {
    _log.warning('$leftBehind audio file(s) not moved yet, retried next start');
  }
  return leftBehind;
}

Future<int> _move(String source, String target) async {
  final type = FileSystemEntity.typeSync(target, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await Directory(p.dirname(target)).create(recursive: true);
    try {
      // Same volume (the usual case): one rename moves the whole folder,
      // a symlink the user set up included.
      if (FileSystemEntity.isLinkSync(source)) {
        await Link(source).rename(target);
      } else {
        await Directory(source).rename(target);
      }
      _log.info('Moved audio folder to $target');
      return 0;
    } on FileSystemException catch (e) {
      // Another volume (redirected profile): move file by file below.
      _log.debug('Folder rename failed, merging file by file: $e');
    }
  }
  if (FileSystemEntity.isLinkSync(source)) {
    _log.warning('Audio folder is a link and could not be moved: $source');
    return 1;
  }
  return _merge(Directory(source), target);
}

/// Moves every file of [source] into [target], keeping files that already
/// exist there. Empty source folders are removed afterwards.
Future<int> _merge(Directory source, String target) async {
  var leftBehind = 0;
  await Directory(target).create(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final dest = p.join(target, p.basename(entity.path));
    if (entity is Directory) {
      leftBehind += await _merge(entity, dest);
    } else if (entity is File) {
      if (!await _moveFile(entity, dest)) leftBehind++;
    } else {
      leftBehind++;
    }
  }
  try {
    await source.delete();
  } on FileSystemException catch (e) {
    // Not empty: something stayed behind and is retried next start.
    _log.debug('Old audio folder kept: ${source.path}: $e');
  }
  return leftBehind;
}

Future<bool> _moveFile(File file, String dest) async {
  if (FileSystemEntity.typeSync(dest, followLinks: false) !=
      FileSystemEntityType.notFound) {
    _log.warning('Audio file exists in both places, kept both: $dest');
    return false;
  }
  try {
    await file.rename(dest);
    return true;
  } on FileSystemException catch (e) {
    // Different volume: copy, then remove the original.
    _log.debug('File rename failed, copying: ${file.path}: $e');
  }
  try {
    await file.copy(dest);
    await file.delete();
    return true;
  } on FileSystemException catch (e) {
    _log.warning('Audio file not moved: ${file.path}: $e');
    return false;
  }
}

Future<void> _rewriteJournal({
  required String journalDir,
  required String oldRecordings,
  required String newRecordings,
}) async {
  final dir = Directory(journalDir);
  if (!dir.existsSync()) return;
  final oldPrefix = p.normalize(oldRecordings);
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    try {
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map<String, dynamic>) continue;
      final wav = decoded['wavPath'];
      if (wav is! String || !p.isWithin(oldPrefix, p.normalize(wav))) {
        continue;
      }
      decoded['wavPath'] = p.join(
        newRecordings,
        p.relative(p.normalize(wav), from: oldPrefix),
      );
      await entity.writeAsString(jsonEncode(decoded), flush: true);
    } on Object catch (e) {
      // A corrupt entry is reported by the recovery scan as before.
      _log.warning('Journal entry not rewritten: ${entity.path}: $e');
    }
  }
}

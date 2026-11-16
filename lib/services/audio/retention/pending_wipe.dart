/// Files a forgot-PIN wipe or a factory reset could not remove.
///
/// Only single files are listed, never a folder and never a root, so a
/// recording or journal entry made after the wipe is not swept with them. Each
/// entry stores the file's own modification time and size. The next start
/// deletes a listed file only when both still match exactly. Otherwise the
/// entry is dropped and the file is left alone: a changed file is new, and
/// keeping it is the safe side. Entries without such a signature (written by
/// an older version) are dropped the same way.
///
/// The check does not depend on the system clock. Its granularity is limited by
/// the file system (1 s on HFS+, 2 s on FAT): a replacement with the same size
/// and the same modification time inside that window passes the check and is
/// removed. Accepted: such a file is rare and was requested for deletion.
///
/// A database row that still names a file protects it: the entry stays queued.
/// Journal entries do not protect a file. The start runs this cleanup before
/// the recovery scan, so a leftover journal entry is removed with its file and
/// is never offered for recovery. The orphan grace period does not apply: the
/// user asked for the deletion.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../path_service.dart';

final _log = AppLogger('PendingWipe');

/// The signature of one queued file: its modification time and size.
typedef _Signature = ({int modified, int size});

/// Pending applies share one pass: a second call while one runs gets the same
/// result, so two starts cannot race over the same files.
Future<int>? _inFlight;

/// Every file under [dirPath], recursively, or null when the folder cannot be
/// listed. Used when a folder could not be removed, so that only its files
/// are queued.
Future<List<String>?> filesUnder(String dirPath) async {
  try {
    return await io.Directory(dirPath)
        .list(recursive: true)
        .where((entity) => entity is io.File)
        .map((entity) => entity.path)
        .toList();
  } catch (e, st) {
    _log.warning('pending wipe: could not list $dirPath', e, st);
    return null;
  }
}

/// Queues [paths] for the next start. Every path must be an existing file
/// strictly inside a user audio folder; a root, a folder or a missing file is
/// refused. Returns false, and queues nothing, when a path is refused or the
/// list cannot be written. [fileSystem] reads the signatures; the list itself
/// always lives on the local disk.
Future<bool> recordPendingWipe(
  Iterable<String> paths, {
  FileSystem? fileSystem,
}) async {
  final list = paths.toList();
  if (list.isEmpty) return true;
  final fs = fileSystem ?? const LocalFileSystem();
  final roots = userAudioDirectories();
  final signatures = <String, _Signature>{};
  try {
    for (final path in list) {
      final inside = roots.any((root) => p.isWithin(root, path));
      if (!inside ||
          await fs.type(path, followLinks: false) !=
              io.FileSystemEntityType.file) {
        _log.warning('pending wipe: refused a path that is not an audio file');
        return false;
      }
      final stat = await fs.file(path).stat();
      signatures[path] = (
        modified: stat.modified.millisecondsSinceEpoch,
        size: stat.size,
      );
    }
    final file = io.File(pendingWipeFile());
    final merged = {...await _readPending(file), ...signatures};
    await file.parent.create(recursive: true);
    await file.writeAsString(_encodeAll(merged));
    return true;
  } catch (e, st) {
    _log.warning('pending wipe: could not record the list', e, st);
    return false;
  }
}

/// Removes the queued files at the start. [referencedPaths] names the files
/// that a database row still uses; those stay queued. Calls that overlap share
/// one pass. Returns how many entries stay queued.
Future<int> applyPendingWipe({
  required Future<Set<String>> Function() referencedPaths,
  FileSystem? fileSystem,
}) {
  final running = _inFlight;
  if (running != null) return running;
  final fs = fileSystem ?? const LocalFileSystem();
  final run = _runPendingWipe(referencedPaths, fs);
  _inFlight = run;
  return run.whenComplete(() {
    _inFlight = null;
  });
}

Future<int> _runPendingWipe(
  Future<Set<String>> Function() referencedPaths,
  FileSystem fs,
) async {
  final file = io.File(pendingWipeFile());
  final pending = await _readPending(file);
  if (pending.isEmpty) {
    if (file.existsSync()) await file.delete();
    return 0;
  }
  final protected = await referencedPaths();
  final remaining = <String, _Signature>{};
  for (final entry in pending.entries) {
    final keep = await _process(
      fs,
      entry.key,
      entry.value,
      protected: protected.contains(entry.key),
    );
    if (keep) remaining[entry.key] = entry.value;
  }
  if (remaining.isEmpty) {
    if (file.existsSync()) await file.delete();
  } else {
    await file.writeAsString(_encodeAll(remaining));
  }
  return remaining.length;
}

/// Returns true when the entry stays queued.
Future<bool> _process(
  FileSystem fs,
  String path,
  _Signature signature, {
  required bool protected,
}) async {
  try {
    if (await fs.type(path, followLinks: false) !=
        io.FileSystemEntityType.file) {
      return false;
    }
    if (protected) return true;
    final stat = await fs.file(path).stat();
    if (stat.type != io.FileSystemEntityType.file) return false;
    final matches =
        stat.modified.millisecondsSinceEpoch == signature.modified &&
        stat.size == signature.size;
    if (!matches) return false;
    await fs.file(path).delete();
    return false;
  } on io.FileSystemException catch (e, st) {
    // Vanished between the checks: nothing is left to remove. A file that is
    // still there but cannot be removed stays queued.
    if (await fs.type(path, followLinks: false) ==
        io.FileSystemEntityType.file) {
      _log.warning('pending wipe: could not delete $path', e, st);
      return true;
    }
    return false;
  }
}

String _encodeAll(Map<String, _Signature> entries) => jsonEncode({
  for (final entry in entries.entries)
    entry.key: {'mtime': entry.value.modified, 'size': entry.value.size},
});

Future<Map<String, _Signature>> _readPending(io.File file) async {
  try {
    if (!file.existsSync()) return {};
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final result = <String, _Signature>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic> &&
          value['mtime'] is int &&
          value['size'] is int) {
        result[entry.key] = (
          modified: value['mtime'] as int,
          size: value['size'] as int,
        );
      } else {
        _log.warning('pending wipe: dropped an entry without a signature');
      }
    }
    return result;
  } catch (e, st) {
    _log.warning('pending wipe list is unreadable', e, st);
    return {};
  }
}

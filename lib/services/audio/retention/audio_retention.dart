/// Retention of retained WAV audio, separate from the retention of history text.
///
/// Audio has its own age limit ([kRetainedAudioMaxAge]). The rule lives in
/// [planRetainedAudioDeletions] so it can be tested without a database or a
/// file system; [sweepRetainedAudio] applies the plan.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/data/database.dart';
import '../../../core/logging/app_logger.dart';

final _log = AppLogger('AudioRetention');

/// How long retained audio is kept, counted from when it was saved. Fixed for
/// now; a user-selectable period is an open item.
const Duration kRetainedAudioMaxAge = Duration(days: 30);

/// One retained audio file as the sweep sees it.
class RetainedAudioRef {
  const RetainedAudioRef({
    required this.id,
    required this.filePath,
    required this.createdAt,
  });

  /// Attachment row id.
  final String id;
  final String filePath;
  final DateTime createdAt;
}

/// Returns the items older than [maxAge] at [now]. An item created exactly at
/// the cutoff is kept.
List<RetainedAudioRef> planRetainedAudioDeletions({
  required Iterable<RetainedAudioRef> items,
  required DateTime now,
  Duration maxAge = kRetainedAudioMaxAge,
}) {
  final cutoff = now.subtract(maxAge);
  return [
    for (final item in items)
      if (item.createdAt.isBefore(cutoff)) item,
  ];
}

/// Deletes expired retained audio and its attachment rows. A file that cannot
/// be deleted keeps its row, so the next sweep retries it. Returns the number of
/// rows removed.
Future<int> sweepRetainedAudio({
  required HistoryDatabase db,
  required DateTime now,
  Future<void> Function(String path)? deleteFile,
}) async {
  final rows = await db.listAudioAttachments();
  final plan = planRetainedAudioDeletions(
    items: [
      for (final row in rows)
        RetainedAudioRef(
          id: row.id,
          filePath: row.filepath,
          createdAt: row.createdAt,
        ),
    ],
    now: now,
  );
  if (plan.isEmpty) return 0;

  final removable = <String>[];
  for (final item in plan) {
    try {
      await (deleteFile ?? _deleteIfExists)(item.filePath);
      removable.add(item.id);
    } on FileSystemException catch (e) {
      _log.warning('Could not delete expired audio, keeping its row: $e');
    }
  }
  await db.deleteAudioAttachments(removable);
  return removable.length;
}

Future<void> _deleteIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// How long a retained WAV without any reference may exist before the orphan
/// sweep deletes it. The grace period covers a recording that is still being
/// saved (its row or journal entry is not written yet).
const Duration kOrphanedWavGrace = Duration(hours: 24);

/// One file in the retained-audio folder, as the orphan sweep sees it.
class RetainedWavFile {
  const RetainedWavFile({required this.path, required this.modified});

  final String path;
  final DateTime modified;
}

/// Returns the WAVs that nothing refers to and that are older than [grace].
/// A file in [referencedPaths] (attachment rows or open journal entries) is
/// never planned, however old it is.
List<RetainedWavFile> planOrphanedWavDeletions({
  required Iterable<RetainedWavFile> files,
  required Set<String> referencedPaths,
  required DateTime now,
  Duration grace = kOrphanedWavGrace,
}) {
  final cutoff = now.subtract(grace);
  // Compare normalised paths: stored references and directory listings may
  // use different separators (e.g. `/` vs `\` on Windows).
  final protected = {for (final path in referencedPaths) p.normalize(path)};
  return [
    for (final file in files)
      if (!protected.contains(p.normalize(file.path)) &&
          file.modified.isBefore(cutoff))
        file,
  ];
}

/// Deletes orphaned `.wav` files in [directory]. Returns the number deleted.
/// A missing directory is not an error. A file that cannot be deleted is
/// logged and left for the next sweep.
Future<int> sweepOrphanedRetainedWavs({
  required String directory,
  required Set<String> referencedPaths,
  required DateTime now,
  Duration grace = kOrphanedWavGrace,
}) async {
  final dir = Directory(directory);
  if (!await dir.exists()) return 0;

  final files = <RetainedWavFile>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.wav')) continue;
    final stat = await entity.stat();
    files.add(RetainedWavFile(path: entity.path, modified: stat.modified));
  }

  var deleted = 0;
  for (final orphan in planOrphanedWavDeletions(
    files: files,
    referencedPaths: referencedPaths,
    now: now,
    grace: grace,
  )) {
    try {
      await File(orphan.path).delete();
      deleted++;
    } on FileSystemException catch (e) {
      _log.warning('Could not delete orphaned audio, retrying later: $e');
    }
  }
  return deleted;
}

/// Returns the import work entries (one folder per job, named by its id) that
/// no queued or running job owns and that have been idle for [maxAge].
/// [RetainedWavFile] carries the path and the last activity of any entry.
List<RetainedWavFile> planOrphanedImportDeletions({
  required Iterable<RetainedWavFile> entries,
  required Set<String> liveJobIds,
  required DateTime now,
  Duration maxAge = kRetainedAudioMaxAge,
}) {
  final cutoff = now.subtract(maxAge);
  return [
    for (final entry in entries)
      if (!liveJobIds.contains(p.basename(entry.path)) &&
          entry.modified.isBefore(cutoff))
        entry,
  ];
}

/// Deletes orphaned import work folders in [workDir], with their files. A
/// folder is idle only when nothing in it changed for [maxAge], so a job that
/// is still writing is never old. A missing folder is not an error; an entry
/// that cannot be deleted is logged and left for the next sweep.
Future<int> sweepOrphanedImportWork({
  required String workDir,
  required Set<String> liveJobIds,
  required DateTime now,
  Duration maxAge = kRetainedAudioMaxAge,
}) async {
  final dir = Directory(workDir);
  if (!await dir.exists()) return 0;

  final entries = <RetainedWavFile>[];
  await for (final entity in dir.list(followLinks: false)) {
    entries.add(
      RetainedWavFile(path: entity.path, modified: await _lastActivity(entity)),
    );
  }

  var deleted = 0;
  for (final orphan in planOrphanedImportDeletions(
    entries: entries,
    liveJobIds: liveJobIds,
    now: now,
    maxAge: maxAge,
  )) {
    try {
      if (await FileSystemEntity.isDirectory(orphan.path)) {
        await Directory(orphan.path).delete(recursive: true);
      } else {
        await File(orphan.path).delete();
      }
      deleted++;
    } on FileSystemException catch (e) {
      _log.warning('Could not delete orphaned import work, retrying later: $e');
    }
  }
  return deleted;
}

/// The newest modification time of anything inside a folder, or the entry's
/// own time when it is a file or an empty folder. A folder's own time is
/// skipped: it changes with its entries, and a folder that was just created
/// would look active.
Future<DateTime> _lastActivity(FileSystemEntity entity) async {
  if (entity is! Directory) return (await entity.stat()).modified;
  DateTime? newest;
  await for (final child in entity.list(recursive: true, followLinks: false)) {
    final modified = (await child.stat()).modified;
    if (newest == null || modified.isAfter(newest)) newest = modified;
  }
  return newest ?? (await entity.stat()).modified;
}

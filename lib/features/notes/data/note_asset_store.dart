/// File storage for note image attachments (WP-31a).
///
/// Bytes live below the app data directory, one folder per note:
/// `note_assets/<noteId>/<assetId>.<ext>`. The database row only records the
/// relative path. The folder layout keeps everything a note owns in one place,
/// so removing a note removes its images with it, and a sweep can find folders
/// whose note is gone. Files are only ever written inside the app's own data
/// directory; no path chosen by the user is used as a storage location.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/data/note_asset_storage.dart';
import 'note_image_inspector.dart';

class NoteAssetStore {
  NoteAssetStore({required this.appDataDirPath});

  /// Absolute path of the app data directory, the root that relative asset
  /// paths are resolved against.
  final String appDataDirPath;

  static const folderName = noteAssetFolderName;

  /// Path of an asset relative to [appDataDirPath], in forward-slash form so
  /// the stored value is the same on every platform.
  static String relativePathFor(
    String noteId,
    String assetId,
    NoteImageType type,
  ) => '$folderName/$noteId/$assetId.${type.extension}';

  /// Absolute folder that holds every note's assets.
  String get rootPath => p.join(appDataDirPath, folderName);

  /// Absolute path of an asset, or null when [relativePath] is not exactly
  /// `note_assets/<noteId>/<file>`. Absolute paths, `..`, empty segments and
  /// backslashes are refused, so a stored path can never reach outside the
  /// image folder.
  String? resolveAssetPath(String relativePath) {
    if (relativePath.contains('\\')) return null;
    final parts = relativePath.split('/');
    if (parts.length != 3 || parts[0] != folderName) return null;
    if (!parts.every(_isSafeSegment)) return null;
    return p.joinAll([appDataDirPath, ...parts]);
  }

  /// Absolute path of an asset. Throws [ArgumentError] for a path that
  /// [resolveAssetPath] refuses.
  String absolutePath(String relativePath) {
    final resolved = resolveAssetPath(relativePath);
    if (resolved == null) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'outside the note image folder',
      );
    }
    return resolved;
  }

  Future<void> write(String relativePath, Uint8List bytes) async {
    final target = File(absolutePath(relativePath));
    await target.parent.create(recursive: true);
    // Write beside the target, then rename: a crash mid-write must never leave
    // a half-written image that a note already references.
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  }

  Future<void> delete(String relativePath) async {
    final path = resolveAssetPath(relativePath);
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Removes the folder of [noteId] with every asset in it. Ids that could
  /// point outside the folder are refused.
  Future<void> deleteNoteFolder(String noteId) async {
    if (!_isSafeSegment(noteId)) return;
    final dir = Directory(p.join(rootPath, noteId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes every note folder whose note id is not in [liveNoteIds].
  Future<void> sweepOrphans(Set<String> liveNoteIds) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (!liveNoteIds.contains(name)) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// Removes image files that no database row refers to, and the folders of
  /// notes that no longer exist. Temporary `.tmp` files are left alone: a
  /// write may be in progress.
  ///
  /// The image folder is listed before the two loaders run. A file that
  /// appears after the listing is never judged. A file that is listed already
  /// has its row, because the row is written before the file is created, so
  /// the later read sees it.
  Future<void> sweep({
    required Future<Set<String>> Function() loadLiveNoteIds,
    required Future<Set<String>> Function() loadLiveRelativePaths,
  }) async {
    final files = await _listRelativeFiles();
    final liveNoteIds = await loadLiveNoteIds();
    final livePaths = await loadLiveRelativePaths();
    for (final rel in files) {
      if (rel.endsWith('.tmp')) continue;
      final noteId = rel.split('/')[1];
      if (!liveNoteIds.contains(noteId) || !livePaths.contains(rel)) {
        final file = File(absolutePath(rel));
        if (await file.exists()) await file.delete();
      }
    }
    await sweepOrphans(liveNoteIds);
  }

  /// Forward-slash paths, relative to the app data directory, of every file
  /// below the image folder.
  Future<List<String>> _listRelativeFiles() async {
    final root = Directory(rootPath);
    if (!await root.exists()) return const [];
    final out = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: appDataDirPath);
      out.add(rel.split(p.separator).join('/'));
    }
    return out;
  }

  static bool _isSafeSegment(String segment) =>
      segment.isNotEmpty &&
      segment != '.' &&
      segment != '..' &&
      !segment.contains('/') &&
      !segment.contains('\\');
}

/// Thrown by `NotesActions.addImage` when the bytes fail [inspectNoteImage].
class NoteImageRejectedException implements Exception {
  const NoteImageRejectedException(this.rejection);

  final NoteImageRejection rejection;

  @override
  String toString() => 'NoteImageRejectedException(${rejection.name})';
}

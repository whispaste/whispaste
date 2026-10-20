/// Storage rules for note image attachments (WP-31a): the folder name, the
/// amount limits, the error a refused import raises, and the erase that a
/// factory reset runs over the image files.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Folder under the app data directory that holds every note's images.
const noteAssetFolderName = 'note_assets';

/// Which limit an import would have exceeded.
enum NoteAssetLimit { perNoteCount, perNoteBytes, globalBytes }

/// Amount limits for note images. Enforced in the same transaction as the row
/// insert, so two imports cannot both pass the check.
class NoteAssetLimits {
  const NoteAssetLimits({
    this.maxCountPerNote = 20,
    this.maxBytesPerNote = 32 * 1024 * 1024,
    this.maxTotalBytes = 512 * 1024 * 1024,
  });

  final int maxCountPerNote;
  final int maxBytesPerNote;

  /// Bytes of all images of all notes together.
  final int maxTotalBytes;

  static const NoteAssetLimits standard = NoteAssetLimits();
}

/// Thrown when an import would exceed a [NoteAssetLimits] value. Nothing is
/// written in that case.
class NoteAssetLimitException implements Exception {
  const NoteAssetLimitException(this.reason);

  final NoteAssetLimit reason;

  @override
  String toString() => 'NoteAssetLimitException(${reason.name})';
}

/// Removes the whole image folder below [appDataDir]. Used by the factory
/// reset: a missing folder is not an error.
Future<void> eraseNoteAssetRoot(String appDataDir) async {
  final root = Directory(p.join(appDataDir, noteAssetFolderName));
  if (await root.exists()) await root.delete(recursive: true);
}

/// Installed status of a catalog file: present with its pinned size (#1513).
library;

import 'dart:io';

import 'download_fragment_guard.dart' show fragmentIdentityPath;

/// Whether [path] is a file of exactly [sizeBytes]. A file of another size
/// (a cut-off copy, an HTML page saved under the model's name, another
/// release) is not installed; the next download replaces it. The full
/// SHA-256 check runs after a download and before a GPU model loads.
Future<bool> fileHasPinnedSize(String path, int sizeBytes) async {
  // The final rename precedes hashing. A surviving identity sidecar means
  // this download has not passed verification yet, also after a crash.
  if (await File(fragmentIdentityPath(path)).exists()) return false;
  final stat = await FileStat.stat(path);
  return stat.type == FileSystemEntityType.file && stat.size == sizeBytes;
}

/// Synchronous equivalent for the speech engine's readiness check.
bool fileHasPinnedSizeSync(String path, int sizeBytes) {
  try {
    if (File(fragmentIdentityPath(path)).existsSync()) return false;
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.file && stat.size == sizeBytes;
  } on FileSystemException {
    return false;
  }
}

import 'dart:io';

/// Removes a temp directory a test created.
///
/// On Windows a file handle that is still open (a database or asset store
/// that is closed asynchronously) makes the recursive delete fail with
/// errno 32. The directory then stays in %TEMP%, which the OS cleans up, so
/// that failure is ignored there. Elsewhere a failed delete still fails the
/// test.
void deleteTempDir(Directory dir) {
  if (!dir.existsSync()) return;
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
  }
}

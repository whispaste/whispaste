import 'dart:io';

/// Windows `ERROR_SHARING_VIOLATION`: another handle — the app's own or a
/// third party's (virus scanner, indexer, an editor) — still holds the file
/// open, so it cannot be deleted yet.
const int windowsSharingViolation = 32;

/// Delays between delete attempts. Locks of this kind are usually
/// short-lived (an engine finishing a model read, a scan of a fresh
/// download), so a few seconds of patience resolves most of them.
const List<Duration> kSharingViolationBackoff = [
  Duration(milliseconds: 250),
  Duration(milliseconds: 750),
  Duration(seconds: 2),
];

/// Whether [error] is a sharing violation. Matches the OS error code, never
/// the message, which Windows localizes.
bool isSharingViolation(Object error) =>
    error is FileSystemException &&
    error.osError?.errorCode == windowsSharingViolation;

/// Runs [action], retrying with [kSharingViolationBackoff] while it fails
/// with a sharing violation. Any other failure, or a lock that outlasts the
/// backoff, is rethrown for the caller to handle.
Future<T> retryOnSharingViolation<T>(
  Future<T> Function() action, {
  Future<void> Function(Duration delay)? wait,
}) async {
  final pause = wait ?? Future<void>.delayed;
  for (var attempt = 0; ; attempt++) {
    try {
      return await action();
    } on FileSystemException catch (e) {
      if (!isSharingViolation(e) ||
          attempt >= kSharingViolationBackoff.length) {
        rethrow;
      }
      await pause(kSharingViolationBackoff[attempt]);
    }
  }
}

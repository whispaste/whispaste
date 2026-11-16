/// Guards around a model download that span more than one request: which
/// file a partial `.tmp` belongs to (so a resume never appends bytes of a
/// different file version), and one writer per destination across processes.
///
/// Used by [HttpModelFetcher.fetchVerified] and the CUDA pack download.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';

final _log = AppLogger('DownloadGuard');

/// Sidecar next to `<dest>.tmp` that names the file the fragment belongs to:
/// `{"sha256": "...", "size": 123}`. The tmp reaper keeps an identified
/// fragment longer than an anonymous one (see `tmp_reaper.dart`).
String fragmentIdentityPath(String destPath) => '$destPath.tmp.json';

/// Prepares `<destPath>.tmp` for a download of the file with [sha256] and
/// [sizeBytes].
///
/// A fragment without an identity, or with the identity of another file
/// version, is deleted: its bytes may come from an earlier upstream revision
/// (before 1.5.0 the Parakeet bundle was fetched from `resolve/main`), and
/// appending the pinned bytes to them would only fail the hash at the end.
/// Afterwards the identity of the wanted file is written, so a later run of
/// the app may resume the fragment.
Future<void> prepareFragmentIdentity({
  required String destPath,
  required String sha256,
  required int sizeBytes,
}) async {
  final tmp = File('$destPath.tmp');
  final sidecar = File(fragmentIdentityPath(destPath));
  if (tmp.existsSync()) {
    final identity = await readFragmentIdentity(destPath);
    final matches =
        identity != null &&
        identity.sha256 == sha256 &&
        identity.sizeBytes == sizeBytes;
    if (!matches) {
      _log.warning(
        'Partial file ${p.basename(tmp.path)} has '
        '${identity == null ? 'no identity' : 'another identity'} '
        '— restarting from byte 0',
      );
      try {
        await tmp.delete();
      } on FileSystemException catch (e) {
        _log.warning('Could not delete ${tmp.path}: $e');
      }
    }
  }
  try {
    await sidecar.writeAsString(
      jsonEncode({'sha256': sha256, 'size': sizeBytes}),
      flush: true,
    );
  } on FileSystemException catch (e) {
    // Without the identity the fragment is only resumable in this session.
    _log.warning('Could not write ${sidecar.path}: $e');
  }
}

/// The identity stored for `<destPath>.tmp`, or null when there is none or
/// it is unreadable.
Future<({String sha256, int sizeBytes})?> readFragmentIdentity(
  String destPath,
) async {
  try {
    final raw = await File(fragmentIdentityPath(destPath)).readAsString();
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final sha = json['sha256'];
    final size = json['size'];
    if (sha is! String || size is! int) return null;
    return (sha256: sha, sizeBytes: size);
  } on Object {
    return null;
  }
}

/// Removes the identity sidecar once the fragment is gone (renamed into
/// place or deleted).
Future<void> clearFragmentIdentity(String destPath) async {
  final sidecar = File(fragmentIdentityPath(destPath));
  try {
    if (sidecar.existsSync()) await sidecar.delete();
  } on FileSystemException catch (e) {
    _log.warning('Could not delete ${sidecar.path}: $e');
  }
}

/// Path of the lock file for [destPath]: hidden, next to the file.
String downloadLockPath(String destPath) =>
    p.join(p.dirname(destPath), '.${p.basename(destPath)}.lock');

/// An exclusive, cross-process lock on one download destination.
///
/// Two WhisPaste processes (the app and a headless `--download-…` run, or a
/// second app started before the single-instance check) must never write
/// the same `.tmp`. The lock is an OS file lock on a small hidden file next
/// to the destination; the OS releases it when the process ends, so a crash
/// never leaves a stale lock. The lock file itself stays on disk on purpose:
/// deleting it would let a second process lock a fresh file while a third
/// still holds the old one.
///
/// Inside one process the [HttpModelFetcher] in-flight map serialises
/// callers first: POSIX record locks do not exclude the owning process.
class DownloadFileLock {
  DownloadFileLock._(this._file);

  final RandomAccessFile _file;

  /// Acquires the lock for [destPath], waiting while another process holds
  /// it. [isCancelled] is polled every [pollInterval]; when it turns true the
  /// wait ends with [DownloadLockCancelled]. [onWaiting] runs once when the
  /// first attempt finds the lock taken.
  static Future<DownloadFileLock> acquire(
    String destPath, {
    required bool Function() isCancelled,
    Duration pollInterval = const Duration(seconds: 1),
    void Function()? onWaiting,
  }) async {
    final lockFile = File(downloadLockPath(destPath));
    await lockFile.parent.create(recursive: true);
    final raf = await lockFile.open(mode: FileMode.append);
    var announced = false;
    while (true) {
      try {
        await raf.lock(FileLock.exclusive);
        return DownloadFileLock._(raf);
      } on FileSystemException {
        if (!announced) {
          announced = true;
          _log.info(
            'Another process is downloading ${p.basename(destPath)} — waiting',
          );
          onWaiting?.call();
        }
      }
      if (isCancelled()) {
        await raf.close();
        throw const DownloadLockCancelled();
      }
      await Future<void>.delayed(pollInterval);
      if (isCancelled()) {
        await raf.close();
        throw const DownloadLockCancelled();
      }
    }
  }

  /// Releases the lock. Safe to call once; errors are logged only.
  Future<void> release() async {
    try {
      await _file.unlock();
    } on FileSystemException catch (e) {
      _log.warning('Could not unlock download lock: $e');
    }
    try {
      await _file.close();
    } on FileSystemException catch (e) {
      _log.warning('Could not close download lock: $e');
    }
  }
}

/// The wait for another process's download was cancelled by the user.
class DownloadLockCancelled implements Exception {
  const DownloadLockCancelled();

  @override
  String toString() => 'Download cancelled while waiting for another download';
}

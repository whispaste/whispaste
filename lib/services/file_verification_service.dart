/// File verification service — SHA256 integrity checks for downloaded assets.
///
/// Extracted from [ModelDownloadNotifier] so that the verification logic is
/// independently testable and reusable across future download pipelines.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('FileVerification');

/// Lower-case hex SHA-256 of the file at [path].
///
/// Hashed on a background isolate: a multi-hundred-MB model must not stall
/// the UI isolate. Use this for every fresh download; startup size checks do
/// not call it.
Future<String> sha256HexOfFile(String path) =>
    Isolate.run(() => _sha256HexOfFile(path));

Future<String> _sha256HexOfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// Sidecar next to a verified file that remembers which file version matched.
String verifiedStampPath(String filePath) => '$filePath.verified.json';

// ---------------------------------------------------------------------------
// Result ADT
// ---------------------------------------------------------------------------

/// Outcome of a [FileVerificationService.verify] call.
sealed class VerificationResult {
  const VerificationResult();
}

/// The file exists and its SHA256 digest matches [expectedHash].
final class VerificationOk extends VerificationResult {
  const VerificationOk();
}

/// The file exists but its SHA256 digest does not match [expectedHash].
final class VerificationMismatch extends VerificationResult {
  const VerificationMismatch({
    required this.expectedHash,
    required this.actualHash,
  });

  final String expectedHash;
  final String actualHash;
}

/// An I/O error occurred while reading the file (e.g. missing or unreadable).
final class VerificationIoError extends VerificationResult {
  const VerificationIoError({required this.error});

  final Object error;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Verifies the integrity of a file by comparing its SHA256 digest against
/// an expected hash string.
///
/// The service is intentionally stateless and has no dependencies, making it
/// trivial to instantiate in tests without any mocking infrastructure.
///
/// Usage:
/// ```dart
/// final result = await FileVerificationService().verify(file, expectedHash);
/// switch (result) {
///   case VerificationOk(): // proceed
///   case VerificationMismatch(:final actualHash): // handle mismatch
///   case VerificationIoError(:final error): // handle I/O error
/// }
/// ```
class FileVerificationService {
  const FileVerificationService();

  /// Verifies [file] against [expectedHash] (hex-encoded SHA256).
  ///
  /// Returns:
  /// - [VerificationOk] when the digest matches.
  /// - [VerificationMismatch] when the digest does not match.
  /// - [VerificationIoError] when the file is missing or cannot be read.
  Future<VerificationResult> verify(File file, String expectedHash) async {
    _log.info('Verifying SHA256 of ${file.path}');

    final String actualHash;
    try {
      actualHash = await sha256HexOfFile(file.path);
    } on FileSystemException catch (e) {
      _log.warning('I/O error verifying ${file.path}: $e');
      return VerificationIoError(error: e);
    } catch (e) {
      _log.warning('Unexpected error verifying ${file.path}: $e');
      return VerificationIoError(error: e);
    }

    if (actualHash == expectedHash) {
      _log.info('SHA256 OK: ${file.path}');
      return const VerificationOk();
    }

    _log.warning(
      'SHA256 mismatch for ${file.path}: '
      'expected=$expectedHash actual=$actualHash',
    );
    return VerificationMismatch(
      expectedHash: expectedHash,
      actualHash: actualHash,
    );
  }

  /// Like [verify], but a full hash is needed only once per file version.
  ///
  /// After a successful hash the stamp records the expected hash, the exact
  /// size and the modification time. A later call that finds the same hash,
  /// size and mtime returns [VerificationOk] without reading the file. Any
  /// change of size or mtime, or a different expected hash, hashes again.
  /// A file rewritten with its old mtime is not detected; that is the
  /// accepted trade-off for a load that must not read hundreds of MB.
  Future<VerificationResult> verifyStamped(
    File file,
    String expectedHash,
  ) async {
    final FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException catch (e) {
      return VerificationIoError(error: e);
    }
    if (stat.type != FileSystemEntityType.file) {
      return VerificationIoError(
        error: FileSystemException('not a regular file', file.path),
      );
    }

    final modifiedMs = stat.modified.millisecondsSinceEpoch;
    final stamp = await _readStamp(file.path);
    if (stamp != null &&
        stamp.sha256 == expectedHash &&
        stamp.size == stat.size &&
        stamp.modifiedMs == modifiedMs) {
      return const VerificationOk();
    }

    final result = await verify(file, expectedHash);
    if (result is VerificationOk) {
      await _writeStamp(
        file.path,
        _VerifiedStamp(
          sha256: expectedHash,
          size: stat.size,
          modifiedMs: modifiedMs,
        ),
      );
    }
    return result;
  }

  Future<_VerifiedStamp?> _readStamp(String filePath) async {
    try {
      final json = jsonDecode(
        await File(verifiedStampPath(filePath)).readAsString(),
      );
      if (json is! Map<String, Object?>) return null;
      final sha = json['sha256'];
      final size = json['size'];
      final mtime = json['modifiedMs'];
      if (sha is! String || size is! int || mtime is! int) return null;
      return _VerifiedStamp(sha256: sha, size: size, modifiedMs: mtime);
    } on Object {
      // Missing or unreadable stamp: hash the file instead.
      return null;
    }
  }

  Future<void> _writeStamp(String filePath, _VerifiedStamp stamp) async {
    final target = verifiedStampPath(filePath);
    try {
      final tmp = File('$target.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'sha256': stamp.sha256,
          'size': stamp.size,
          'modifiedMs': stamp.modifiedMs,
        }),
        flush: true,
      );
      await tmp.rename(target);
    } on Object catch (e) {
      // A stamp is only a cache: without it the next check hashes again.
      _log.warning('Could not write verification stamp for $filePath: $e');
    }
  }
}

final class _VerifiedStamp {
  const _VerifiedStamp({
    required this.sha256,
    required this.size,
    required this.modifiedMs,
  });

  final String sha256;
  final int size;
  final int modifiedMs;
}

/// File verification service — SHA256 integrity checks for downloaded assets.
///
/// Extracted from [ModelDownloadNotifier] so that the verification logic is
/// independently testable and reusable across future download pipelines.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('FileVerification');

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

    final Digest digest;
    try {
      digest = await sha256.bind(file.openRead()).first;
    } on FileSystemException catch (e) {
      _log.warning('I/O error verifying ${file.path}: $e');
      return VerificationIoError(error: e);
    } catch (e) {
      _log.warning('Unexpected error verifying ${file.path}: $e');
      return VerificationIoError(error: e);
    }

    final actualHash = digest.toString();
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
}

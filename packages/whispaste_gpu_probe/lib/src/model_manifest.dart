/// ModelManifest — declarative model registry + on-demand acquisition.
///
/// Keeps the distributable tool bundle small: large model files are downloaded
/// on first use, verified by SHA-256, and reused on subsequent runs.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'probe_types.dart';

// ---------------------------------------------------------------------------
// ModelEntry
// ---------------------------------------------------------------------------

/// A single entry in the [ModelManifest]: all metadata needed to acquire and
/// verify one Whisper model file.
class ModelEntry {
  const ModelEntry({
    required this.name,
    required this.downloadUrl,
    required this.sha256,
    required this.targetFilename,
    required this.sizeBytes,
  });

  /// Human-readable identifier (e.g. `ggml-small-q5_1`).
  final String name;

  /// Remote location from which the model is fetched when missing/corrupt.
  final Uri downloadUrl;

  /// Expected SHA-256 digest of the model file, lower-case hex.
  final String sha256;

  /// File name written into the working directory (e.g. `ggml-small-q5_1.bin`).
  final String targetFilename;

  /// Expected file size in bytes (informational; not validated here).
  final int sizeBytes;
}

// ---------------------------------------------------------------------------
// ModelManifest
// ---------------------------------------------------------------------------

/// Registry of all known models.
///
/// In production, [entries] is populated from a bundled JSON or hardcoded
/// constants. In tests, a minimal [ModelEntry] suffices.
class ModelManifest {
  const ModelManifest({required this.entries});

  /// All models known to this manifest.
  final List<ModelEntry> entries;

  /// Looks up a model by [name]. Returns null if not found.
  ModelEntry? find(String name) {
    for (final e in entries) {
      if (e.name == name) return e;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Download seam
// ---------------------------------------------------------------------------

/// Injectable download function.
///
/// Implementations must write the downloaded bytes to [target].  On failure
/// they must throw.  Tests use fakes; production code uses an HTTP client.
typedef ModelDownloader = Future<void> Function(Uri url, File target);

// ---------------------------------------------------------------------------
// Acquisition logic
// ---------------------------------------------------------------------------

/// Ensures the model file for [entry] exists and has the correct checksum.
///
/// Returns a [CandidateResult] with [Outcome.skipped] (and a human-readable
/// [CandidateResult.errorDetail]) on any failure so callers can continue the
/// probe matrix unchanged.
///
/// On success returns null — the caller reads [entry.targetFilename] from
/// [workDir] and proceeds normally.
///
/// [downloader] is the injectable seam: pass a real HTTP downloader in
/// production and a fake in tests.
Future<CandidateResult?> acquireModel({
  required ModelEntry entry,
  required String workDir,
  required ModelDownloader downloader,

  /// Candidate id to embed in failure results (e.g. `whisper-cpp-cpu`).
  required String candidateId,
}) async {
  final target = File(p.join(workDir, entry.targetFilename));

  // --- fast path: file already present and checksum matches -----------------
  if (target.existsSync()) {
    final digest = _sha256OfFile(target);
    if (digest == entry.sha256) {
      // Reuse — do NOT call the downloader.
      return null; // success
    }
  }

  // --- slow path: download then verify --------------------------------------
  try {
    await downloader(entry.downloadUrl, target);
  } on Exception catch (e) {
    return CandidateResult(
      candidateId: candidateId,
      outcome: Outcome.failedToStart,
      errorDetail: 'Model download failed for "${entry.name}": $e',
    );
  }

  // Verify after download.
  final digest = _sha256OfFile(target);
  if (digest != entry.sha256) {
    return CandidateResult(
      candidateId: candidateId,
      outcome: Outcome.skipped,
      errorDetail:
          'Checksum mismatch for "${entry.name}": '
          'expected ${entry.sha256}, got $digest',
    );
  }

  return null; // success
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Computes the SHA-256 hex digest of [file].
String _sha256OfFile(File file) {
  final bytes = file.readAsBytesSync();
  return sha256.convert(bytes).toString();
}

/// Computes the SHA-256 hex digest of raw [bytes].
///
/// Exposed for test helpers that need to compute the expected digest.
String sha256OfBytes(Uint8List bytes) {
  return sha256.convert(bytes).toString();
}

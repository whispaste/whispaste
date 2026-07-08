/// Model registry and on-disk paths for the Parakeet (sherpa_onnx) engine.
///
/// Parakeet TDT ships as four separate files (encoder/decoder/joiner ONNX +
/// tokens.txt) rather than the single quantized GGML file whisper.cpp uses —
/// see [model_download_service.dart] for the whisper equivalent. Kept as a
/// standalone registry (not merged into that file) so the whisper-specific
/// single-file download path stays untouched.
///
/// Source: `csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8` on
/// HuggingFace — the community-maintained ONNX export of NVIDIA's
/// `parakeet-tdt-0.6b-v2` used by the sherpa-onnx project's own Dart/Flutter
/// examples (see `dart-api-examples/non-streaming-asr/bin/nemo-transducer.dart`
/// in `k2-fsa/sherpa-onnx`).
///
/// Integrity note: whisper's `sttModels` registry pins a SHA-256 per file
/// because HuggingFace's classic git-lfs backend exposes a plain SHA-256 OID.
/// This HuggingFace repo is served over HF's newer "Xet" storage backend,
/// whose `X-Linked-ETag` header is NOT a SHA-256 digest of the file bytes (it
/// is a different length/format) — verified against this repo before writing
/// this file. Hardcoding it as if it were a SHA-256 would make every
/// legitimate download fail verification. Until a reliable per-file SHA-256
/// source is confirmed, [ParakeetModelFile.sha256] is `null` and
/// [ParakeetDownloadService] falls back to a byte-size sanity check only.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../path_service.dart' show sttDir;

/// One file within the Parakeet model bundle.
class ParakeetModelFile {
  const ParakeetModelFile({
    required this.filename,
    required this.url,
    required this.sizeBytes,
    this.sha256,
  });

  final String filename;
  final String url;
  final int sizeBytes;

  /// Expected SHA-256, or `null` when unpinned (see library doc above).
  final String? sha256;
}

const String _repoBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main';

/// The four files that make up the Parakeet TDT 0.6B v2 (int8) bundle.
/// Sizes verified via HTTP HEAD against the HuggingFace repo.
const List<ParakeetModelFile> parakeetModelFiles = [
  ParakeetModelFile(
    filename: 'encoder.int8.onnx',
    url: '$_repoBase/encoder.int8.onnx',
    sizeBytes: 652184296,
  ),
  ParakeetModelFile(
    filename: 'decoder.int8.onnx',
    url: '$_repoBase/decoder.int8.onnx',
    sizeBytes: 7257753,
  ),
  ParakeetModelFile(
    filename: 'joiner.int8.onnx',
    url: '$_repoBase/joiner.int8.onnx',
    sizeBytes: 1739080,
  ),
  ParakeetModelFile(
    filename: 'tokens.txt',
    url: '$_repoBase/tokens.txt',
    sizeBytes: 308,
  ),
];

/// Total download size across all four files, for UI display.
int get parakeetModelTotalBytes =>
    parakeetModelFiles.fold(0, (sum, f) => sum + f.sizeBytes);

/// Directory the Parakeet bundle is stored in — a subdirectory of the shared
/// STT directory so it never collides with whisper's flat `ggml-*.bin` +
/// `whisper-server` layout.
String parakeetModelDir() => p.join(sttDir(), 'parakeet-tdt-0.6b-v2');

/// Full path to a bundle file by name.
String parakeetModelFilePath(String filename) =>
    p.join(parakeetModelDir(), filename);

/// Test seam — overrides the file-existence check used by
/// [parakeetModelFilesExistSync]. Production code leaves this `null`.
@visibleForTesting
bool Function(String path)? parakeetFileExistsOverride;

/// Whether every bundle file is present on disk.
bool parakeetModelFilesExistSync() {
  final checker =
      parakeetFileExistsOverride ?? (path) => File(path).existsSync();
  for (final f in parakeetModelFiles) {
    if (!checker(parakeetModelFilePath(f.filename))) return false;
  }
  return true;
}

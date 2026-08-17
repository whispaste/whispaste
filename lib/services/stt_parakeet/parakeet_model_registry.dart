/// Model registry and on-disk paths for the Parakeet (sherpa_onnx) engine.
///
/// Parakeet TDT ships as four separate files (encoder/decoder/joiner ONNX +
/// tokens.txt) rather than the single quantized GGML file whisper.cpp uses —
/// see [model_download_service.dart] for the whisper equivalent. Kept as a
/// standalone registry (not merged into that file) so the whisper-specific
/// single-file download path stays untouched.
///
/// Source: `csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` on
/// HuggingFace — the community-maintained ONNX export of NVIDIA's
/// `parakeet-tdt-0.6b-v3` used by the sherpa-onnx project's own Dart/Flutter
/// examples (see `dart-api-examples/non-streaming-asr/bin/nemo-transducer.dart`
/// in `k2-fsa/sherpa-onnx`).
///
/// v3, not v2: v2 is English-only (HuggingFace model card: "Language: en").
/// v3 is NVIDIA's multilingual follow-up (25 European languages, incl.
/// German) — the only version consistent with the app's engine-selection
/// copy ("~25 languages"), which described v3 while v2 was actually wired up
/// until 2026-07-17.
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
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main';

/// The four files that make up the Parakeet TDT 0.6B v3 (int8) bundle.
/// Sizes verified against the resolved target (`curl -sI -L`, following
/// HuggingFace's redirect — see the tokens.txt comment below for why that
/// distinction matters) on 2026-07-17.
const List<ParakeetModelFile> parakeetModelFiles = [
  ParakeetModelFile(
    filename: 'encoder.int8.onnx',
    url: '$_repoBase/encoder.int8.onnx',
    sizeBytes: 652184281,
  ),
  ParakeetModelFile(
    filename: 'decoder.int8.onnx',
    url: '$_repoBase/decoder.int8.onnx',
    sizeBytes: 11845275,
  ),
  ParakeetModelFile(
    filename: 'joiner.int8.onnx',
    url: '$_repoBase/joiner.int8.onnx',
    sizeBytes: 6355277,
  ),
  ParakeetModelFile(
    filename: 'tokens.txt',
    url: '$_repoBase/tokens.txt',
    // HuggingFace's resolve/main URL 307-redirects to the real file; the
    // redirect response itself carries a small Content-Length (308 for the
    // v2 repo) that is NOT the file's size — must follow the redirect
    // (`curl -sI -L`) to measure the real target. Got this wrong once
    // already for the v2 registry (fixed in commit aa8fd511).
    sizeBytes: 93939,
  ),
];

/// Test seam — overrides [parakeetModelFiles] for [ParakeetDownloadNotifier].
/// Production code leaves this `null`. The real bundle files are
/// multi-hundred-MB, so tests exercising the full download loop substitute a
/// small fake list here instead of writing real-sized fixtures to disk.
@visibleForTesting
List<ParakeetModelFile>? parakeetModelFilesOverride;

/// The bundle file list [ParakeetDownloadNotifier] should download —
/// [parakeetModelFilesOverride] in tests, [parakeetModelFiles] otherwise.
List<ParakeetModelFile> effectiveParakeetModelFiles() =>
    parakeetModelFilesOverride ?? parakeetModelFiles;

/// Total download size across all four files, for UI display.
int get parakeetModelTotalBytes =>
    parakeetModelFiles.fold(0, (sum, f) => sum + f.sizeBytes);

/// Human-readable total bundle size (e.g. `"631 MB"`), formatted with the
/// same 1024-based rule as `SttModelInfo.sizeLabel` in
/// `model_download_service.dart` so whisper and Parakeet size labels never
/// look inconsistent side by side.
String get parakeetModelSizeLabel {
  final bytes = parakeetModelTotalBytes;
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).round()} MB';
}

/// ISO 639-1 codes for the 25 European languages `parakeet-tdt-0.6b-v3`
/// supports, per the NVIDIA model card (huggingface.co/nvidia/parakeet-tdt-0.6b-v3,
/// verified 2026-07-28). Used by [recommendEngine] (`engine_recommendation.dart`)
/// to decide whether Parakeet is even eligible for a given dictation language —
/// Parakeet is faster than Whisper on every machine, so language (not
/// hardware) is the only thing that can rule it out.
const Set<String> parakeetSupportedLanguages = {
  'bg', // Bulgarian
  'hr', // Croatian
  'cs', // Czech
  'da', // Danish
  'nl', // Dutch
  'en', // English
  'et', // Estonian
  'fi', // Finnish
  'fr', // French
  'de', // German
  'el', // Greek
  'hu', // Hungarian
  'it', // Italian
  'lv', // Latvian
  'lt', // Lithuanian
  'mt', // Maltese
  'pl', // Polish
  'pt', // Portuguese
  'ro', // Romanian
  'sk', // Slovak
  'sl', // Slovenian
  'es', // Spanish
  'sv', // Swedish
  'ru', // Russian
  'uk', // Ukrainian
};

/// The (only) Parakeet model's identity — used both as the on-disk bundle
/// directory name and as the persisted `model` value for history/analytics
/// entries transcribed with the Parakeet engine (see
/// `AppSettings.transcriptionModelId`). Parakeet has no quality tiers, unlike
/// the three whisper IDs in [sttModels].
const String parakeetModelId = 'parakeet-tdt-0.6b-v3';

/// Directory the Parakeet bundle is stored in — a subdirectory of the shared
/// STT directory so it never collides with whisper's flat `ggml-*.bin` +
/// `whisper-server` layout.
String parakeetModelDir() => p.join(sttDir(), parakeetModelId);

/// Full path to a bundle file by name.
String parakeetModelFilePath(String filename) =>
    p.join(parakeetModelDir(), filename);

/// Test seam — overrides the file-existence check used by
/// [parakeetModelFilesExistSync]. Production code leaves this `null`.
@visibleForTesting
bool Function(String path)? parakeetFileExistsOverride;

/// Whether every bundle file is present on disk.
///
/// Deliberately checks the real [parakeetModelFiles] list, not
/// [effectiveParakeetModelFiles] — this "already installed?" guard must
/// reflect the real bundle regardless of [parakeetModelFilesOverride], so a
/// test substituting a fake file list for `downloadBundle()`'s download loop
/// doesn't also fake out its own already-installed check. In production
/// [parakeetModelFilesOverride] is always `null`, so the two lists are
/// identical and this distinction has no runtime effect.
bool parakeetModelFilesExistSync() {
  final checker =
      parakeetFileExistsOverride ?? (path) => File(path).existsSync();
  for (final f in parakeetModelFiles) {
    if (!checker(parakeetModelFilePath(f.filename))) return false;
  }
  return true;
}

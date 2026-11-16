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
/// Integrity: every file pins its SHA-256. The value is the `lfs.oid` of the
/// HuggingFace tree API (`/api/models/<repo>/tree/main`), which is the SHA-256
/// of the file content even though the repo is served over HF's Xet storage.
/// Verified 2026-10-17 by downloading decoder and joiner and hashing them;
/// they matched the tree API byte for byte. `tokens.txt` is not LFS and was
/// hashed from the downloaded file.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../path_service.dart' show sttDir;

final _log = AppLogger('ParakeetRegistry');

/// One file within the Parakeet model bundle.
class ParakeetModelFile {
  const ParakeetModelFile({
    required this.filename,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    this.mirrorUrls = const [],
  });

  final String filename;

  /// Primary source, pinned to one Hugging Face commit.
  final String url;
  final int sizeBytes;

  /// Lower-case hex SHA-256 of the file (see library doc above).
  final String sha256;

  /// Further sources of the identical file, tried in order after [url]
  /// fails (`HttpModelFetcher.fetchVerified`), each checked against [sha256].
  final List<String> mirrorUrls;

  /// [url] followed by [mirrorUrls].
  List<String> get sources => [url, ...mirrorUrls];
}

/// Pinned to one commit of the repo (OW-P18): the file SHA-256 values below are
/// the LFS hashes at this commit (checked 2026-10-19 via the HF API).
const String _repoBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/2bda32ec70b097a55adaa07d9a7173915b43cc78';

/// The four files that make up the Parakeet TDT 0.6B v3 (int8) bundle.
/// Sizes verified against the resolved target (`curl -sI -L`, following
/// HuggingFace's redirect — see the tokens.txt comment below for why that
/// distinction matters) on 2026-07-17. SHA-256 values: see library doc.
const List<ParakeetModelFile> parakeetModelFiles = [
  ParakeetModelFile(
    filename: 'encoder.int8.onnx',
    url: '$_repoBase/encoder.int8.onnx',
    sizeBytes: 652184281,
    sha256: 'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
  ),
  ParakeetModelFile(
    filename: 'decoder.int8.onnx',
    url: '$_repoBase/decoder.int8.onnx',
    sizeBytes: 11845275,
    sha256: '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
  ),
  ParakeetModelFile(
    filename: 'joiner.int8.onnx',
    url: '$_repoBase/joiner.int8.onnx',
    sizeBytes: 6355277,
    sha256: '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
  ),
  ParakeetModelFile(
    filename: 'tokens.txt',
    url: '$_repoBase/tokens.txt',
    // HuggingFace's resolve URL 307-redirects to the real file; the
    // redirect response itself carries a small Content-Length (308 for the
    // v2 repo) that is NOT the file's size — must follow the redirect
    // (`curl -sI -L`) to measure the real target. Got this wrong once
    // already for the v2 registry (fixed in commit aa8fd511).
    sizeBytes: 93939,
    sha256: 'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
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

/// Whether every bundle file is present on disk with its pinned size.
///
/// Deliberately checks the real [parakeetModelFiles] list, not
/// [effectiveParakeetModelFiles] — this "already installed?" guard must
/// reflect the real bundle regardless of [parakeetModelFilesOverride], so a
/// test substituting a fake file list for `downloadBundle()`'s download loop
/// doesn't also fake out its own already-installed check. In production
/// [parakeetModelFilesOverride] is always `null`, so the two lists are
/// identical and this distinction has no runtime effect.
bool parakeetModelFilesExistSync() {
  final checker = parakeetFileExistsOverride;
  if (checker == null) {
    return parakeetBundleCompleteIn(parakeetModelDir(), parakeetModelFiles);
  }
  for (final f in parakeetModelFiles) {
    if (!checker(parakeetModelFilePath(f.filename))) return false;
  }
  return true;
}

/// Folder names people use when they install the bundle by hand: the
/// Hugging Face repository name and a shortened form of it (seen in user
/// reports for 1.4.2). The app only ever reads [parakeetModelId].
const List<String> parakeetMisplacedDirNames = [
  'parakeet-tdt-0.6b-v3-int8',
  'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
];

/// Moves bundle files that were put into a [parakeetMisplacedDirNames]
/// folder next to [dir] into [dir], if they have their pinned size and [dir]
/// lacks them. Returns the names moved; the caller must check their SHA-256
/// (`ParakeetDownloadNotifier.downloadBundle` does) before they count.
List<String> adoptMisplacedParakeetFiles(
  String dir,
  List<ParakeetModelFile> files,
) {
  final moved = <String>[];
  final parent = p.dirname(dir);
  for (final name in parakeetMisplacedDirNames) {
    final other = p.join(parent, name);
    if (!Directory(other).existsSync()) continue;
    for (final file in files) {
      if (parakeetBundleFileCompleteIn(dir, file)) continue;
      if (!parakeetBundleFileCompleteIn(other, file)) continue;
      try {
        Directory(dir).createSync(recursive: true);
        final target = File(p.join(dir, file.filename));
        if (target.existsSync()) target.deleteSync();
        File(p.join(other, file.filename)).renameSync(target.path);
        moved.add(file.filename);
      } on FileSystemException catch (e) {
        // Another volume or a locked file: the download fetches it instead.
        _log.info('Parakeet file ${file.filename} not adopted from $name: $e');
      }
    }
  }
  return moved;
}

/// Whether [file] lies in [dir] with its pinned size. A file of the right
/// name but another size (a hand-placed file from another export, a cut-off
/// copy) is not the bundle file: it counts as missing, so the download
/// replaces it instead of the engine failing on load (#1546). One `stat`
/// per file, cheap enough for the dictation path.
bool parakeetBundleFileCompleteIn(String dir, ParakeetModelFile file) {
  final f = File(p.join(dir, file.filename));
  try {
    return f.statSync().type == FileSystemEntityType.file &&
        f.lengthSync() == file.sizeBytes;
  } on FileSystemException {
    return false;
  }
}

/// Whether every one of [files] is complete in [dir], see
/// [parakeetBundleFileCompleteIn].
bool parakeetBundleCompleteIn(String dir, List<ParakeetModelFile> files) =>
    files.every((f) => parakeetBundleFileCompleteIn(dir, f));

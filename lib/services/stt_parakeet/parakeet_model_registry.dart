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
/// Integrity: size, SHA-256 and sources of every file are pinned in the
/// bundled model catalog (`lib/core/models/bundled_model_catalog.dart`).
library;

export '../../core/models/bundled_model_catalog.dart'
    show parakeetSupportedLanguages;
export '../../core/models/model_catalog.dart' show ModelFile;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/models/bundled_model_catalog.dart';
import '../../core/models/model_catalog.dart';
import '../path_service.dart' show sttDir;
import '../stt_sherpa/sherpa_provider_policy.dart';
import '../model_install_check.dart';

final _log = AppLogger('ParakeetRegistry');

/// One file within the Parakeet model bundle, as pinned in the catalog.
typedef ParakeetModelFile = ModelFile;

/// The four files that make up the Parakeet TDT 0.6B v3 (int8) bundle, read
/// from the bundled catalog (`bundled_model_catalog.dart`, pins and their
/// history there).
final List<ParakeetModelFile> parakeetModelFiles = bundledModelCatalog
    .byId(CatalogIds.parakeet)
    .files;

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

/// The (only) Parakeet model's identity — used both as the on-disk bundle
/// directory name and as the persisted `model` value for history/analytics
/// entries transcribed with the Parakeet engine (see
/// `AppSettings.transcriptionModelId`). Parakeet has no quality tiers, unlike
/// the three whisper IDs in [sttModels].
const String parakeetModelId = CatalogIds.parakeet;

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
  return fileHasPinnedSizeSync(p.join(dir, file.filename), file.sizeBytes);
}

/// Whether every one of [files] is complete in [dir], see
/// [parakeetBundleFileCompleteIn].
bool parakeetBundleCompleteIn(String dir, List<ParakeetModelFile> files) =>
    files.every((f) => parakeetBundleFileCompleteIn(dir, f));

/// Release gate: only providers with a measured speedup for these exact int8
/// files belong here. See benchmarks/sherpa_gpu; unmeasured providers use CPU.
const Set<SherpaProvider> parakeetSherpaFasterProviders = {};

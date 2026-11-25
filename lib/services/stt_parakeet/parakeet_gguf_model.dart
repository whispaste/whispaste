/// GGUF model for the GPU Parakeet engine (libparakeet).
///
/// Source: `ggml-org/parakeet-GGUF` on HuggingFace, the official ggml-org
/// conversion of `nvidia/parakeet-tdt-0.6b-v3` (CC-BY-4.0, see NOTICE). Size,
/// SHA-256 and the pinned revision live in the bundled model catalog
/// (`lib/core/models/bundled_model_catalog.dart`).
///
/// Integrity: [verifyParakeetGguf] checks the exact size and the SHA-256 before
/// every load. The hash is cached as a stamp per file version, so only the first
/// load of a new file hashes it. A truncated or corrupt GGUF makes ggml's Metal
/// backend abort the process (`GGML_ASSERT ggml-metal-device.m`), so this check
/// is mandatory. The download also refuses any file whose size differs.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/models/bundled_model_catalog.dart';
import '../file_verification_service.dart';
import '../http_model_fetcher.dart';
import 'parakeet_model_registry.dart' show parakeetModelDir;

/// Quantisation used for the GPU engine. q8_0 was the accuracy/size
/// compromise in the M5 measurements. Change this constant to switch variants.
const ParakeetGgufQuant parakeetGgufDefaultQuant = ParakeetGgufQuant.q8Zero;

/// The GGUF variants of Parakeet TDT 0.6B v3 that can be loaded.
enum ParakeetGgufQuant {
  /// 8-bit, default. About 0.84 GB resident on Metal.
  q8Zero('q8_0'),

  /// Half precision, the reference for quality. About 1.4 GB resident.
  f16('f16');

  const ParakeetGgufQuant(this.tag);

  /// Tag used in the GGUF file name (`ggml-parakeet-tdt-0.6b-v3-<tag>.bin`).
  final String tag;

  /// ID of this variant in the bundled model catalog.
  String get catalogId => switch (this) {
    ParakeetGgufQuant.q8Zero => CatalogIds.parakeetGgufQ8,
    ParakeetGgufQuant.f16 => CatalogIds.parakeetGgufF16,
  };
}

class ParakeetGgufFile {
  const ParakeetGgufFile({
    required this.quant,
    required this.sizeBytes,
    required this.sha256,
    this.sources = const [],
  });

  /// The entry of [quant] in the bundled model catalog.
  factory ParakeetGgufFile.fromCatalog(ParakeetGgufQuant quant) {
    final file = bundledModelCatalog.byId(quant.catalogId).file;
    return ParakeetGgufFile(
      quant: quant,
      sizeBytes: file.sizeBytes,
      sha256: file.sha256,
      sources: file.sources,
    );
  }

  final ParakeetGgufQuant quant;
  final int sizeBytes;

  /// Lower-case hex SHA-256 of the whole file.
  final String sha256;

  /// Public sources of the identical file, tried in order
  /// (`HttpModelFetcher.fetchVerified`), each checked against [sha256].
  final List<String> sources;

  String get filename => 'ggml-parakeet-tdt-0.6b-v3-${quant.tag}.bin';
}

/// Pinned GGUF files, keyed by quant, read from the bundled model catalog.
final Map<ParakeetGgufQuant, ParakeetGgufFile> parakeetGgufFiles = {
  for (final q in ParakeetGgufQuant.values) q: ParakeetGgufFile.fromCatalog(q),
};

/// The pinned file for [parakeetGgufDefaultQuant].
ParakeetGgufFile get parakeetGgufActive =>
    parakeetGgufFiles[parakeetGgufDefaultQuant]!;

/// Absolute path of the active GGUF file, next to the sherpa bundle.
String parakeetGgufPath([ParakeetGgufFile? file]) =>
    p.join(parakeetModelDir(), (file ?? parakeetGgufActive).filename);

/// Outcome of a model check. Anything other than [ok] must never reach the
/// native loader.
enum ParakeetGgufCheck { ok, missing, sizeMismatch, hashMismatch }

/// Verifies the file at [path] against [expected]. The exact size is checked
/// first; the SHA-256 is only computed once per file version (see
/// [FileVerificationService.verifyStamped]), so later loads stay fast.
Future<ParakeetGgufCheck> verifyParakeetGguf(
  String path,
  ParakeetGgufFile expected,
) async {
  final file = File(path);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) return ParakeetGgufCheck.missing;
  if (stat.size != expected.sizeBytes) return ParakeetGgufCheck.sizeMismatch;
  final result = await const FileVerificationService().verifyStamped(
    file,
    expected.sha256,
  );
  return switch (result) {
    VerificationOk() => ParakeetGgufCheck.ok,
    VerificationMismatch() => ParakeetGgufCheck.hashMismatch,
    VerificationIoError() => ParakeetGgufCheck.missing,
  };
}

/// Downloads the active GGUF into the Parakeet model directory, source after
/// source, and checks size and SHA-256 right away
/// ([HttpModelFetcher.fetchVerified]); a file that fails is deleted. The
/// hash stamp it writes lets [verifyParakeetGguf] skip the hash on load.
Future<void> downloadParakeetGguf({
  required HttpModelFetcher fetcher,
  void Function(FetchProgress)? onProgress,
  void Function()? onVerifying,
  ParakeetGgufFile? file,
}) async {
  final target = file ?? parakeetGgufActive;
  final dest = parakeetGgufPath(target);
  Directory(p.dirname(dest)).createSync(recursive: true);
  await fetcher.fetchVerified(
    sources: target.sources,
    destPath: dest,
    expectedSize: target.sizeBytes,
    expectedSha256: target.sha256,
    onProgress: onProgress,
    onVerifying: onVerifying,
  );
}

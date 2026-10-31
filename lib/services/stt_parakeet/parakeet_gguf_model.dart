/// GGUF model for the GPU Parakeet engine (libparakeet).
///
/// Source: `ggml-org/parakeet-GGUF` on HuggingFace, the official ggml-org
/// conversion of `nvidia/parakeet-tdt-0.6b-v3` (CC-BY-4.0, see NOTICE). The
/// file is pinned to one repository revision and to its LFS SHA-256, both
/// taken from the HuggingFace tree API (`/api/models/ggml-org/parakeet-GGUF/tree/main`).
/// The f16 file was also reproduced locally from the NeMo checkpoint and
/// matches the upstream SHA-256 byte for byte.
///
/// Integrity: [verifyParakeetGguf] checks the SHA-256 before every load. A
/// truncated or corrupt GGUF makes ggml's Metal backend abort the process
/// (`GGML_ASSERT ggml-metal-device.m`), so this check is mandatory and not an
/// optimisation. The download also refuses any file whose size differs.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../http_model_fetcher.dart';
import 'parakeet_model_registry.dart' show parakeetModelDir;

/// Quantisation used for the GPU engine. q8_0 was the accuracy/size
/// compromise in the M5 measurements (see the benchmark note in
/// `internal-notes`). Change this constant to switch variants.
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
}

class ParakeetGgufFile {
  const ParakeetGgufFile({
    required this.quant,
    required this.sizeBytes,
    required this.sha256,
  });

  final ParakeetGgufQuant quant;
  final int sizeBytes;

  /// Lower-case hex SHA-256 of the whole file.
  final String sha256;

  String get filename => 'ggml-parakeet-tdt-0.6b-v3-${quant.tag}.bin';

  /// Pinned repository revision of `ggml-org/parakeet-GGUF`.
  static const String revision = '35156454d1a39de06863303dd209fd2bed6ee079';

  String get url =>
      'https://huggingface.co/ggml-org/parakeet-GGUF/resolve/$revision/$filename';
}

/// Pinned GGUF files, keyed by quant. Sizes and hashes come from the HF tree.
const Map<ParakeetGgufQuant, ParakeetGgufFile> parakeetGgufFiles = {
  ParakeetGgufQuant.q8Zero: ParakeetGgufFile(
    quant: ParakeetGgufQuant.q8Zero,
    sizeBytes: 668757119,
    sha256: '4d64e9e96c2792186d072fde0034df0ad670cf680a2f53069052ead827fd600e',
  ),
  ParakeetGgufQuant.f16: ParakeetGgufFile(
    quant: ParakeetGgufQuant.f16,
    sizeBytes: 1255897319,
    sha256: '833bffc9513b2cae867ee9e51633cfd11e4d51aaa5597c8ac02159385a2b426f',
  ),
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

/// Verifies the file at [path] against [expected]. The hash runs in a
/// background isolate: `package:crypto` is pure Dart and needs seconds for
/// the ~670 MB file, which must not block the UI isolate.
Future<ParakeetGgufCheck> verifyParakeetGguf(
  String path,
  ParakeetGgufFile expected,
) async {
  final file = File(path);
  if (!file.existsSync()) return ParakeetGgufCheck.missing;
  if (file.lengthSync() != expected.sizeBytes) {
    return ParakeetGgufCheck.sizeMismatch;
  }
  final digest = await Isolate.run(() => _sha256OfFile(path));
  return digest == expected.sha256
      ? ParakeetGgufCheck.ok
      : ParakeetGgufCheck.hashMismatch;
}

Future<String> _sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// Downloads the active GGUF into the Parakeet model directory. A size
/// mismatch after download deletes the file so a retry starts clean. The
/// hash is checked by [verifyParakeetGguf] before each load, not here.
Future<void> downloadParakeetGguf({
  required HttpModelFetcher fetcher,
  void Function(FetchProgress)? onProgress,
  ParakeetGgufFile? file,
}) async {
  final target = file ?? parakeetGgufActive;
  final dest = parakeetGgufPath(target);
  Directory(p.dirname(dest)).createSync(recursive: true);
  await fetcher.fetch(
    url: target.url,
    destPath: dest,
    expectedSize: target.sizeBytes,
    onProgress: onProgress,
  );
  if (File(dest).lengthSync() != target.sizeBytes) {
    File(dest).deleteSync();
    throw StateError('parakeet_gguf_size_mismatch');
  }
}

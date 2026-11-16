/// ModelStore — the on-device model test bench: a catalogue of Whisper models
/// the user can download on demand (incl. larger ones), tracked by local state
/// and downloaded with live progress.
///
/// The distributable tool stays small; models are fetched into a local models
/// directory on demand and reused afterwards. This is the "Modell" axis of the
/// engine × model test matrix — the UI lists the catalogue, shows download
/// progress, and the live test runs a chosen engine against a chosen model.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;

import 'model_manifest.dart';

/// Download state of one catalogue model.
enum ModelState { absent, downloading, present, error }

/// Progress-reporting download seam.
///
/// Implementations stream [url] into [target] and call [onProgress] with the
/// bytes received so far and the total size (`-1` when the server omits
/// Content-Length). They must throw on failure. Tests inject a fake.
typedef ProgressDownloader =
    Future<void> Function(
      Uri url,
      File target,
      void Function(int received, int total) onProgress,
    );

/// One file of a multi-file model bundle (e.g. a sherpa-onnx encoder/decoder/
/// tokens triple). Bundle files are downloaded into a per-model subdirectory.
class BundleFile {
  const BundleFile({
    required this.url,
    required this.filename,
    required this.sizeBytes,
    this.sha256 = '',
  });

  /// Source URL, pinned to one repository commit.
  final Uri url;

  /// Lower-case hex SHA-256 the downloaded file must match; empty skips the
  /// check (only for files whose upstream has no pinned copy).
  final String sha256;

  /// Target filename inside the model's bundle directory.
  final String filename;

  /// Exact size in bytes at the pinned commit (display + progress fallback).
  final int sizeBytes;
}

/// One catalogue model: display metadata plus the fetch spec.
///
/// A model is either **single-file** (one [entry], stored directly in the
/// models directory — GGML/ONNX-Whisper/wav2vec2) or a **bundle** ([files],
/// downloaded into `models/<id>/` — sherpa-onnx). Exactly one of the two is
/// set.
class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.label,
    required this.family,
    this.entry,
    this.files,
  }) : assert(
         (entry == null) != (files == null),
         'Exactly one of entry / files must be set',
       );

  /// Stable identifier used in the UI / API (e.g. `ggml-small`).
  final String id;

  /// Human label shown in the UI (e.g. `Small · 466 MB · gut/schnell`).
  final String label;

  /// Model family this model belongs to — must match a [ProbeEngine.modelFamily]
  /// (`ggml`, `onnx-whisper`, `onnx-wav2vec2`, `sherpa-onnx`). Determines which
  /// engines can run it in the live test.
  final String family;

  /// Single-file fetch metadata (URL, target filename, size, checksum), or null
  /// for bundle models.
  final ModelEntry? entry;

  /// Bundle files downloaded into `models/<id>/`, or null for single-file models.
  final List<BundleFile>? files;

  /// True when this model is a multi-file bundle.
  bool get isBundle => files != null;

  /// Total on-disk size used for display + progress-bar fallback.
  int get totalSizeBytes => isBundle
      ? files!.fold(0, (sum, f) => sum + f.sizeBytes)
      : entry!.sizeBytes;
}

/// The default multi-family model catalogue — the PRD's model axis.
///
/// - `ggml`         : whisper.cpp + Const-me (GGML .bin, ggerganov/whisper.cpp)
/// - `onnx-whisper` : ONNX Runtime + DirectML Whisper-ONNX (onnx-community/…)
/// - `onnx-wav2vec2`: non-Whisper German wav2vec2 ONNX (jonatasgrosman/…)
///
/// Sizes are approximate on-disk sizes for display + download progress.
List<CatalogModel> defaultModelCatalog() {
  // Every repository is pinned to one commit, sizes and SHA-256 are the
  // values at that commit (HF tree API `lfs.oid`, small non-LFS files hashed
  // after download; 2026-11-16). `resolve/main` would follow whatever the
  // upstream pushes next, which broke the app's Parakeet download once.
  CatalogModel make(
    String id,
    String family,
    Uri url,
    String file,
    int bytes,
    String label, {
    String sha256 = '',
  }) => CatalogModel(
    id: id,
    label: label,
    family: family,
    entry: ModelEntry(
      name: id,
      downloadUrl: url,
      sha256: sha256,
      targetFilename: file,
      sizeBytes: bytes,
    ),
  );
  Uri ggmlUrl(String file) => Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
    '5359861c739e955e79d9a303bcbc70fb988958b1/$file',
  );
  // sherpa-onnx Whisper bundle: encoder + decoder + tokens (int8) downloaded
  // into models/<id>/. Sizes are the real Hugging Face file sizes.
  const sherpaRevisions = {
    'tiny': '65176e2deb88badc814a94058666cadccc29b61c',
    'base': 'bb53ee204431c90d314c1cc08d28d23e5b7927cc',
    'small': '8f3c18b358db4d1f2fc1eae49d75cd20989e4309',
    'medium': '8c31d28503847560985df21f90e14f0c736e075e',
  };
  CatalogModel sherpa(
    String size,
    (int, String) enc,
    (int, String) dec,
    String label,
  ) {
    Uri u(String f) => Uri.parse(
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-$size'
      '/resolve/${sherpaRevisions[size]}/$f',
    );
    const tokens = 816730;
    return CatalogModel(
      id: 'sherpa-whisper-$size',
      label: label,
      family: 'sherpa-onnx',
      files: [
        BundleFile(
          url: u('$size-encoder.int8.onnx'),
          filename: '$size-encoder.int8.onnx',
          sizeBytes: enc.$1,
          sha256: enc.$2,
        ),
        BundleFile(
          url: u('$size-decoder.int8.onnx'),
          filename: '$size-decoder.int8.onnx',
          sizeBytes: dec.$1,
          sha256: dec.$2,
        ),
        BundleFile(
          url: u('$size-tokens.txt'),
          filename: '$size-tokens.txt',
          sizeBytes: tokens,
          sha256:
              'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
        ),
      ],
    );
  }

  // ONNX Runtime + DirectML Whisper bundle: encoder + decoder (int8) +
  // tokenizer downloaded into models/<id>/. The onnx-directml runner resolves
  // encoder_model_int8.onnx / decoder_model_int8.onnx / tokenizer.json inside
  // that dir. Source is the public onnx-community export — Microsoft's
  // whisper-*-directml repos went private (HTTP 401), so the old single-file
  // catalogue entries no longer resolve.
  const onnxcRevisions = {
    'base': '27a07b4b52b3a4c5886134bb4320e93e1a4bbc7c',
    'small': '36050c46d777d46dc4b5f43f6d90574fc38f8732',
  };
  CatalogModel onnxc(
    String size,
    (int, String) enc,
    (int, String) dec,
    String label,
  ) {
    Uri u(String f) => Uri.parse(
      'https://huggingface.co/onnx-community/whisper-$size'
      '/resolve/${onnxcRevisions[size]}/$f',
    );
    const tokenizer = 2480466; // tokenizer.json is identical across sizes
    return CatalogModel(
      id: 'onnx-whisper-$size',
      label: label,
      family: 'onnx-whisper',
      files: [
        BundleFile(
          url: u('onnx/encoder_model_int8.onnx'),
          filename: 'encoder_model_int8.onnx',
          sizeBytes: enc.$1,
          sha256: enc.$2,
        ),
        BundleFile(
          url: u('onnx/decoder_model_int8.onnx'),
          filename: 'decoder_model_int8.onnx',
          sizeBytes: dec.$1,
          sha256: dec.$2,
        ),
        BundleFile(
          url: u('tokenizer.json'),
          filename: 'tokenizer.json',
          sizeBytes: tokenizer,
          sha256:
              '27fc476bfe7f17299480be2273fc0608e4d5a99aba2ab5dec5374b4482d1a566',
        ),
      ],
    );
  }

  // CTranslate2 Whisper bundle for faster-whisper: model.bin + config.json +
  // tokenizer.json + vocabulary.txt downloaded into models/<id>/. The id is
  // `faster-whisper-<size>` on purpose — Purfview's standalone resolves a model
  // as `<model_dir>/faster-whisper-<name>`, so the bundle dir name IS the lookup
  // key (see FasterWhisperCandidate).
  const ct2Revisions = {
    'base': 'ebe41f70d5b6dfa9166e2c581c45c9c0cfc57b66',
    'small': '536b0662742c02347bc0e980a01041f333bce120',
  };
  // config.json differs per size (size, hash); model.bin is passed in.
  const ct2Config = {
    'base': (
      2309,
      '56a6d8110d311f19c8f0471e562832c7527f146b567275bfca59fcf7c184da9a',
    ),
    'small': (
      2370,
      'b55496ac7940a7ae47d2c01eab40edfd8701feec1229d9cce3b40014383fb828',
    ),
  };
  CatalogModel ct2(String size, (int, String) modelBin, String label) {
    Uri u(String f) => Uri.parse(
      'https://huggingface.co/Systran/faster-whisper-$size'
      '/resolve/${ct2Revisions[size]}/$f',
    );
    // tokenizer.json / vocabulary.txt are identical across sizes.
    return CatalogModel(
      id: 'faster-whisper-$size',
      label: label,
      family: 'ct2-whisper',
      files: [
        BundleFile(
          url: u('model.bin'),
          filename: 'model.bin',
          sizeBytes: modelBin.$1,
          sha256: modelBin.$2,
        ),
        BundleFile(
          url: u('config.json'),
          filename: 'config.json',
          sizeBytes: ct2Config[size]!.$1,
          sha256: ct2Config[size]!.$2,
        ),
        BundleFile(
          url: u('tokenizer.json'),
          filename: 'tokenizer.json',
          sizeBytes: 2203239,
          sha256:
              'fb7b63191e9bb045082c79fd742a3106a12c99513ab30df4a0d47fa6cb6fd0ab',
        ),
        BundleFile(
          url: u('vocabulary.txt'),
          filename: 'vocabulary.txt',
          sizeBytes: 459861,
          sha256:
              '34ce3fe1c5041027b3f8d42912270993f986dbc4bb34cf27f951e34a1e453913',
        ),
      ],
    );
  }

  return [
    // GGML — whisper.cpp + Const-me.
    make(
      'ggml-tiny',
      'ggml',
      ggmlUrl('ggml-tiny.bin'),
      'ggml-tiny.bin',
      77691713,
      'Tiny · ~75 MB · sehr schnell',
      sha256:
          'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
    ),
    make(
      'ggml-base',
      'ggml',
      ggmlUrl('ggml-base.bin'),
      'ggml-base.bin',
      147951465,
      'Base · ~141 MB · schnell',
      sha256:
          '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    ),
    make(
      'ggml-small',
      'ggml',
      ggmlUrl('ggml-small.bin'),
      'ggml-small.bin',
      487601967,
      'Small · ~465 MB · ausgewogen',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
    ),
    make(
      'ggml-medium',
      'ggml',
      ggmlUrl('ggml-medium.bin'),
      'ggml-medium.bin',
      1533763059,
      'Medium · ~1,5 GB · genau',
      sha256:
          '6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208',
    ),
    make(
      'ggml-large-v3',
      'ggml',
      ggmlUrl('ggml-large-v3.bin'),
      'ggml-large-v3.bin',
      3095033483,
      'Large v3 · ~2,9 GB · höchste Qualität',
      sha256:
          '64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2',
    ),
    // ONNX Whisper — ONNX Runtime + DirectML (onnx-community export).
    onnxc(
      'base',
      (
        23201297,
        'ca6177401f86a2c6b4dc5f7fc02fbca680678906bd0c22f6d89f0b80f124253f',
      ),
      (
        53310178,
        'c859636f4463dd5a9ea752546c6c7badeb48ab3e22b340cafef08a15552fcb2e',
      ),
      'Whisper Base (ONNX int8, DirectML) · ~78 MB · schnell',
    ),
    onnxc(
      'small',
      (
        92326127,
        '2601c9eb2d345c5916d4576d36f663a7c96589740fb2273828c48c3fc2c7db75',
      ),
      (
        155989346,
        '0486afa8eb464bf2210d07aca0cb3f5d91d3f2f01cbe47f9f1e6ff9122abaaf6',
      ),
      'Whisper Small (ONNX int8, DirectML) · ~243 MB · ausgewogen',
    ),
    // Non-Whisper — German wav2vec2 (ONNX).
    make(
      'wav2vec2-de-xlsr53',
      'onnx-wav2vec2',
      Uri.parse(
        // The repository has no ONNX export at any commit (checked
        // 2026-11-16, HTTP 404); pinned so it cannot silently change.
        'https://huggingface.co/jonatasgrosman/wav2vec2-large-xlsr-53-german'
        '/resolve/4b8a02957378d0f2da2ef74091156b032c485a89/model.onnx',
      ),
      'wav2vec2-large-xlsr-53-german.onnx',
      1180000000,
      'wav2vec2 XLSR-53 Deutsch (ONNX) · ~1,18 GB',
    ),
    // sherpa-onnx (k2-fsa) — multilingual Whisper-ONNX bundles, CPU EP.
    sherpa(
      'tiny',
      (
        12937772,
        'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434',
      ),
      (
        89855401,
        'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925',
      ),
      'sherpa-onnx Whisper Tiny (int8) · ~103 MB · sehr schnell',
    ),
    sherpa(
      'base',
      (
        29120534,
        '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
      ),
      (
        130672026,
        '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
      ),
      'sherpa-onnx Whisper Base (int8) · ~161 MB · schnell',
    ),
    sherpa(
      'small',
      (
        112442483,
        '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
      ),
      (
        262226114,
        'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
      ),
      'sherpa-onnx Whisper Small (int8) · ~376 MB · ausgewogen',
    ),
    sherpa(
      'medium',
      (
        374196283,
        '1c54582b4d829de0089f6cb63bbbdb3bf7555398bacaf855fbecf1a84dfd193e',
      ),
      (
        571059257,
        '595d00a338a365a7bfa0ca7f296cabc639583bef770ab6130df90f49a6412747',
      ),
      'sherpa-onnx Whisper Medium (int8) · ~946 MB · genau',
    ),
    // CTranslate2 — faster-whisper (Purfview standalone), CPU + CUDA.
    ct2('base', (
      145217532,
      'd01c3014881c9c6f3133c182f3d2887eb6ca1c789a7538c5c007196857a0a6a9',
    ), 'faster-whisper Base (CT2) · ~148 MB · schnell'),
    ct2('small', (
      483546902,
      '3e305921506d8872816023e4c273e75d2419fb89b24da97b4fe7bce14170d671',
    ), 'faster-whisper Small (CT2) · ~466 MB · ausgewogen'),
  ];
}

/// Mutable per-model state held by the [ModelStore].
class _Entry {
  _Entry(this.model);
  final CatalogModel model;
  ModelState state = ModelState.absent;
  int received = 0;
  int total = 0;
  String? error;
}

/// Owns the models directory and the catalogue state machine.
class ModelStore {
  ModelStore({
    required this.directory,
    List<CatalogModel>? catalog,
    ProgressDownloader? downloader,
  }) : catalog = catalog ?? defaultModelCatalog(),
       _downloader = downloader ?? httpProgressDownloader {
    for (final m in this.catalog) {
      _entries[m.id] = _Entry(m);
    }
    _rescan();
  }

  /// Absolute path of the models directory (created on first download).
  final String directory;

  /// The catalogue, in display order.
  final List<CatalogModel> catalog;

  final ProgressDownloader _downloader;
  final Map<String, _Entry> _entries = {};

  /// Re-checks the directory and marks models present when their file exists.
  void _rescan() {
    for (final e in _entries.values) {
      if (e.state == ModelState.downloading) continue;
      final m = e.model;
      if (m.isBundle) {
        final dir = Directory(p.join(directory, m.id));
        if (!dir.existsSync()) continue;
        var sum = 0;
        var allPresent = true;
        for (final bf in m.files!) {
          final f = File(p.join(dir.path, bf.filename));
          if (!f.existsSync() || f.lengthSync() <= 0) {
            allPresent = false;
            break;
          }
          sum += f.lengthSync();
        }
        if (allPresent) {
          e
            ..state = ModelState.present
            ..received = sum
            ..total = sum;
        }
      } else {
        final f = File(p.join(directory, m.entry!.targetFilename));
        if (f.existsSync() && f.lengthSync() > 0) {
          e
            ..state = ModelState.present
            ..received = f.lengthSync()
            ..total = f.lengthSync();
        }
      }
    }
  }

  /// Absolute path the candidate consumes when [id] is present, else null.
  ///
  /// For single-file models this is the model file; for bundle models it is the
  /// `models/<id>/` directory (the candidate resolves its files inside).
  String? localPathIfPresent(String id) {
    final e = _entries[id];
    if (e == null || e.state != ModelState.present) return null;
    final m = e.model;
    return m.isBundle
        ? p.join(directory, m.id)
        : p.join(directory, m.entry!.targetFilename);
  }

  /// The catalogue model for [id], or null.
  CatalogModel? byId(String id) => _entries[id]?.model;

  /// JSON-serialisable catalogue + state snapshot for `GET /api/models`.
  List<Map<String, Object?>> statusJson() => [
    for (final m in catalog)
      () {
        final e = _entries[m.id]!;
        return <String, Object?>{
          'id': m.id,
          'label': m.label,
          'family': m.family,
          'sizeBytes': m.totalSizeBytes,
          'state': e.state.name,
          'received': e.received,
          'total': e.total > 0 ? e.total : m.totalSizeBytes,
          if (e.error != null) 'error': e.error,
        };
      }(),
  ];

  /// True while [id] is being downloaded.
  bool isDownloading(String id) =>
      _entries[id]?.state == ModelState.downloading;

  /// Downloads model [id] into [directory], updating state and invoking
  /// [onChange] on every progress tick (used to fan out SSE updates).
  ///
  /// Idempotent: returns immediately if the model is already present or a
  /// download is in flight. Never throws — failures land in the model state.
  Future<void> download(String id, {void Function()? onChange}) async {
    final e = _entries[id];
    if (e == null) return;
    if (e.state == ModelState.present || e.state == ModelState.downloading) {
      return;
    }
    final m = e.model;
    e
      ..state = ModelState.downloading
      ..received = 0
      ..total = m.totalSizeBytes
      ..error = null;
    onChange?.call();

    try {
      if (m.isBundle) {
        final dir = Directory(p.join(directory, m.id));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        var completed = 0;
        for (final bf in m.files!) {
          final target = File(p.join(dir.path, bf.filename));
          await _downloader(bf.url, target, (received, _) {
            e
              ..received = completed + received
              ..total = m.totalSizeBytes;
            onChange?.call();
          });
          await _verifyDownloaded(target, bf.sha256);
          completed += target.existsSync() ? target.lengthSync() : bf.sizeBytes;
        }
        e
          ..state = ModelState.present
          ..received = completed;
      } else {
        final dir = Directory(directory);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final target = File(p.join(directory, m.entry!.targetFilename));
        await _downloader(m.entry!.downloadUrl, target, (received, total) {
          e
            ..received = received
            ..total = total > 0 ? total : m.entry!.sizeBytes;
          onChange?.call();
        });
        await _verifyDownloaded(target, m.entry!.sha256);
        e
          ..state = ModelState.present
          ..received = target.existsSync() ? target.lengthSync() : e.received;
      }
    } on Object catch (err) {
      e
        ..state = ModelState.error
        ..error = '$err';
    }
    onChange?.call();
  }
}

/// Deletes [file] and throws when its SHA-256 differs from [expected]. An
/// empty [expected] skips the check (entries without a pinned upstream copy).
Future<void> _verifyDownloaded(File file, String expected) async {
  if (expected.isEmpty || !file.existsSync()) return;
  final actual = (await sha256.bind(file.openRead()).first).toString();
  if (actual == expected) return;
  await file.delete();
  throw StateError(
    'Prüfsumme falsch für ${p.basename(file.path)}: '
    'erwartet $expected, erhalten $actual',
  );
}

/// Production [ProgressDownloader] — streams [url] to `<target>.part`, reports
/// progress, then atomically renames to [target]. Follows redirects (Hugging
/// Face `resolve/` URLs redirect to a CDN).
Future<void> httpProgressDownloader(
  Uri url,
  File target,
  void Function(int received, int total) onProgress,
) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    final resp = await req.close();
    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode} beim Laden von $url');
    }
    final total = resp.contentLength;
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
    } finally {
      await sink.close();
    }
    if (target.existsSync()) await target.delete();
    await part.rename(target.path);
  } finally {
    client.close(force: true);
  }
}

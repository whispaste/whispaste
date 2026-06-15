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
  });

  /// Source URL.
  final Uri url;

  /// Target filename inside the model's bundle directory.
  final String filename;

  /// Approximate size in bytes (display + progress-bar fallback).
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
/// - `onnx-whisper` : ONNX Runtime + DirectML Whisper-ONNX (microsoft/…-directml)
/// - `onnx-wav2vec2`: non-Whisper German wav2vec2 ONNX (jonatasgrosman/…)
///
/// Sizes are approximate on-disk sizes for display + download progress.
List<CatalogModel> defaultModelCatalog() {
  CatalogModel make(
    String id,
    String family,
    Uri url,
    String file,
    int bytes,
    String label,
  ) => CatalogModel(
    id: id,
    label: label,
    family: family,
    entry: ModelEntry(
      name: id,
      downloadUrl: url,
      sha256: '', // checksum optional; empty = verify by presence only
      targetFilename: file,
      sizeBytes: bytes,
    ),
  );
  Uri ggmlUrl(String file) => Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file',
  );
  // sherpa-onnx Whisper bundle: encoder + decoder + tokens (int8) downloaded
  // into models/<id>/. Sizes are the real Hugging Face file sizes.
  CatalogModel sherpa(String size, int enc, int dec, String label) {
    Uri u(String f) => Uri.parse(
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-$size'
      '/resolve/main/$f',
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
          sizeBytes: enc,
        ),
        BundleFile(
          url: u('$size-decoder.int8.onnx'),
          filename: '$size-decoder.int8.onnx',
          sizeBytes: dec,
        ),
        BundleFile(
          url: u('$size-tokens.txt'),
          filename: '$size-tokens.txt',
          sizeBytes: tokens,
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
    ),
    make(
      'ggml-base',
      'ggml',
      ggmlUrl('ggml-base.bin'),
      'ggml-base.bin',
      147951465,
      'Base · ~141 MB · schnell',
    ),
    make(
      'ggml-small',
      'ggml',
      ggmlUrl('ggml-small.bin'),
      'ggml-small.bin',
      487601967,
      'Small · ~465 MB · ausgewogen',
    ),
    make(
      'ggml-medium',
      'ggml',
      ggmlUrl('ggml-medium.bin'),
      'ggml-medium.bin',
      1533763059,
      'Medium · ~1,5 GB · genau',
    ),
    make(
      'ggml-large-v3',
      'ggml',
      ggmlUrl('ggml-large-v3.bin'),
      'ggml-large-v3.bin',
      3094623691,
      'Large v3 · ~2,9 GB · höchste Qualität',
    ),
    // ONNX Whisper — ONNX Runtime + DirectML.
    make(
      'onnx-whisper-small',
      'onnx-whisper',
      Uri.parse(
        'https://huggingface.co/microsoft/whisper-small-directml/resolve/main/whisper_small_int8.onnx',
      ),
      'whisper_small_int8.onnx',
      242000000,
      'Whisper Small (ONNX int8) · ~242 MB',
    ),
    make(
      'onnx-whisper-medium',
      'onnx-whisper',
      Uri.parse(
        'https://huggingface.co/microsoft/whisper-medium-directml/resolve/main/whisper_medium_int8.onnx',
      ),
      'whisper_medium_int8.onnx',
      769000000,
      'Whisper Medium (ONNX int8) · ~769 MB · Crash-Risiko',
    ),
    // Non-Whisper — German wav2vec2 (ONNX).
    make(
      'wav2vec2-de-xlsr53',
      'onnx-wav2vec2',
      Uri.parse(
        'https://huggingface.co/jonatasgrosman/wav2vec2-large-xlsr-53-german/resolve/main/model.onnx',
      ),
      'wav2vec2-large-xlsr-53-german.onnx',
      1180000000,
      'wav2vec2 XLSR-53 Deutsch (ONNX) · ~1,18 GB',
    ),
    // sherpa-onnx (k2-fsa) — multilingual Whisper-ONNX bundles, CPU EP.
    sherpa(
      'tiny',
      12937772,
      89855401,
      'sherpa-onnx Whisper Tiny (int8) · ~103 MB · sehr schnell',
    ),
    sherpa(
      'base',
      29120534,
      130672026,
      'sherpa-onnx Whisper Base (int8) · ~161 MB · schnell',
    ),
    sherpa(
      'small',
      112442483,
      262226114,
      'sherpa-onnx Whisper Small (int8) · ~376 MB · ausgewogen',
    ),
    sherpa(
      'medium',
      374196283,
      571059257,
      'sherpa-onnx Whisper Medium (int8) · ~946 MB · genau',
    ),
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

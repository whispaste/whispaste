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

/// One catalogue model: display metadata + the [ModelEntry] used to fetch it.
class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.label,
    required this.entry,
  });

  /// Stable identifier used in the UI / API (e.g. `ggml-small`).
  final String id;

  /// Human label shown in the UI (e.g. `Small · 466 MB · gut/schnell`).
  final String label;

  /// Fetch metadata (URL, target filename, size, checksum).
  final ModelEntry entry;
}

/// The default Whisper (ggml / whisper.cpp) model catalogue, smallest → largest.
///
/// Source: the official `ggerganov/whisper.cpp` models on Hugging Face. Sizes
/// are approximate on-disk sizes used purely for display + download progress.
List<CatalogModel> defaultModelCatalog() {
  CatalogModel m(String id, String file, int bytes, String label) =>
      CatalogModel(
        id: id,
        label: label,
        entry: ModelEntry(
          name: id,
          downloadUrl: Uri.parse(
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file',
          ),
          sha256: '', // checksum optional; empty = verify by presence only
          targetFilename: file,
          sizeBytes: bytes,
        ),
      );
  return [
    m('ggml-tiny', 'ggml-tiny.bin', 77691713, 'Tiny · ~75 MB · sehr schnell'),
    m('ggml-base', 'ggml-base.bin', 147951465, 'Base · ~141 MB · schnell'),
    m(
      'ggml-small',
      'ggml-small.bin',
      487601967,
      'Small · ~465 MB · ausgewogen',
    ),
    m('ggml-medium', 'ggml-medium.bin', 1533763059, 'Medium · ~1,5 GB · genau'),
    m(
      'ggml-large-v3',
      'ggml-large-v3.bin',
      3094623691,
      'Large v3 · ~2,9 GB · höchste Qualität',
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
      final f = File(p.join(directory, e.model.entry.targetFilename));
      if (f.existsSync() && f.lengthSync() > 0) {
        e
          ..state = ModelState.present
          ..received = f.lengthSync()
          ..total = f.lengthSync();
      }
    }
  }

  /// Absolute path of the model file for [id] when present, else null.
  String? localPathIfPresent(String id) {
    final e = _entries[id];
    if (e == null || e.state != ModelState.present) return null;
    return p.join(directory, e.model.entry.targetFilename);
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
          'sizeBytes': m.entry.sizeBytes,
          'state': e.state.name,
          'received': e.received,
          'total': e.total > 0 ? e.total : m.entry.sizeBytes,
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
    e
      ..state = ModelState.downloading
      ..received = 0
      ..total = e.model.entry.sizeBytes
      ..error = null;
    onChange?.call();

    final dir = Directory(directory);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File(p.join(directory, e.model.entry.targetFilename));

    try {
      await _downloader(e.model.entry.downloadUrl, target, (received, total) {
        e
          ..received = received
          ..total = total > 0 ? total : e.model.entry.sizeBytes;
        onChange?.call();
      });
      e
        ..state = ModelState.present
        ..received = target.existsSync() ? target.lengthSync() : e.received;
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

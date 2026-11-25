/// Loads a newer model catalog without an app release (#1792).
///
/// Source: two assets of the fixed GitHub release `model-catalog` in the
/// public repository, `model-catalog.json` (metadata only: IDs, sizes,
/// SHA-256 and pinned sources, never model files) and
/// `model-catalog.json.sig`, the Ed25519 signature of its exact bytes with
/// the appcast key ([kModelCatalogPublicKey]). The maintainer publishes
/// both with `scripts/publish-model-catalog.sh`.
///
/// Trust: a file whose signature does not check out, whose format the app
/// cannot read, or whose `revision` is below the stored one is never used;
/// the app keeps the stored catalog or, without one, the bundled catalog.
/// Merging ([mergeDownloadedCatalog]) only ever adds models.
///
/// Network: none before the first-run privacy choice, only where the app
/// updates itself and only while "Check for updates" is on, at start and
/// every 24 hours (`main.dart`). A conditional request (`If-None-Match`)
/// keeps a known file from being downloaded again. Every hop goes through
/// the download host allowlist ([getWithAllowlistedRedirects]). NETWORK.md
/// lists it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/models/active_model_catalog.dart';
import '../../core/models/bundled_model_catalog.dart';
import '../../core/models/model_catalog.dart';
import '../../core/models/model_catalog_signature.dart';
import '../download_allowlist.dart';
import '../http_model_fetcher.dart' show buildDioWithSentry;

final _log = AppLogger('ModelCatalog');

/// The catalog file. A fixed release tag, never `latest`.
const String kModelCatalogUrl =
    'https://github.com/whispaste/whispaste/releases/download/model-catalog/model-catalog.json';

/// Its detached signature.
const String kModelCatalogSignatureUrl = '$kModelCatalogUrl.sig';

/// Larger answers are refused: the catalog is a few kilobytes.
const int kModelCatalogMaxBytes = 1024 * 1024;

/// A base64 Ed25519 signature is 88 characters.
const int _maxSignatureBytes = 1024;

/// How often the app asks for a newer catalog while it runs.
const Duration modelCatalogRefreshInterval = Duration(hours: 24);

/// The folder of the stored catalog file, inside the app data.
String modelCatalogCacheDir(String appDataDir) =>
    p.join(appDataDir, 'model_catalog');

/// The system this app runs on, as a catalog platform; null elsewhere.
ModelPlatform? currentModelPlatform() {
  if (Platform.isMacOS) return ModelPlatform.macos;
  if (Platform.isWindows) return ModelPlatform.windows;
  if (Platform.isLinux) return ModelPlatform.linux;
  return null;
}

/// The catalog file as stored on disk, not yet checked.
class StoredCatalogFile {
  const StoredCatalogFile({
    required this.bytes,
    required this.signature,
    this.etag,
  });

  final Uint8List bytes;
  final String signature;

  /// The `ETag` the server sent with [bytes], for the next conditional
  /// request.
  final String? etag;
}

/// The last verified catalog file on disk: `model-catalog.json`,
/// `model-catalog.json.sig` and `etag`. Checked again on every read, so a
/// file changed on disk is ignored like a bad download.
class ModelCatalogCache {
  ModelCatalogCache(this.directory);

  final String directory;

  File get _json => File(p.join(directory, 'model-catalog.json'));
  File get _sig => File(p.join(directory, 'model-catalog.json.sig'));
  File get _etag => File(p.join(directory, 'etag'));

  /// The stored file, or null when there is none or it cannot be read.
  Future<StoredCatalogFile?> read() async {
    try {
      if (!await _json.exists() || !await _sig.exists()) return null;
      final etag = await _etag.exists() ? await _etag.readAsString() : null;
      return StoredCatalogFile(
        bytes: await _json.readAsBytes(),
        signature: await _sig.readAsString(),
        etag: etag == null || etag.trim().isEmpty ? null : etag.trim(),
      );
    } on FileSystemException catch (e) {
      _log.warning('stored model catalog unreadable', e);
      return null;
    }
  }

  /// Stores [file]. Each part is written to a temporary file and renamed,
  /// so a crash leaves the old or the new part, never half a file; a
  /// mismatched pair fails the signature check on the next read.
  Future<void> write(StoredCatalogFile file) async {
    await Directory(directory).create(recursive: true);
    await _replace(_json, file.bytes);
    await _replace(_sig, utf8.encode(file.signature.trim()));
    if (file.etag == null) {
      if (await _etag.exists()) await _etag.delete();
    } else {
      await _replace(_etag, utf8.encode(file.etag!));
    }
  }

  /// Writes only a new ETag for the stored file.
  Future<void> writeEtag(String etag) async {
    await Directory(directory).create(recursive: true);
    await _replace(_etag, utf8.encode(etag));
  }

  static Future<void> _replace(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }
}

/// The catalog in [bytes] when [signature] is valid under [publicKey] and
/// the file is a readable catalog, else null. Entries above [appVersion]
/// are left out ([ModelCatalog.fromJson]).
ModelCatalog? readVerifiedCatalog(
  Uint8List bytes,
  String signature, {
  required String appVersion,
  String publicKey = kModelCatalogPublicKey,
}) {
  if (!verifyModelCatalogSignature(bytes, signature, publicKey: publicKey)) {
    _log.warning('model catalog signature invalid, file ignored');
    return null;
  }
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map) {
      throw const ModelCatalogFormatException('not a JSON object');
    }
    return ModelCatalog.fromJson(
      json.cast<String, Object?>(),
      appVersion: appVersion,
    );
  } on FormatException catch (e) {
    _log.warning('signed model catalog unreadable, file ignored: $e');
    return null;
  }
}

/// What a [RemoteModelCatalogService.refresh] did.
enum ModelCatalogRefreshResult {
  /// A newer catalog is stored and in use.
  updated,

  /// The server has nothing newer.
  unchanged,

  /// No usable answer (network, size, signature, format, older revision);
  /// the catalog in use stays.
  failed,
}

/// Loads, checks, stores and applies the downloadable catalog.
class RemoteModelCatalogService {
  RemoteModelCatalogService({
    required this.cache,
    required this.appVersion,
    this.platform,
    Dio? dio,
    this.publicKey = kModelCatalogPublicKey,
    this.timeout = const Duration(seconds: 30),
    void Function(ModelCatalog catalog)? apply,
  }) : _dioOverride = dio,
       _apply = apply ?? setActiveModelCatalog;

  final ModelCatalogCache cache;
  final String appVersion;
  final ModelPlatform? platform;
  final String publicKey;
  final Duration timeout;
  final Dio? _dioOverride;
  final void Function(ModelCatalog catalog) _apply;

  /// The last verified catalog file (before merging), or null.
  ModelCatalog? _stored;
  String? _storedEtag;
  Uint8List? _storedBytes;

  /// The verified downloaded catalog in use, or null when only the bundled
  /// one is used.
  ModelCatalog? get storedCatalog => _stored;

  /// Applies the stored catalog file, if it is still valid. No network.
  Future<void> loadCached() async {
    final file = await cache.read();
    if (file == null) return;
    final catalog = readVerifiedCatalog(
      file.bytes,
      file.signature,
      appVersion: appVersion,
      publicKey: publicKey,
    );
    if (catalog == null) return;
    _remember(catalog, file);
    _applyMerged(catalog);
    _log.info('stored model catalog revision ${catalog.revision} in use');
  }

  /// Asks the server for a newer catalog and applies it when it checks out.
  /// Never throws.
  Future<ModelCatalogRefreshResult> refresh() async {
    final dio =
        _dioOverride ??
        buildDioWithSentry(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        );
    try {
      return await _refresh(dio).timeout(timeout);
    } on Object catch (e) {
      _log.info('model catalog refresh failed: $e');
      return ModelCatalogRefreshResult.failed;
    } finally {
      if (_dioOverride == null) dio.close();
    }
  }

  Future<ModelCatalogRefreshResult> _refresh(Dio dio) async {
    final etag = _stored == null ? null : _storedEtag;
    final Response<List<int>> response;
    try {
      response = await getWithAllowlistedRedirects<List<int>>(
        dio,
        kModelCatalogUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'If-None-Match': ?etag},
        ),
      );
    } on DioException catch (e) {
      // The transport only lets 2xx and redirects through; 304 arrives here.
      if (e.response?.statusCode == HttpStatus.notModified) {
        return ModelCatalogRefreshResult.unchanged;
      }
      rethrow;
    }
    if (response.statusCode == HttpStatus.notModified) {
      return ModelCatalogRefreshResult.unchanged;
    }
    final body = response.data;
    if (response.statusCode != HttpStatus.ok || body == null) {
      _log.info('model catalog: HTTP ${response.statusCode}');
      return ModelCatalogRefreshResult.failed;
    }
    if (body.length > kModelCatalogMaxBytes) {
      _log.warning('model catalog too large (${body.length} bytes)');
      return ModelCatalogRefreshResult.failed;
    }
    final bytes = Uint8List.fromList(body);
    final newEtag = response.headers.value('etag');
    if (_storedBytes != null && _sameBytes(bytes, _storedBytes!)) {
      if (newEtag != null && newEtag != _storedEtag) {
        _storedEtag = newEtag;
        await cache.writeEtag(newEtag);
      }
      return ModelCatalogRefreshResult.unchanged;
    }

    final sigResponse = await getWithAllowlistedRedirects<List<int>>(
      dio,
      kModelCatalogSignatureUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final sigBody = sigResponse.data;
    if (sigResponse.statusCode != HttpStatus.ok ||
        sigBody == null ||
        sigBody.length > _maxSignatureBytes) {
      _log.info('model catalog signature: HTTP ${sigResponse.statusCode}');
      return ModelCatalogRefreshResult.failed;
    }
    final signature = utf8.decode(sigBody, allowMalformed: true);
    final catalog = readVerifiedCatalog(
      bytes,
      signature,
      appVersion: appVersion,
      publicKey: publicKey,
    );
    if (catalog == null) return ModelCatalogRefreshResult.failed;
    final stored = _stored;
    if (stored != null && catalog.revision < stored.revision) {
      _log.warning(
        'model catalog revision ${catalog.revision} is older than the '
        'stored ${stored.revision}, refused',
      );
      return ModelCatalogRefreshResult.failed;
    }
    final file = StoredCatalogFile(
      bytes: bytes,
      signature: signature,
      etag: newEtag,
    );
    await cache.write(file);
    _remember(catalog, file);
    _applyMerged(catalog);
    _log.info('model catalog revision ${catalog.revision} loaded');
    return ModelCatalogRefreshResult.updated;
  }

  void _remember(ModelCatalog catalog, StoredCatalogFile file) {
    _stored = catalog;
    _storedEtag = file.etag;
    _storedBytes = file.bytes;
  }

  void _applyMerged(ModelCatalog downloaded) => _apply(
    mergeDownloadedCatalog(
      bundledModelCatalog,
      downloaded,
      appVersion: appVersion,
      platform: platform,
    ),
  );

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Runs [refresh] now and every [interval], each time only when [enabled]
/// says so at that moment (the "Check for updates" toggle, re-read so a
/// change applies without a restart). Returns the timer; cancel it to stop.
Timer startModelCatalogRefresh({
  required Future<Object?> Function() refresh,
  required bool Function() enabled,
  Duration interval = modelCatalogRefreshInterval,
}) {
  if (enabled()) unawaited(refresh());
  return Timer.periodic(interval, (_) {
    if (enabled()) unawaited(refresh());
  });
}

/// The catalog in use, for widgets that list models: rebuilds them when a
/// downloaded catalog adds models ([setActiveModelCatalog]).
final activeModelCatalogProvider =
    NotifierProvider<ActiveModelCatalogNotifier, ModelCatalog>(
      ActiveModelCatalogNotifier.new,
    );

class ActiveModelCatalogNotifier extends Notifier<ModelCatalog> {
  @override
  ModelCatalog build() {
    final sub = activeModelCatalogChanges.listen((c) => state = c);
    ref.onDispose(sub.cancel);
    return activeModelCatalog;
  }
}

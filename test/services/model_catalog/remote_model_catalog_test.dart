// Loading the downloadable model catalog (#1792): a signed newer file is
// stored and merged, an unchanged one is not downloaded again (ETag), and
// anything unsigned, unreadable or older keeps the catalog in use.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/models/bundled_model_catalog.dart';
import 'package:whispaste/core/models/model_catalog.dart';
import 'package:whispaste/core/models/model_catalog_signature.dart';
import 'package:whispaste/services/model_catalog/remote_model_catalog.dart';

final _seed = base64.encode(List<int>.generate(32, (i) => i + 7));
final _publicKey = modelCatalogPublicKeyOf(_seed);

Uint8List _catalogBytes({
  int revision = 1,
  String id = 'whisper-new',
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'revision': revision,
      'models': [
        {
          'id': id,
          'kind': 'stt',
          'runtime': 'whisper.cpp',
          'label': id,
          'minAppVersion': '1.5.2',
          'languages': ['mul'],
          'speed': 'medium',
          'accuracy': 'high',
          'requirements': {
            'platforms': ['macos', 'windows', 'linux'],
          },
          'license': 'MIT',
          'files': [
            {
              'filename': 'ggml-$id.bin',
              'sizeBytes': 1000,
              'sha256': 'c' * 64,
              'sources': [
                'https://huggingface.co/o/r/resolve/${'d' * 40}/ggml-$id.bin',
              ],
            },
          ],
        },
      ],
    }),
  ),
);

/// Serves the catalog and its signature like the GitHub release, and
/// records the request headers.
class _ReleaseAdapter implements HttpClientAdapter {
  _ReleaseAdapter(this.catalog, this.signature);

  Uint8List catalog;
  String signature;
  String etag = '"v1"';
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final url = options.uri.toString();
    if (url == kModelCatalogUrl) {
      if (options.headers['If-None-Match'] == etag) {
        return ResponseBody.fromBytes(const [], 304);
      }
      return ResponseBody.fromBytes(
        catalog,
        200,
        headers: {
          'etag': [etag],
        },
      );
    }
    if (url == kModelCatalogSignatureUrl) {
      return ResponseBody.fromString(signature, 200);
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late List<ModelCatalog> applied;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('model_catalog_test');
    applied = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  RemoteModelCatalogService service(_ReleaseAdapter adapter) =>
      RemoteModelCatalogService(
        cache: ModelCatalogCache(dir.path),
        appVersion: '1.5.5',
        dio: Dio()..httpClientAdapter = adapter,
        publicKey: _publicKey,
        apply: applied.add,
      );

  test('a signed catalog is stored and merged into the bundled one', () async {
    final bytes = _catalogBytes();
    final adapter = _ReleaseAdapter(bytes, signModelCatalog(bytes, _seed));
    final s = service(adapter);

    expect(await s.refresh(), ModelCatalogRefreshResult.updated);
    expect(applied.single.tryById('whisper-new'), isNotNull);
    expect(applied.single.models.length, bundledModelCatalog.models.length + 1);
    expect(File('${dir.path}/model-catalog.json').readAsBytesSync(), bytes);
    expect(adapter.requests.first.headers['If-None-Match'], isNull);

    // A second start reads the stored file without network, then asks with
    // the ETag and gets 304.
    final again = service(adapter);
    await again.loadCached();
    expect(applied.last.tryById('whisper-new'), isNotNull);
    adapter.requests.clear();
    expect(await again.refresh(), ModelCatalogRefreshResult.unchanged);
    expect(adapter.requests.single.headers['If-None-Match'], '"v1"');
  });

  test('a bad signature keeps the bundled catalog', () async {
    final bytes = _catalogBytes();
    final s = service(
      _ReleaseAdapter(bytes, signModelCatalog(_catalogBytes(id: 'x'), _seed)),
    );
    expect(await s.refresh(), ModelCatalogRefreshResult.failed);
    expect(applied, isEmpty);
    expect(File('${dir.path}/model-catalog.json').existsSync(), isFalse);
  });

  test('an older revision is refused', () async {
    final v2 = _catalogBytes(revision: 2);
    final adapter = _ReleaseAdapter(v2, signModelCatalog(v2, _seed));
    final s = service(adapter);
    expect(await s.refresh(), ModelCatalogRefreshResult.updated);

    final v1 = _catalogBytes(revision: 1, id: 'whisper-old');
    adapter
      ..catalog = v1
      ..signature = signModelCatalog(v1, _seed)
      ..etag = '"v0"';
    expect(await s.refresh(), ModelCatalogRefreshResult.failed);
    expect(s.storedCatalog!.revision, 2);
    expect(applied.length, 1);
  });

  test('a stored file changed on disk is ignored', () async {
    final bytes = _catalogBytes();
    await ModelCatalogCache(dir.path).write(
      StoredCatalogFile(
        bytes: bytes,
        signature: signModelCatalog(bytes, _seed),
      ),
    );
    File(
      '${dir.path}/model-catalog.json',
    ).writeAsBytesSync(_catalogBytes(id: 'tampered'));
    final s = service(_ReleaseAdapter(bytes, ''));
    await s.loadCached();
    expect(applied, isEmpty);
    expect(s.storedCatalog, isNull);
  });

  test('a network failure keeps the catalog in use', () async {
    final s = RemoteModelCatalogService(
      cache: ModelCatalogCache(dir.path),
      appVersion: '1.5.5',
      dio: Dio()..httpClientAdapter = _FailingAdapter(),
      publicKey: _publicKey,
      apply: applied.add,
    );
    expect(await s.refresh(), ModelCatalogRefreshResult.failed);
    expect(applied, isEmpty);
  });

  test('refresh runs only while enabled', () {
    fakeAsync((async) {
      var calls = 0;
      var enabled = false;
      final timer = startModelCatalogRefresh(
        refresh: () async => calls++,
        enabled: () => enabled,
        interval: const Duration(milliseconds: 10),
      );
      async.elapse(const Duration(milliseconds: 35));
      expect(calls, 0);
      enabled = true;
      async.elapse(const Duration(milliseconds: 35));
      expect(calls, greaterThan(0));
      timer.cancel();
    });
  });
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) => Future.error(const SocketException('offline'));

  @override
  void close({bool force = false}) {}
}

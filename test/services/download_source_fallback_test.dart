/// Hand-over points of the hardened model download (`fetchVerified`):
/// source fallback, hash check per source, resume validation across app
/// restarts (fragment identity) and the one-writer-per-file lock.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/download_fragment_guard.dart';
import 'package:whispaste/services/http_model_fetcher.dart';

/// Answers by URL host: a handler per host, every request recorded.
class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.handlers);
  final Map<String, Future<ResponseBody> Function(RequestOptions)> handlers;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handlers[options.uri.host]!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok(List<int> bytes) => ResponseBody(
  Stream.value(Uint8List.fromList(bytes)),
  200,
  headers: {
    'content-length': ['${bytes.length}'],
  },
);

ResponseBody _status(int code) =>
    ResponseBody(const Stream<Uint8List>.empty(), code, headers: {});

const _primary = 'https://huggingface.co/org/repo/resolve/abc/model.bin';
const _mirror = 'https://github.com/org/repo/releases/download/t/model.bin';

void main() {
  late Directory dir;
  late String dest;
  final good = List<int>.generate(64, (i) => i);
  final goodSha = sha256.convert(good).toString();
  final bad = List<int>.filled(64, 7);

  HttpModelFetcher fetcherWith(_HostAdapter adapter) => HttpModelFetcher(
    dio: Dio()..httpClientAdapter = adapter,
    retryBackoff: const [],
  );

  Future<String?> run(HttpModelFetcher f) => f.fetchVerified(
    sources: const [_primary, _mirror],
    destPath: dest,
    expectedSize: good.length,
    expectedSha256: goodSha,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_sources_');
    dest = p.join(dir.path, 'model.bin');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('source fallback', () {
    test('stalled first source exhausts retries and switches source', () async {
      final silent = StreamController<Uint8List>();
      final adapter = _HostAdapter({
        'huggingface.co': (_) async => ResponseBody(silent.stream, 200),
        'github.com': (_) async => _ok(good),
      });
      final fetcher = HttpModelFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        retryBackoff: const [],
        stallThreshold: const Duration(milliseconds: 40),
        stallCheckInterval: const Duration(milliseconds: 10),
      );
      expect(await run(fetcher), _mirror);
      await silent.close();
      expect(File(dest).readAsBytesSync(), good);
    });

    test(
      'HTML response is discarded before writing and next source works',
      () async {
        final adapter = _HostAdapter({
          'huggingface.co': (_) async => ResponseBody.fromString(
            '<html>Sign in</html>',
            200,
            headers: {
              'content-type': ['text/html; charset=utf-8'],
            },
          ),
          'github.com': (_) async => _ok(good),
        });
        expect(await run(fetcherWith(adapter)), _mirror);
        expect(adapter.requests.last.headers['Range'], isNull);
        expect(File(dest).readAsBytesSync(), good);
      },
    );

    test(
      'wrong announced size never contaminates a resumable fragment',
      () async {
        await prepareFragmentIdentity(
          destPath: dest,
          sha256: goodSha,
          sizeBytes: good.length,
        );
        File('$dest.tmp').writeAsBytesSync(good.take(20).toList());
        final adapter = _HostAdapter({
          'huggingface.co': (_) async => _ok([1, 2, 3]),
          'github.com': (_) async => ResponseBody(
            Stream.value(Uint8List.fromList(good.sublist(20))),
            206,
            headers: {
              'content-length': ['44'],
              'content-range': ['bytes 20-63/64'],
            },
          ),
        });
        expect(await run(fetcherWith(adapter)), _mirror);
        expect(adapter.requests.last.headers['Range'], 'bytes=20-');
        expect(File(dest).readAsBytesSync(), good);
      },
    );

    test('HTTP error at the primary → the mirror delivers', () async {
      final adapter = _HostAdapter({
        'huggingface.co': (_) async => _status(404),
        'github.com': (_) async => _ok(good),
      });
      expect(await run(fetcherWith(adapter)), _mirror);
      expect(File(dest).readAsBytesSync(), good);
    });

    test('wrong hash at the primary → deleted, the mirror delivers', () async {
      final adapter = _HostAdapter({
        'huggingface.co': (_) async => _ok(bad),
        'github.com': (_) async => _ok(good),
      });
      expect(await run(fetcherWith(adapter)), _mirror);
      expect(File(dest).readAsBytesSync(), good);
    });

    test('every source with the wrong hash → DownloadChecksumException, '
        'nothing left in place', () async {
      final adapter = _HostAdapter({
        'huggingface.co': (_) async => _ok(bad),
        'github.com': (_) async => _ok(bad),
      });
      await expectLater(
        run(fetcherWith(adapter)),
        throwsA(isA<DownloadChecksumException>()),
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.tmp').existsSync(), isFalse);
    });

    test(
      'the first source that works is used, later ones are not asked',
      () async {
        final adapter = _HostAdapter({
          'huggingface.co': (_) async => _ok(good),
          'github.com': (_) async => fail('mirror must not be asked'),
        });
        expect(await run(fetcherWith(adapter)), _primary);
        expect(File(fragmentIdentityPath(dest)).existsSync(), isFalse);
      },
    );

    test('a verified file in place is kept without any request', () async {
      final adapter = _HostAdapter({
        'huggingface.co': (_) async => _ok(good),
        'github.com': (_) async => _ok(good),
      });
      await run(fetcherWith(adapter));
      final before = adapter.requests.length;
      expect(await run(fetcherWith(adapter)), isNull);
      expect(adapter.requests, hasLength(before));
    });

    test('a file in place with another hash is replaced', () async {
      File(dest).writeAsBytesSync(bad);
      final adapter = _HostAdapter({
        'huggingface.co': (_) async => _ok(good),
        'github.com': (_) async => _ok(good),
      });
      expect(await run(fetcherWith(adapter)), _primary);
      expect(File(dest).readAsBytesSync(), good);
    });
  });

  group('transient HTTP status', () {
    test('429 is asked again on the same source before falling back', () async {
      var calls = 0;
      final adapter = _HostAdapter({
        'huggingface.co': (_) async => ++calls == 1 ? _status(429) : _ok(good),
        'github.com': (_) async => fail('mirror must not be asked'),
      });
      final fetcher = HttpModelFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        retryBackoff: const [Duration(milliseconds: 1)],
      );
      expect(await run(fetcher), _primary);
      expect(calls, 2);
    });

    test('Retry-After is honoured, capped, else the backoff applies', () {
      const backoff = Duration(seconds: 3);
      expect(
        transientRetryDelay(retryAfter: '5', backoff: backoff),
        const Duration(seconds: 5),
      );
      expect(
        transientRetryDelay(retryAfter: '3600', backoff: backoff),
        kMaxRetryAfter,
      );
      expect(transientRetryDelay(retryAfter: null, backoff: backoff), backoff);
      expect(
        transientRetryDelay(retryAfter: 'Wed, 21 Oct 2015', backoff: backoff),
        backoff,
      );
    });
  });

  group('resume validation across restarts (fragment identity)', () {
    test(
      'a fragment of the same file is resumed with a Range request',
      () async {
        await prepareFragmentIdentity(
          destPath: dest,
          sha256: goodSha,
          sizeBytes: good.length,
        );
        File('$dest.tmp').writeAsBytesSync(good.sublist(0, 20));
        final adapter = _HostAdapter({
          'huggingface.co': (o) async => ResponseBody(
            Stream.value(Uint8List.fromList(good.sublist(20))),
            206,
            headers: {
              'content-length': ['${good.length - 20}'],
              'content-range': ['bytes 20-${good.length - 1}/${good.length}'],
            },
          ),
          'github.com': (_) async => fail('mirror must not be asked'),
        });
        expect(await run(fetcherWith(adapter)), _primary);
        expect(adapter.requests.single.headers['Range'], 'bytes=20-');
        expect(File(dest).readAsBytesSync(), good);
      },
    );

    test('a fragment without identity (older app) is dropped', () async {
      File('$dest.tmp').writeAsBytesSync(bad.sublist(0, 20));
      await prepareFragmentIdentity(
        destPath: dest,
        sha256: goodSha,
        sizeBytes: good.length,
      );
      expect(File('$dest.tmp').existsSync(), isFalse);
      final id = await readFragmentIdentity(dest);
      expect(id?.sha256, goodSha);
      expect(id?.sizeBytes, good.length);
    });

    test('a fragment of another file version is dropped', () async {
      await prepareFragmentIdentity(
        destPath: dest,
        sha256: 'f' * 64,
        sizeBytes: good.length,
      );
      File('$dest.tmp').writeAsBytesSync(bad.sublist(0, 20));
      await prepareFragmentIdentity(
        destPath: dest,
        sha256: goodSha,
        sizeBytes: good.length,
      );
      expect(File('$dest.tmp').existsSync(), isFalse);
    });

    test('a fragment of the same version is kept', () async {
      await prepareFragmentIdentity(
        destPath: dest,
        sha256: goodSha,
        sizeBytes: good.length,
      );
      File('$dest.tmp').writeAsBytesSync(good.sublist(0, 20));
      await prepareFragmentIdentity(
        destPath: dest,
        sha256: goodSha,
        sizeBytes: good.length,
      );
      expect(File('$dest.tmp').lengthSync(), 20);
    });
  });

  group('one writer per file', () {
    test('two parallel downloads of the same file fetch it once', () async {
      final gate = Completer<void>();
      var calls = 0;
      final adapter = _HostAdapter({
        'huggingface.co': (_) async {
          calls++;
          await gate.future;
          return _ok(good);
        },
        'github.com': (_) async => _ok(good),
      });
      final a = run(fetcherWith(adapter));
      final b = run(fetcherWith(adapter));
      // Let the first writer reach the server and the second one queue up
      // behind its lock before the response is released.
      while (calls == 0) {
        await pumpEventQueue();
      }
      await pumpEventQueue();
      gate.complete();
      final results = await Future.wait([a, b]);

      expect(calls, 1, reason: 'the second waits, then finds the file');
      expect(results, containsAll(<String?>[_primary, null]));
      expect(File(dest).readAsBytesSync(), good);
    });

    test(
      'cancel while waiting for the other download ends as a cancel',
      () async {
        final gate = Completer<void>();
        var started = false;
        final adapter = _HostAdapter({
          'huggingface.co': (_) async {
            started = true;
            await gate.future;
            return _ok(good);
          },
          'github.com': (_) async => _ok(good),
        });
        final first = run(fetcherWith(adapter));
        // The first download holds the lock once it reaches the server.
        while (!started) {
          await pumpEventQueue();
        }
        final waiting = fetcherWith(adapter);
        final second = run(waiting);
        await pumpEventQueue();
        waiting.cancel();
        gate.complete();

        await expectLater(
          second,
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        expect(await first, _primary);
      },
    );

    test('the lock file sits next to the target and is reusable', () async {
      final lock = await DownloadFileLock.acquire(
        dest,
        isCancelled: () => false,
      );
      expect(File(downloadLockPath(dest)).existsSync(), isTrue);
      await lock.release();
      final again = await DownloadFileLock.acquire(
        dest,
        isCancelled: () => false,
      );
      await again.release();
    });
  });
}

/// Unit tests for the [HttpStallDetector] surface in
/// [HttpModelFetcher] and [WhisperServerDownloader].
///
/// Covers:
///   1. Stall-detection — a stream that goes silent for ≥ stallThreshold is
///      cancelled with `DioException(type: cancel, message: 'stalled')`.
///   2. No-stall — a stream that always pushes a chunk within the threshold
///      runs to completion.
///   3. `describeDioError` returns the exact PRD-specified German strings.
///   4. The outer retry loop in [WhisperServerDownloader.download] retries
///      on `cancel + 'stalled'` but rethrows on a user-initiated `cancel`.
///
/// Implementation note: instead of waiting 30 real seconds in tests, the
/// fetcher exposes a `stallThreshold` (and check interval) parameter via
/// `@visibleForTesting`. Tests use sub-second thresholds. This avoids the
/// fakeAsync ↔ real file I/O ↔ real `await for` interaction trap.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/whisper_server_downloader.dart';
import 'package:whispaste/services/whisper_server_manifest.dart';

// ---------------------------------------------------------------------------
// Fake HTTP adapter — feeds the Dio pipeline a controllable byte stream.
// ---------------------------------------------------------------------------

class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter(this.body);
  final ResponseBody body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Honour Dio's cancel signal — the body stream will receive an error
    // and the await-for loop in the fetcher will surface DioException(cancel).
    cancelFuture?.then((_) {
      // No-op; Dio's own handling translates this into a cancel DioException
      // when the outer code is wired correctly. The body stream itself is
      // closed by the test driver.
    });
    return body;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _streamBody(Stream<List<int>> stream, {int? contentLength}) {
  final headers = <String, List<String>>{};
  if (contentLength != null) headers['content-length'] = ['$contentLength'];
  // Dio's ResponseBody expects a Stream<Uint8List>; the helper accepts a
  // Stream<List<int>> for ergonomic test setup and converts each chunk.
  final typed = stream.map(Uint8List.fromList);
  return ResponseBody(typed, 200, headers: headers);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_stall_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC1 — stalled stream is cancelled with DioException(cancel, 'stalled')
  // ─────────────────────────────────────────────────────────────────────────

  group('HttpStallDetector — stall cancellation', () {
    test('stream that goes silent past stallThreshold is cancelled with '
        'DioException(cancel, message: "stalled")', () async {
      // A controllable stream: emit 2 small chunks, then go silent.
      final controller = StreamController<List<int>>();
      final body = _streamBody(controller.stream, contentLength: 1000);
      final dio = Dio()..httpClientAdapter = _StreamAdapter(body);

      final fetcher = HttpModelFetcher(
        dio: dio,
        stallThreshold: const Duration(milliseconds: 300),
        stallCheckInterval: const Duration(milliseconds: 50),
      );

      final destPath = p.join(tempDir.path, 'model.bin');
      final fetchFuture = fetcher.fetch(
        url: 'https://example.com/model.bin',
        destPath: destPath,
        expectedSize: 1000,
      );

      // Emit a couple of chunks within the first window.
      controller.add(List.filled(10, 0x01));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      controller.add(List.filled(10, 0x02));

      // Now go silent — the detector should fire within 50ms+300ms.
      DioException? caught;
      try {
        await fetchFuture;
      } on DioException catch (e) {
        caught = e;
      } catch (_) {
        // Other errors are not acceptable here.
      }

      expect(caught, isNotNull, reason: 'Expected a DioException(cancel)');
      expect(caught!.type, DioExceptionType.cancel);
      expect(caught.message, 'stalled');

      // Clean up the still-open controller (the listener was cancelled
      // by Dio, but we still own the source).
      await controller.close();
    });

    test(
      'stream that keeps emitting within the threshold is NOT cancelled',
      () async {
        // Emit a chunk every (threshold/2) until the total is reached, then
        // close the stream — the fetcher must complete normally.
        const totalChunks = 6;
        const chunkSize = 10;
        final controller = StreamController<List<int>>();
        final body = _streamBody(
          controller.stream,
          contentLength: totalChunks * chunkSize,
        );
        final dio = Dio()..httpClientAdapter = _StreamAdapter(body);

        final fetcher = HttpModelFetcher(
          dio: dio,
          stallThreshold: const Duration(milliseconds: 400),
          stallCheckInterval: const Duration(milliseconds: 50),
        );

        final destPath = p.join(tempDir.path, 'model.bin');
        final fetchFuture = fetcher.fetch(
          url: 'https://example.com/model.bin',
          destPath: destPath,
          expectedSize: totalChunks * chunkSize,
        );

        // Drive the stream at 150 ms intervals — well below the 400 ms
        // threshold.
        unawaited(() async {
          for (var i = 0; i < totalChunks; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            if (!controller.isClosed) {
              controller.add(List.filled(chunkSize, i & 0xFF));
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await controller.close();
        }());

        // Should complete without throwing.
        await fetchFuture;
        expect(File(destPath).existsSync(), isTrue);
        expect(
          await File(destPath).length(),
          totalChunks * chunkSize,
          reason: 'All bytes should have been written',
        );
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC3 — describeDioError returns PRD-specified strings
  // ─────────────────────────────────────────────────────────────────────────

  group('describeDioError', () {
    RequestOptions opts() => RequestOptions(path: 'https://example.com/x');

    test('cancel + "stalled" → stall message', () {
      final e = DioException(
        requestOptions: opts(),
        type: DioExceptionType.cancel,
        message: 'stalled',
      );
      expect(
        describeDioError(e),
        'Verbindung steht — kein Datenfortschritt seit 30 s.',
      );
    });

    test('connectionTimeout (no response) → connect-timeout message', () {
      final e = DioException(
        requestOptions: opts(),
        type: DioExceptionType.connectionTimeout,
      );
      expect(describeDioError(e), 'Verbindungsaufbau dauerte zu lange.');
    });

    test('receiveTimeout (no response) → receive-timeout message', () {
      final e = DioException(
        requestOptions: opts(),
        type: DioExceptionType.receiveTimeout,
      );
      expect(describeDioError(e), 'Server antwortet nicht mehr.');
    });

    test('connectionError (no response) → no-internet message', () {
      final e = DioException(
        requestOptions: opts(),
        type: DioExceptionType.connectionError,
      );
      expect(describeDioError(e), 'Keine Internetverbindung.');
    });

    test('generic no-response → falls back to type name', () {
      final e = DioException(
        requestOptions: opts(),
        type: DioExceptionType.unknown,
      );
      expect(describeDioError(e), 'Netzwerkfehler: unknown');
    });

    test('response present → HTTP status + message', () {
      final ro = opts();
      final e = DioException(
        requestOptions: ro,
        response: Response<dynamic>(requestOptions: ro, statusCode: 503),
        message: 'service unavailable',
      );
      expect(describeDioError(e), 'HTTP 503: service unavailable');
    });

    test('response present with null message → "unbekannter Fehler"', () {
      final ro = opts();
      final e = DioException(
        requestOptions: ro,
        response: Response<dynamic>(requestOptions: ro, statusCode: 404),
      );
      expect(describeDioError(e), 'HTTP 404: unbekannter Fehler');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC4 — WhisperServerDownloader.download retry-loop classification
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperServerDownloader retry-loop cancel classification', () {
    test(
      'cancel with message "stalled" is retriable — the outer loop tries '
      'the next attempt / repo and eventually throws a normal Exception',
      () async {
        // Fetcher always throws a stalled-cancel — the manifest-driven
        // downloader retries internally, then throws a normal Exception
        // (NOT rethrow the DioException as user-cancel).
        final downloader = WhisperServerDownloader(
          fetcher: _AlwaysStalledFetcher(),
          manifestLoader: _fakeManifestLoader(),
        );

        await expectLater(
          () => downloader.download(destDir: tempDir.path, gpuMode: 'auto'),
          throwsA(allOf(isA<Exception>(), isNot(isA<DioException>()))),
        );
      },
    );

    test(
      'cancel WITHOUT "stalled" message (= user cancel) rethrows immediately',
      () async {
        final downloader = WhisperServerDownloader(
          fetcher: _UserCancelFetcher(),
          manifestLoader: _fakeManifestLoader(),
        );

        await expectLater(
          () => downloader.download(destDir: tempDir.path, gpuMode: 'auto'),
          throwsA(
            isA<DioException>()
                .having((e) => e.type, 'type', DioExceptionType.cancel)
                .having((e) => e.message, 'message', isNot('stalled')),
          ),
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers — fake manifest loader producing one binary per host platform/
// arch so the downloader's selector finds a match irrespective of the
// CI runner's actual GPU.
// ---------------------------------------------------------------------------

WhisperServerManifestLoader _fakeManifestLoader() {
  const manifest = '''
{
  "schema_version": 1,
  "whisper_server_tag": "whisper-server-test",
  "whisper_cpp_release": "test",
  "generated_at": "2026-01-01T00:00:00Z",
  "binaries": [
    {"platform":"macos","arch":"arm64","backend":"metal","url":"http://example.com/metal.zip","size_bytes":1000,"source":"whispaste"},
    {"platform":"macos","arch":"arm64","backend":"cpu","url":"http://example.com/cpu-mac.zip","size_bytes":1000,"source":"whispaste"},
    {"platform":"windows","arch":"x64","backend":"vulkan","url":"http://example.com/vulkan.zip","size_bytes":1000,"source":"whispaste"},
    {"platform":"windows","arch":"x64","backend":"cuda12","url":"http://example.com/cuda.zip","size_bytes":1000,"source":"upstream"},
    {"platform":"windows","arch":"x64","backend":"cpu","url":"http://example.com/cpu-win.zip","size_bytes":1000,"source":"upstream"},
    {"platform":"linux","arch":"x64","backend":"cpu","url":"http://example.com/cpu-linux.zip","size_bytes":1000,"source":"upstream"}
  ]
}
''';
  // Force every remote attempt to short-circuit so the loader falls back
  // to the bundled JSON without waiting on real network timeouts.
  final offlineDio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'offline test',
            ),
          );
        },
      ),
    );
  return WhisperServerManifestLoader(
    dio: offlineDio,
    bundleReader: () async => manifest,
  );
}

class _AlwaysStalledFetcher extends HttpModelFetcher {
  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.cancel,
      message: 'stalled',
    );
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

class _UserCancelFetcher extends HttpModelFetcher {
  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.cancel,
      message: 'cancelled',
    );
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

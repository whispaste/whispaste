/// Unit tests for the [HttpStallDetector] surface in [HttpModelFetcher].
///
/// Covers:
///   1. Stall-detection — a stream that goes silent for ≥ stallThreshold is
///      resumed within the retry budget, afterwards it ends with
///      `DioException(type: receiveTimeout, message: 'stalled')`.
///   2. No-stall — a stream that always pushes a chunk within the threshold
///      runs to completion.
///   3. `describeDioError` returns the exact PRD-specified German strings.
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

/// Answers each request with the next of [bodies] and records it.
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.requests, this.bodies);
  final List<RequestOptions> requests;
  final List<ResponseBody> bodies;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return bodies.removeAt(0);
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
    test('stream that goes silent past stallThreshold, with no retry left, '
        'ends with DioException(receiveTimeout, message: "stalled"), not '
        'with a cancel the UI would read as the user\'s', () async {
      // A controllable stream: emit 2 small chunks, then go silent.
      final controller = StreamController<List<int>>();
      final body = _streamBody(controller.stream, contentLength: 1000);
      final dio = Dio()..httpClientAdapter = _StreamAdapter(body);

      final fetcher = HttpModelFetcher(
        dio: dio,
        stallThreshold: const Duration(milliseconds: 300),
        stallCheckInterval: const Duration(milliseconds: 50),
        retryBackoff: const [],
      );

      final destPath = p.join(tempDir.path, 'model.bin');
      final fetchFuture = fetcher.fetch(
        url: 'https://huggingface.co/model.bin',
        destPath: destPath,
        expectedSize: 1000,
      );

      // Emit a couple of chunks within the first window.
      controller.add(List.filled(10, 0x01));
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

      expect(caught, isNotNull, reason: 'Expected a DioException');
      expect(caught!.type, DioExceptionType.receiveTimeout);
      expect(caught.message, 'stalled');
      expect(
        describeDioError(caught),
        'Verbindung steht — kein Datenfortschritt seit 30 s.',
      );

      // Clean up the still-open controller (the listener was cancelled
      // by Dio, but we still own the source).
      await controller.close();
    });

    test('a stall within the retry budget is resumed with a Range request '
        'and the download completes', () async {
      final first = StreamController<List<int>>();
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _SequenceAdapter(requests, [
          _streamBody(first.stream, contentLength: 100),
          ResponseBody(
            Stream.value(Uint8List.fromList(List.filled(60, 2))),
            206,
            headers: {
              'content-length': ['60'],
              'content-range': ['bytes 40-99/100'],
            },
          ),
        ]);
      final fetcher = HttpModelFetcher(
        dio: dio,
        stallThreshold: const Duration(milliseconds: 200),
        stallCheckInterval: const Duration(milliseconds: 50),
        retryBackoff: const [Duration(milliseconds: 10)],
      );
      final destPath = p.join(tempDir.path, 'model.bin');
      final future = fetcher.fetch(
        url: 'https://huggingface.co/model.bin',
        destPath: destPath,
        expectedSize: 100,
      );
      first.add(List.filled(40, 1));

      await future;
      expect(await File(destPath).length(), 100);
      expect(requests, hasLength(2));
      expect(requests.last.headers['Range'], 'bytes=40-');
      await first.close();
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
          url: 'https://huggingface.co/model.bin',
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
    RequestOptions opts() => RequestOptions(path: 'https://huggingface.co/x');

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
}

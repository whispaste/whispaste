/// HTTP file fetcher — encapsulates Dio-based streaming downloads with
/// resume, retry, and cancellation support.
///
/// Extracted from [ModelDownloadNotifier] so that the download transport
/// layer is independently testable and reusable for future binary downloads
/// (e.g. STT-server binary, update payloads).
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sentry_dio/sentry_dio.dart';

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';

final _log = AppLogger('HttpModelFetcher');

// ---------------------------------------------------------------------------
// Stall detection — public so call-site retry-loops can detect the cause
// ---------------------------------------------------------------------------

/// `DioException.message` value set by the stall-detector when it cancels
/// a download because the byte stream went silent for longer than
/// [HttpModelFetcher.stallThreshold].
///
/// Call sites that want to distinguish a user-initiated cancel from a
/// stall-cancel must compare against this constant, **not** an inline
/// string literal.
const String httpStallCancelMessage = 'stalled';

/// Translates a [DioException] into a user-facing German string.
///
/// Source of truth: `.scratch/reliability-sprint/prd.md` — Modul 3.
/// Adding a new branch here is a PRD change; reviewers must reject silent
/// drift.
String describeDioError(DioException e) {
  if (e.type == DioExceptionType.cancel &&
      e.message == httpStallCancelMessage) {
    return 'Verbindung steht — kein Datenfortschritt seit 30 s.';
  }
  if (e.response == null) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout =>
        'Verbindungsaufbau dauerte zu lange.',
      DioExceptionType.receiveTimeout => 'Server antwortet nicht mehr.',
      DioExceptionType.connectionError => 'Keine Internetverbindung.',
      _ => 'Netzwerkfehler: ${e.type.name}',
    };
  }
  return 'HTTP ${e.response!.statusCode}: ${e.message ?? "unbekannter Fehler"}';
}

// ---------------------------------------------------------------------------
// Progress event
// ---------------------------------------------------------------------------

/// Progress snapshot emitted by [HttpModelFetcher.fetch].
class FetchProgress {
  const FetchProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.speedBytesPerSec,
    this.etaSeconds,
  });

  final int bytesReceived;
  final int totalBytes;
  final double speedBytesPerSec;

  /// Estimated seconds remaining. Null when the total is unknown or speed is 0.
  final int? etaSeconds;

  int get progressPercent =>
      totalBytes > 0 ? (bytesReceived * 100 ~/ totalBytes).clamp(0, 99) : 0;
}

// ---------------------------------------------------------------------------
// HttpModelFetcher
// ---------------------------------------------------------------------------

/// Downloads a single file from [url] to [destPath] with resume support.
///
/// Public interface:
/// - [fetch]: starts (or resumes) a download and streams progress events.
/// - [cancel]: cancels the active fetch.
///
/// Dio is injected via the constructor so callers can substitute a
/// pre-configured or mock instance in tests.
class HttpModelFetcher {
  /// Creates a fetcher backed by [dio].
  ///
  /// If [dio] is omitted, a default instance with sensible timeouts and
  /// the WhisPaste user-agent header is created.
  ///
  /// [_stallThreshold] is the maximum allowed gap between received chunks
  /// before the in-flight download is cancelled with
  /// `DioException(cancel, '$httpStallCancelMessage')`. Default 30 s — the
  /// PRD-pinned value. Tests override this to keep runtimes in milliseconds.
  ///
  /// [_stallCheckInterval] is how often the detector wakes to compare „now"
  /// against the timestamp of the last received chunk. Default 5 s — the
  /// PRD-pinned value. Must be ≤ [_stallThreshold].
  HttpModelFetcher({
    Dio? dio,
    this._stallThreshold = const Duration(seconds: 30),
    this._stallCheckInterval = const Duration(seconds: 5),
  }) : _dio = dio ?? _defaultDio();

  final Dio _dio;
  CancelToken? _cancelToken;

  /// Maximum gap between received chunks before a stall-cancel fires.
  ///
  /// Configurable via the constructor so tests can use sub-second
  /// thresholds without 30 s real-time waits. Production callers must
  /// rely on the default.
  final Duration _stallThreshold;

  /// Stall-detector poll interval. See [_stallThreshold].
  final Duration _stallCheckInterval;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Downloads [url] to [destPath], resuming any partial `<destPath>.tmp` file.
  ///
  /// [expectedSize] is used as a fallback when the server does not return a
  /// `Content-Length` header.
  ///
  /// Progress events are emitted to [onProgress] at most every 500 ms.
  ///
  /// Throws [DioException] on network errors or if [cancel] is called.
  /// Throws [FileSystemException] on I/O errors.
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    _cancelToken = CancelToken();
    await _fetchInternal(
      url: url,
      destPath: destPath,
      expectedSize: expectedSize,
      onProgress: onProgress,
    );
  }

  /// Cancels the in-progress fetch, if any.
  ///
  /// The [fetch] future will throw a [DioException] with type
  /// [DioExceptionType.cancel].
  void cancel([String reason = 'cancelled']) {
    _cancelToken?.cancel(reason);
    _cancelToken = null;
  }

  // -----------------------------------------------------------------------
  // Internal
  // -----------------------------------------------------------------------

  Future<void> _fetchInternal({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    final tmpPath = '$destPath.tmp';
    int startByte = 0;
    final tmpFile = File(tmpPath);

    // Resume partial download.
    if (tmpFile.existsSync()) {
      startByte = tmpFile.lengthSync();
      _log.info('Resuming download from byte $startByte');
    }

    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: _cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
      ),
    );

    final totalBytes = _resolveTotal(response, startByte, expectedSize);

    final sink = tmpFile.openWrite(
      mode: startByte > 0 ? FileMode.append : FileMode.write,
    );
    int received = startByte;

    // Rolling speed tracker — sample every ~500 ms for a smooth 5 s window.
    final speedSamples = <_SpeedSample>[];
    var lastSpeedUpdate = DateTime.now();
    double currentSpeed = 0;
    int? currentEta;

    // Stall detector — fires `_cancelToken.cancel(httpStallCancelMessage)`
    // when no bytes have arrived for ≥ [_stallThreshold]. The outer retry
    // loop in WhisperServerDownloader recognises that message and treats
    // the failure as retriable; a user-initiated cancel uses any other
    // message and remains a hard abort.
    //
    // Note: Dio's `CancelToken.cancel(reason)` stores `reason` in
    // `DioException.error`, not `DioException.message`. To honour the
    // PRD contract (`e.message == 'stalled'`), the catch-block below
    // rewrites the message on stall-classified cancels.
    var lastByteAt = DateTime.now();
    var stallFired = false;
    final stallTimer = Timer.periodic(_stallCheckInterval, (_) {
      final silent = DateTime.now().difference(lastByteAt);
      if (silent >= _stallThreshold) {
        final ct = _cancelToken;
        if (ct != null && !ct.isCancelled) {
          _log.warning(
            'HTTP download stalled for ${silent.inSeconds}s — cancelling',
          );
          stallFired = true;
          ct.cancel(httpStallCancelMessage);
        }
      }
    });

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        lastByteAt = DateTime.now();

        final now = DateTime.now();
        final sinceLastUpdate = now.difference(lastSpeedUpdate);

        if (sinceLastUpdate.inMilliseconds >= 500) {
          lastSpeedUpdate = now;
          speedSamples.add(_SpeedSample(now, received));
          final cutoff = now.subtract(const Duration(seconds: 5));
          speedSamples.removeWhere((s) => s.time.isBefore(cutoff));

          if (speedSamples.length >= 2) {
            final first = speedSamples.first;
            final elapsed = now.difference(first.time).inMilliseconds;
            if (elapsed > 0) {
              currentSpeed = (received - first.bytes) * 1000 / elapsed;
              final remaining = totalBytes > 0 ? totalBytes - received : 0;
              currentEta = currentSpeed > 0
                  ? (remaining / currentSpeed).ceil()
                  : null;
            }
          }

          onProgress?.call(
            FetchProgress(
              bytesReceived: received,
              totalBytes: totalBytes,
              speedBytesPerSec: currentSpeed,
              etaSeconds: totalBytes > 0 ? currentEta : null,
            ),
          );
        }
      }
      await sink.flush();
    } on DioException catch (e) {
      // Translate a stall-classified cancel into the PRD-contract shape:
      // `DioException(cancel, message: httpStallCancelMessage)`. Dio's
      // own factory writes the cancel reason into `.error` and overwrites
      // `.message`, so the outer retry-loop wouldn't recognise the stall
      // without this rewrite.
      if (stallFired && e.type == DioExceptionType.cancel) {
        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: DioExceptionType.cancel,
          error: e.error,
          stackTrace: e.stackTrace,
          message: httpStallCancelMessage,
        );
      }
      rethrow;
    } finally {
      stallTimer.cancel();
      await sink.close();
    }

    // Atomic rename.
    if (File(destPath).existsSync()) {
      await File(destPath).delete();
    }
    await tmpFile.rename(destPath);
  }

  int _resolveTotal(Response<ResponseBody> resp, int start, int expected) {
    final cl = resp.headers['content-length'];
    if (cl != null && cl.isNotEmpty) {
      final parsed = int.tryParse(cl.first);
      if (parsed != null) return start + parsed;
    }
    return expected;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [Dio] instance with the standard app User-Agent header and the
/// Sentry interceptor attached (`captureFailedRequests: false`).
///
/// Used by both [HttpModelFetcher] and [UpdateService] to avoid duplicating
/// the Dio setup pattern. Callers supply their own timeouts.
Dio buildDioWithSentry({
  required Duration connectTimeout,
  required Duration receiveTimeout,
}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {'User-Agent': appUserAgent},
    ),
  );
  // Sentry MUST be the last interceptor added — it wraps existing ones.
  dio.addSentry(captureFailedRequests: false);
  return dio;
}

Dio _defaultDio() => buildDioWithSentry(
  connectTimeout: const Duration(seconds: 30),
  receiveTimeout: const Duration(minutes: 10),
);

class _SpeedSample {
  const _SpeedSample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}

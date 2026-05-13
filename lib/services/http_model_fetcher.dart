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

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';

final _log = AppLogger('HttpModelFetcher');

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
  HttpModelFetcher({Dio? dio}) : _dio = dio ?? _defaultDio();

  final Dio _dio;
  CancelToken? _cancelToken;

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

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;

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
    } finally {
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

Dio _defaultDio() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
    headers: {'User-Agent': appUserAgent},
  ),
);

class _SpeedSample {
  const _SpeedSample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}

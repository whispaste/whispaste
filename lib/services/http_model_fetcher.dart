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
import 'package:path/path.dart' as p;
import 'package:sentry_dio/sentry_dio.dart';

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';
import 'download_allowlist.dart';
import 'download_fragment_guard.dart';
import 'download_tls_failure.dart';
import 'file_verification_service.dart';
import 'tmp_reaper.dart';

final _log = AppLogger('HttpModelFetcher');

/// HTTP statuses that mean "try again later" rather than "this source is
/// wrong": rate limit (Hugging Face answers 429 to bursts) and passing
/// gateway/server errors.
const Set<int> kTransientHttpStatuses = {408, 429, 500, 502, 503, 504};

/// Longest wait a `Retry-After` header may impose before the same source is
/// asked again; a longer one moves on (or fails) instead of freezing the UI.
const Duration kMaxRetryAfter = Duration(seconds: 30);

/// The pause before retrying a transient HTTP error: the server's
/// `Retry-After` in seconds when present (capped at [kMaxRetryAfter]),
/// otherwise [backoff].
Duration transientRetryDelay({
  required String? retryAfter,
  required Duration backoff,
}) {
  final seconds = int.tryParse(retryAfter?.trim() ?? '');
  if (seconds == null || seconds < 0) return backoff;
  final wanted = Duration(seconds: seconds);
  return wanted > kMaxRetryAfter ? kMaxRetryAfter : wanted;
}

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
/// Adding a new branch here is a deliberate behavior change; reviewers must reject silent
/// drift.
String describeDioError(DioException e) {
  if (e.message == httpStallCancelMessage) {
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
/// Every URL, including each redirect target, must pass the host allowlist in
/// `download_allowlist.dart`; a disallowed one throws
/// [DownloadUrlRejectedException] before any byte is written.
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
  ///
  /// [_retryBackoff] holds the pauses before each automatic resume after
  /// the connection drops mid-transfer; its length is the retry budget.
  HttpModelFetcher({
    Dio? dio,
    this.confirmedHosts,
    this._stallThreshold = const Duration(seconds: 30),
    this._stallCheckInterval = const Duration(seconds: 5),
    this._retryBackoff = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 9),
    ],
  }) : _dio = dio ?? _defaultDio();

  final Dio _dio;

  /// Hosts the user confirmed for a model of their own (#1789), allowed next
  /// to the fixed allowlist. Null for every catalog download.
  final Set<String>? confirmedHosts;

  /// The token of the running [fetch]. [cancel] cancels it; every request
  /// attempt gets its own child token, so a stall can end one attempt (and be
  /// resumed) without ending the whole download.
  CancelToken? _cancelToken;

  /// Set by [cancel]; also ends a [fetchVerified] that is still waiting for
  /// another download of the same file to finish.
  bool _cancelRequested = false;

  /// 1-based number of the source the last [fetchVerified] tried last, so a
  /// failure can name it in the usage statistics (#1791) without its URL.
  /// `null` before the first source was tried (lock, preparation).
  int? get lastSourceNumber => _lastSourceNumber;
  int? _lastSourceNumber;

  /// Fetches in flight per destination, across fetcher instances: a second
  /// fetch of the same file waits until the first has closed its `.tmp`, so
  /// two writers never append to one fragment (UIA-RT-05).
  static final Map<String, Future<void>> _inFlight = {};

  /// Same for [fetchVerified], which also covers the hash check: a second
  /// caller waits and then finds the verified file in place.
  static final Map<String, Future<void>> _verifiedInFlight = {};

  /// Maximum gap between received chunks before a stall-cancel fires.
  ///
  /// Configurable via the constructor so tests can use sub-second
  /// thresholds without 30 s real-time waits. Production callers must
  /// rely on the default.
  final Duration _stallThreshold;

  /// Stall-detector poll interval. See [_stallThreshold].
  final Duration _stallCheckInterval;

  final List<Duration> _retryBackoff;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Downloads [url] to [destPath], resuming any partial `<destPath>.tmp` file.
  ///
  /// [expectedSize] is the pinned length. A body that ends short is resumed
  /// like a dropped connection, one that is too long restarts once from byte
  /// 0 and then throws [DownloadLengthException]; a wrong-length file is never
  /// renamed to [destPath]. A `.tmp` that already has exactly this length is
  /// renamed without a request. Without a pinned size (<= 0) the server's
  /// `Content-Length` is the target, if present.
  ///
  /// Progress events are emitted to [onProgress] at most every 500 ms.
  ///
  /// A connection that drops mid-transfer is resumed from the partial file
  /// up to `retryBackoff.length` times before the fetch gives up.
  ///
  /// Throws [DioException] on network errors (a drop that outlasts the retry
  /// budget as [DioExceptionType.connectionError]) or if [cancel] is called.
  /// Throws [FileSystemException] on I/O errors.
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    final token = CancelToken();
    _cancelToken = token;
    final key = File(destPath).absolute.path;
    var waited = false;
    for (
      var previous = _inFlight[key];
      previous != null;
      previous = _inFlight[key]
    ) {
      waited = true;
      await previous;
    }
    if (token.isCancelled) throw token.cancelError!;
    // A second fetch of the same file (a repeated click, or another screen
    // starting the same model) waited for the first one. Downloading again
    // would replace the file while the first caller still verifies it, so
    // the finished result is reused when it has the expected length.
    if (waited && expectedSize > 0) {
      final dest = File(destPath);
      if (dest.existsSync() && dest.lengthSync() == expectedSize) {
        _log.info('Reusing the download that just finished: $destPath');
        return;
      }
    }
    final done = Completer<void>();
    _inFlight[key] = done.future;
    try {
      await _fetchWithRetries(
        token: token,
        url: url,
        destPath: destPath,
        expectedSize: expectedSize,
        onProgress: onProgress,
      );
    } finally {
      _inFlight.remove(key);
      done.complete();
    }
  }

  /// Downloads one registry file from an ordered list of [sources] and
  /// verifies it against the pinned [expectedSize] and [expectedSha256].
  ///
  /// Every source must serve the identical file; each one is checked against
  /// the same hash, so a mirror can never deliver anything else. The next
  /// source is tried when one answers with an HTTP error (after the retries
  /// of [fetch] for 429/5xx), stalls or drops past the retry budget, sends a
  /// wrong length, redirects off the allowlist or delivers bytes with another
  /// hash. A cancel, a storage error and a TLS failure end the download at
  /// once: another source cannot fix those. The source used is logged.
  ///
  /// Before the first request it
  /// - waits for any other download of [destPath], in this process or in
  ///   another WhisPaste process ([DownloadFileLock]);
  /// - keeps a finished, verified [destPath] (nothing is downloaded);
  /// - drops a partial `.tmp` that belongs to another file version
  ///   ([prepareFragmentIdentity]), so a resume across app restarts can only
  ///   append bytes of this exact file.
  ///
  /// [onVerifying] runs before each hash check (the UI shows "verifying").
  /// Returns the URL the file came from, or null when the file was already
  /// in place.
  ///
  /// Throws [DownloadChecksumException] when the last source delivered a
  /// file with another hash, otherwise the last source's error.
  Future<String?> fetchVerified({
    required List<String> sources,
    required String destPath,
    required int expectedSize,
    required String expectedSha256,
    void Function(FetchProgress)? onProgress,
    void Function()? onVerifying,
    FileVerificationService verifier = const FileVerificationService(),
  }) async {
    assert(sources.isNotEmpty, 'fetchVerified needs at least one source');
    _lastSourceNumber = null;
    return withDestinationLock(destPath, () async {
      final dest = File(destPath);
      if (dest.existsSync()) {
        if (dest.lengthSync() == expectedSize) {
          onVerifying?.call();
          final existing = await verifier.verifyStamped(dest, expectedSha256);
          if (existing is VerificationOk) {
            await clearFragmentIdentity(destPath);
            _log.info('${p.basename(destPath)} is already in place');
            return null;
          }
        }
        await _deleteQuietly(dest);
      }

      await prepareFragmentIdentity(
        destPath: destPath,
        sha256: expectedSha256,
        sizeBytes: expectedSize,
      );

      Object? lastError;
      StackTrace? lastStack;
      for (var i = 0; i < sources.length; i++) {
        final url = sources[i];
        _lastSourceNumber = i + 1;
        final label =
            'source ${i + 1}/${sources.length} '
            '(${Uri.tryParse(url)?.host ?? 'invalid'})';
        if (_cancelRequested) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: url),
            reason: 'user cancelled',
          );
        }
        try {
          await fetch(
            url: url,
            destPath: destPath,
            expectedSize: expectedSize,
            onProgress: onProgress,
          );
        } on DioException catch (e, s) {
          if (e.type == DioExceptionType.cancel || _cancelRequested) rethrow;
          if (isTlsDownloadFailure(e)) rethrow;
          if (e.error is FileSystemException) rethrow;
          _log.warning(
            '${p.basename(destPath)}: $label failed (${describeDioError(e)})',
          );
          lastError = e;
          lastStack = s;
          continue;
        } on DownloadLengthException catch (e, s) {
          _log.warning('${p.basename(destPath)}: $label failed ($e)');
          lastError = e;
          lastStack = s;
          continue;
        } on DownloadWrongResponseException catch (e, s) {
          _log.warning('${p.basename(destPath)}: $label failed ($e)');
          lastError = e;
          lastStack = s;
          continue;
        } on DownloadUrlRejectedException catch (e, s) {
          _log.warning('${p.basename(destPath)}: $label failed ($e)');
          lastError = e;
          lastStack = s;
          continue;
        }

        // [fetch] already refused any other length; the hash covers the rest.
        onVerifying?.call();
        final check = await verifier.verifyStamped(dest, expectedSha256);
        if (check is VerificationOk) {
          await clearFragmentIdentity(destPath);
          _log.info('${p.basename(destPath)} downloaded from $label');
          return url;
        }
        if (check case VerificationIoError(
          :final error,
        ) when dest.existsSync()) {
          // Unreadable right after writing: a storage problem, not the
          // source's fault.
          throw error is FileSystemException
              ? error
              : FileSystemException('$error', destPath);
        }
        _log.warning(
          '${p.basename(destPath)}: $label delivered a file that fails the '
          'pinned SHA-256 — deleted',
        );
        await _deleteQuietly(dest);
        lastError = DownloadChecksumException(p.basename(destPath));
        lastStack = StackTrace.current;
      }
      Error.throwWithStackTrace(lastError!, lastStack!);
    });
  }

  /// Runs [body] as the only download of [destPath]: other callers in this
  /// process wait in line, another WhisPaste process is kept out by a
  /// [DownloadFileLock]. A [cancel] during the wait ends it with a
  /// `DioException(cancel)`, the shape every caller already treats as the
  /// user's cancel.
  Future<T> withDestinationLock<T>(
    String destPath,
    Future<T> Function() body,
  ) async {
    _cancelRequested = false;
    final key = File(destPath).absolute.path;
    for (
      var previous = _verifiedInFlight[key];
      previous != null;
      previous = _verifiedInFlight[key]
    ) {
      await previous;
    }
    if (_cancelRequested) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: destPath),
        reason: 'user cancelled',
      );
    }
    final done = Completer<void>();
    _verifiedInFlight[key] = done.future;
    DownloadFileLock? lock;
    try {
      try {
        lock = await DownloadFileLock.acquire(
          destPath,
          isCancelled: () => _cancelRequested,
        );
      } on DownloadLockCancelled {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: destPath),
          reason: 'user cancelled',
        );
      }
      return await body();
    } finally {
      await lock?.release();
      _verifiedInFlight.remove(key);
      done.complete();
    }
  }

  Future<void> _fetchWithRetries({
    required CancelToken token,
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    // Protect the fragment from sibling sweeps while it can still be resumed.
    // It stays registered after a failure or cancel (the next attempt resumes
    // it) and is released only once the atomic rename has succeeded.
    registerResumableFragment('$destPath.tmp');
    var restartedAfterOverlong = false;
    for (var attempt = 0; ; attempt++) {
      // One child token per attempt: the stall detector ends only this
      // attempt (which is then resumed), a user cancel on [token] reaches
      // every attempt.
      if (token.isCancelled) throw token.cancelError!;
      final attemptToken = CancelToken();
      unawaited(
        token.whenCancel.then((e) {
          if (!attemptToken.isCancelled) attemptToken.cancel(e.error);
        }),
      );
      try {
        await _fetchInternal(
          token: attemptToken,
          url: url,
          destPath: destPath,
          expectedSize: expectedSize,
          onProgress: onProgress,
        );
        releaseResumableFragment('$destPath.tmp');
        return;
      } on _BodyTooLong catch (tooLong) {
        // More bytes than the pinned size: the fragment is unusable. Start
        // over once from byte 0; a fresh download that is still too long is
        // reported, never renamed into place.
        if (restartedAfterOverlong) {
          await _deleteQuietly(File('$destPath.tmp'));
          throw DownloadLengthException(
            expected: tooLong.expected,
            actual: tooLong.actual,
          );
        }
        restartedAfterOverlong = true;
        _log.warning(
          'Download longer than expected (${tooLong.actual} > '
          '${tooLong.expected} bytes) — restarting from byte 0',
        );
        await _deleteQuietly(File('$destPath.tmp'));
      } on _TransferInterrupted catch (interrupted) {
        if (attempt >= _retryBackoff.length) {
          if (interrupted.stalled) {
            // Deliberately not a cancel: callers treat a cancel as the
            // user's choice and go back to idle without a message, which
            // made a stalled download fail silently before.
            throw DioException(
              requestOptions: interrupted.requestOptions,
              type: DioExceptionType.receiveTimeout,
              error: interrupted.error,
              stackTrace: interrupted.stackTrace,
              message: httpStallCancelMessage,
            );
          }
          throw DioException.connectionError(
            requestOptions: interrupted.requestOptions,
            reason: '${interrupted.error}',
            error: interrupted.error,
            stackTrace: interrupted.stackTrace,
          );
        }
        _log.warning(
          'Download interrupted (${interrupted.error}) — resuming '
          '(retry ${attempt + 1}/${_retryBackoff.length})',
        );
        await Future<void>.delayed(_retryBackoff[attempt]);
        if (token.isCancelled) throw token.cancelError!;
      } on DioException catch (e) {
        // Rate limit (429) and passing server errors: wait and ask the same
        // source again before the caller moves on to the next source.
        final status = e.response?.statusCode;
        if (e.type != DioExceptionType.badResponse ||
            status == null ||
            !kTransientHttpStatuses.contains(status) ||
            attempt >= _retryBackoff.length) {
          rethrow;
        }
        final wait = transientRetryDelay(
          retryAfter: e.response?.headers.value('retry-after'),
          backoff: _retryBackoff[attempt],
        );
        _log.warning(
          'HTTP $status from ${Uri.tryParse(url)?.host} — retrying in '
          '${wait.inSeconds} s (${attempt + 1}/${_retryBackoff.length})',
        );
        await Future<void>.delayed(wait);
        if (token.isCancelled) throw token.cancelError!;
      }
    }
  }

  /// Cancels the in-progress fetch, if any.
  ///
  /// The [fetch] future will throw a [DioException] with type
  /// [DioExceptionType.cancel].
  void cancel([String reason = 'cancelled']) {
    _cancelRequested = true;
    _cancelToken?.cancel(reason);
    _cancelToken = null;
  }

  // -----------------------------------------------------------------------
  // Internal
  // -----------------------------------------------------------------------

  Future<void> _fetchInternal({
    required CancelToken token,
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    final tmpPath = '$destPath.tmp';
    final tmpFile = File(tmpPath);

    // Resume partial download.
    var startByte = tmpFile.existsSync() ? tmpFile.lengthSync() : 0;
    if (expectedSize > 0 && startByte > 0) {
      if (startByte == expectedSize) {
        // Fully downloaded earlier, only the rename never ran.
        _log.info('Partial file already complete — no download needed');
        await _promote(tmpFile, destPath);
        return;
      }
      if (startByte > expectedSize) {
        _log.warning(
          'Partial file longer than expected ($startByte > $expectedSize) '
          '— restarting from byte 0',
        );
        await _deleteQuietly(tmpFile);
        startByte = 0;
      }
    }
    if (startByte > 0) _log.info('Resuming download from byte $startByte');

    final (response, resolvedStartByte) = await _requestWithResumeRecovery(
      token: token,
      url: url,
      tmpFile: tmpFile,
      startByte: startByte,
    );
    startByte = _bodyStartByte(response, resolvedStartByte);

    // A captive portal, an error page or another file: refuse it before a
    // single byte reaches the fragment, so a resumable fragment stays clean.
    final wrong = wrongDownloadResponse(
      contentType: response.headers.value('content-type'),
      contentLength: response.headers.value('content-length'),
      contentEncoding: response.headers.value('content-encoding'),
      startByte: startByte,
      expectedSize: expectedSize,
    );
    if (wrong != null) {
      response.data?.stream.listen(null).cancel();
      throw DownloadWrongResponseException(wrong);
    }

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

    // Stall detector — cancels this attempt's [token] when no bytes have
    // arrived for ≥ [_stallThreshold]. The catch-block below turns that into
    // a [_TransferInterrupted], so the retry loop resumes from the partial
    // file; once the retry budget is spent the caller gets
    // `DioException(receiveTimeout, message: httpStallCancelMessage)`.
    var lastByteAt = DateTime.now();
    var stallFired = false;
    final stallTimer = Timer.periodic(_stallCheckInterval, (_) {
      final silent = DateTime.now().difference(lastByteAt);
      if (silent >= _stallThreshold && !token.isCancelled) {
        _log.warning(
          'HTTP download stalled for ${silent.inSeconds}s — resuming',
        );
        stallFired = true;
        token.cancel(httpStallCancelMessage);
      }
    });

    try {
      await for (final chunk in response.data!.stream) {
        final limit = expectedSize > 0 ? expectedSize : totalBytes;
        if (limit > 0 && received + chunk.length > limit) {
          throw _BodyTooLong(expected: limit, actual: received + chunk.length);
        }
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
    } on HttpException catch (e, s) {
      // Dio only maps connection failures up to the response headers; a
      // drop while the body streams arrives raw (Sentry 138737241, the
      // CDN closing a long model download).
      throw _TransferInterrupted(e, s, response.requestOptions);
    } on SocketException catch (e, s) {
      throw _TransferInterrupted(e, s, response.requestOptions);
    } on DioException catch (e, s) {
      // The stall detector ended this attempt: a silent connection is a
      // dropped one, so the retry loop resumes from the partial file.
      if (stallFired && e.type == DioExceptionType.cancel) {
        throw _TransferInterrupted(
          const HttpException(httpStallCancelMessage),
          s,
          response.requestOptions,
          stalled: true,
        );
      }
      rethrow;
    } finally {
      stallTimer.cancel();
      await sink.close();
    }

    // Never hand on a body of the wrong length. The pinned size wins; without
    // one the server's Content-Length decides.
    final target = expectedSize > 0 ? expectedSize : totalBytes;
    if (target > 0 && received != target) {
      if (received < target) {
        throw _TransferInterrupted(
          HttpException('Body ended after $received of $target bytes'),
          StackTrace.current,
          response.requestOptions,
        );
      }
      throw _BodyTooLong(expected: target, actual: received);
    }

    await _promote(tmpFile, destPath);
  }

  /// Atomic rename of the finished fragment onto [destPath].
  Future<void> _promote(File tmpFile, String destPath) async {
    if (File(destPath).existsSync()) {
      await File(destPath).delete();
    }
    await tmpFile.rename(destPath);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      _log.warning('Could not delete ${file.path}: $e');
    }
  }

  /// Issues the resumed (or fresh) GET for the download body.
  ///
  /// A resumed request (`startByte > 0`) can be rejected with 416 (Range
  /// Not Satisfiable) if the stale `.tmp` fragment is already >= the
  /// remote file's current size — e.g. the fragment finished but the
  /// atomic rename never ran, or the remote asset changed size underneath
  /// it. That offset never shrinks on its own, so every retry would hit
  /// the same 416 forever (FLUTTER_WHISPASTE-7Z: 50 occurrences over two
  /// months on the same 2 devices). On 416, drops the fragment and retries
  /// once as a fresh, non-resumed request.
  ///
  /// Returns the successful [Response] alongside the start byte actually
  /// used (0 if a 416 recovery happened).
  Future<(Response<ResponseBody>, int)> _requestWithResumeRecovery({
    required CancelToken token,
    required String url,
    required File tmpFile,
    required int startByte,
  }) async {
    try {
      final response = await getWithAllowlistedRedirects<ResponseBody>(
        _dio,
        url,
        cancelToken: token,
        confirmedHosts: confirmedHosts,
        options: Options(
          responseType: ResponseType.stream,
          headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
        ),
      );
      if (startByte > 0 && response.statusCode == 206) {
        final rangeStart = _contentRangeStart(response);
        if (rangeStart != null && rangeStart != startByte) {
          // Appending a different range would corrupt the file.
          _log.warning(
            'Server answered range starting at $rangeStart, asked for '
            '$startByte — restarting from byte 0',
          );
          response.data?.stream.listen(null).cancel();
          await _deleteQuietly(tmpFile);
          final fresh = await getWithAllowlistedRedirects<ResponseBody>(
            _dio,
            url,
            cancelToken: token,
            confirmedHosts: confirmedHosts,
            options: Options(responseType: ResponseType.stream),
          );
          return (fresh, 0);
        }
      }
      return (response, startByte);
    } on DioException catch (e) {
      if (startByte == 0 || e.response?.statusCode != 416) rethrow;
      _log.warning('Stale .tmp rejected with 416 — restarting from byte 0');
      await tmpFile.delete();
      final response = await getWithAllowlistedRedirects<ResponseBody>(
        _dio,
        url,
        cancelToken: token,
        confirmedHosts: confirmedHosts,
        options: Options(responseType: ResponseType.stream),
      );
      return (response, 0);
    }
  }

  /// The offset the body really starts at. A server that ignores Range answers
  /// 200 with the complete body; appending that to the partial file would
  /// corrupt the download, so the body is written from byte 0 instead.
  int _bodyStartByte(Response<ResponseBody> response, int requestedStart) {
    if (requestedStart == 0 || response.statusCode == 206) {
      return requestedStart;
    }
    _log.warning(
      'Server ignored Range (HTTP ${response.statusCode}) — restarting from byte 0',
    );
    return 0;
  }

  /// First byte of a `Content-Range: bytes a-b/total` header, or null when
  /// absent or unparsable.
  int? _contentRangeStart(Response<ResponseBody> response) {
    final header = response.headers['content-range'];
    if (header == null || header.isEmpty) return null;
    final match = RegExp(r'bytes\s+(\d+)-').firstMatch(header.first);
    return match == null ? null : int.tryParse(match.group(1)!);
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

/// The connection dropped while the body was streaming; the bytes received
/// so far are in the `.tmp` file, so [HttpModelFetcher.fetch] can resume.
class _TransferInterrupted implements Exception {
  const _TransferInterrupted(
    this.error,
    this.stackTrace,
    this.requestOptions, {
    this.stalled = false,
  });

  final IOException error;

  /// The stall detector ended the attempt (no bytes for the threshold).
  final bool stalled;
  final StackTrace stackTrace;
  final RequestOptions requestOptions;
}

/// The body held more bytes than the pinned size.
class _BodyTooLong implements Exception {
  const _BodyTooLong({required this.expected, required this.actual});

  final int expected;
  final int actual;
}

/// A download finished (also after one restart from byte 0) with a length
/// other than the expected one. The file is not put in place.
class DownloadLengthException implements Exception {
  const DownloadLengthException({required this.expected, required this.actual});

  final int expected;
  final int actual;

  @override
  String toString() =>
      'Downloaded file size mismatch: expected $expected bytes, got $actual';
}

/// Why a download response is not the pinned file, or null when it may be.
///
/// An HTML or other text body is a web page (captive portal, login wall,
/// error page of a host that changed its layout), never a model file. A
/// declared length that does not match the remaining bytes of the pinned
/// file is another file. A compressed body's length says nothing about the
/// file, so it is not compared.
String? wrongDownloadResponse({
  required String? contentType,
  required String? contentLength,
  required String? contentEncoding,
  required int startByte,
  required int expectedSize,
}) {
  final type = contentType?.split(';').first.trim().toLowerCase() ?? '';
  if (type == 'text/html' || type == 'application/xhtml+xml') {
    return 'server sent a web page ($type) instead of the file';
  }
  final encoding = contentEncoding?.trim().toLowerCase() ?? '';
  final length = int.tryParse(contentLength?.trim() ?? '');
  if (expectedSize > 0 &&
      length != null &&
      (encoding.isEmpty || encoding == 'identity') &&
      startByte + length != expectedSize) {
    return 'server announced ${startByte + length} bytes, '
        'the pinned file has $expectedSize';
  }
  return null;
}

/// A source answered with something that is not the pinned file
/// ([wrongDownloadResponse]). Nothing was written; the next source is tried.
class DownloadWrongResponseException implements Exception {
  const DownloadWrongResponseException(this.reason);

  final String reason;

  @override
  String toString() => 'Wrong download response: $reason';
}

/// Every source of [HttpModelFetcher.fetchVerified] was tried and the last
/// one delivered a file whose SHA-256 differs from the registry. The file was
/// deleted; nothing is put in place.
class DownloadChecksumException implements Exception {
  const DownloadChecksumException(this.filename);

  final String filename;

  @override
  String toString() =>
      'Downloaded file failed checksum verification: $filename';
}

class _SpeedSample {
  const _SpeedSample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}

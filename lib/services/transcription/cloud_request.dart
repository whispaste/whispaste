import 'package:http/http.dart' as http;

import 'transcriber_exception.dart';

/// Uplink speed the timeout must still allow for: 0.5 Mbit/s, a slow
/// connection. A fixed timeout cut off a 19 MB OpenAI slice on such a line.
const int kCloudMinUplinkBytesPerSecond = 62500;

/// Time every cloud request gets regardless of its size (server latency).
const Duration kCloudRequestBaseTimeout = Duration(seconds: 60);

/// Upper bound for one request, so a hung connection still ends.
const Duration kCloudRequestMaxTimeout = Duration(minutes: 40);

/// Timeout for one request whose body is [bodyBytes] long: the base plus the
/// time the upload needs at [kCloudMinUplinkBytesPerSecond], capped at
/// [kCloudRequestMaxTimeout]. Small dictations keep the 60 s base.
Duration cloudRequestTimeout(int bodyBytes) {
  final upload = Duration(seconds: bodyBytes ~/ kCloudMinUplinkBytesPerSecond);
  final total = kCloudRequestBaseTimeout + upload;
  return total > kCloudRequestMaxTimeout ? kCloudRequestMaxTimeout : total;
}

/// Attempts per cloud request: the first try and two retries.
const int kCloudMaxAttempts = 3;

/// Wait before the first retry; it doubles with every further retry.
const Duration kCloudRetryBaseDelay = Duration(seconds: 2);

/// Longest wait between two attempts, also when the server asks for more.
const Duration kCloudRetryMaxDelay = Duration(seconds: 30);

/// Whether a failure of this kind may succeed on a later attempt. Quota,
/// authentication and rejected requests fail the same way again.
bool isRetryableCloudFailure(TranscriberFailureReason reason) =>
    reason == TranscriberFailureReason.rateLimited ||
    reason == TranscriberFailureReason.serverError ||
    reason == TranscriberFailureReason.timeout;

/// Wait before the retry that follows the failed attempt number
/// [failedAttempt] (1-based): the server's `Retry-After` when it sent one,
/// otherwise the exponential backoff. Capped at [kCloudRetryMaxDelay].
Duration cloudRetryDelay(int failedAttempt, Duration? retryAfter) {
  final backoff = kCloudRetryBaseDelay * (1 << (failedAttempt - 1));
  final delay = retryAfter ?? backoff;
  return delay > kCloudRetryMaxDelay ? kCloudRetryMaxDelay : delay;
}

Future<void> _sleep(Duration delay) => Future<void>.delayed(delay);

/// Runs [attempt] until it succeeds, fails with a non-retryable reason, or
/// the [kCloudMaxAttempts] are used up; then the last failure is rethrown.
///
/// [attempt] builds its request again on every call, because a request can
/// only be sent once. Before each attempt [isCancelled] is checked; a
/// cancelled retry throws [TranscriberFailureReason.cancelled] instead.
Future<T> retryCloudRequest<T>(
  Future<T> Function() attempt, {
  bool Function()? isCancelled,
  Future<void> Function(Duration delay) wait = _sleep,
}) async {
  for (var n = 1; ; n++) {
    if (isCancelled?.call() ?? false) {
      throw const TranscriberException(
        'Transcription cancelled.',
        reason: TranscriberFailureReason.cancelled,
      );
    }
    try {
      return await attempt();
    } on TranscriberException catch (e) {
      if (!isRetryableCloudFailure(e.reason) || n >= kCloudMaxAttempts) {
        rethrow;
      }
      await wait(cloudRetryDelay(n, e.retryAfter));
    }
  }
}

/// Status, body and the `Retry-After` wait of one cloud STT response.
class CloudSttResponse {
  const CloudSttResponse(this.status, this.body, {this.retryAfter});

  final int status;
  final String body;

  /// Seconds the server asked the client to wait, when it sent the header.
  final Duration? retryAfter;
}

/// Sends [request] for a cloud speech-to-text adapter and reads the whole
/// response body.
///
/// Without a [client] the request gets its own, closed right after. The
/// transcriber provider caches an adapter for the whole session, so it holds
/// no connection between requests and `release()` has nothing to close.
Future<CloudSttResponse> sendCloudSttRequest(
  http.BaseRequest request, {
  required Duration timeout,
  http.Client? client,
}) async {
  final effective = client ?? http.Client();
  try {
    // The timeout covers the whole exchange, body included: a server that
    // sends its headers and then stalls must not hang the dictation.
    return await _exchange(effective, request).timeout(timeout);
  } finally {
    if (client == null) effective.close();
  }
}

Future<CloudSttResponse> _exchange(
  http.Client client,
  http.BaseRequest request,
) async {
  final streamed = await client.send(request);
  final body = await streamed.stream.bytesToString();
  return CloudSttResponse(
    streamed.statusCode,
    body,
    retryAfter: _retryAfter(streamed.headers),
  );
}

Duration? _retryAfter(Map<String, String> headers) {
  final seconds = int.tryParse(headers['retry-after']?.trim() ?? '');
  return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
}

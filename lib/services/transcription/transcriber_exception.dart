import '../../core/logging/app_logger.dart';

/// Structured error from any [Transcriber] adapter.
class TranscriberException implements Exception, ReasonedError {
  const TranscriberException(
    this.message, {
    this.reason = TranscriberFailureReason.unknown,
    this.retryAfter,
    this.completedParts = const [],
  });

  final String message;
  @override
  final TranscriberFailureReason reason;

  /// Wait the server asked for before a retry (`Retry-After`), if it sent one.
  final Duration? retryAfter;

  /// Text of the slices of a split upload that finished before this failure,
  /// in slice order (an empty string for a slice without speech). A later
  /// attempt passes them back in and sends only the remaining slices.
  final List<String> completedParts;

  @override
  String toString() => 'TranscriberException($reason): $message';
}

enum TranscriberFailureReason {
  /// Backend not initialised or ready.
  notReady,

  /// Network or connection failure.
  networkError,

  /// API key missing or invalid (HTTP 401).
  authError,

  /// Quota used up for the account (HTTP 429 with a billing code, or
  /// `insufficient_quota`). A retry fails the same way.
  quotaExceeded,

  /// Rate limit hit (HTTP 429 without a billing code). Transient: retried,
  /// and the audio is kept when it still fails.
  rateLimited,

  /// Server-side failure (HTTP 5xx). Transient.
  serverError,

  /// Request timed out.
  timeout,

  /// The user's own endpoint cannot be reached (refused, unknown host, no
  /// answer). The audio is kept for a retry (W-M3).
  endpointUnreachable,

  /// The own endpoint has no such model loaded or installed (W-M3).
  modelMissing,

  /// The own endpoint answered, but not as an OpenAI-compatible service
  /// would, e.g. a wrong path or a response without the transcript (W-M3).
  badResponse,

  /// The own endpoint has no usable address or model name yet (W-M3).
  endpointNotConfigured,

  /// The user cancelled the transcription; no further requests are sent.
  cancelled,

  /// Catch-all for unexpected errors.
  unknown,
}

/// The error code of a failed transcription, as the pipeline and the retry
/// rules name it. Classified transcriber errors map to their reason; any other
/// error counts as a server failure, the pipeline's fallback.
String transcriptionErrorCode(Object error) {
  if (error is! TranscriberException) return 'stt_server_failed';
  return switch (error.reason) {
    TranscriberFailureReason.authError => 'cloud_auth_error',
    TranscriberFailureReason.quotaExceeded => 'cloud_quota_exceeded',
    TranscriberFailureReason.rateLimited => 'cloud_rate_limited',
    TranscriberFailureReason.serverError => 'cloud_server_error',
    TranscriberFailureReason.networkError => 'cloud_network_error',
    TranscriberFailureReason.timeout => 'cloud_timeout',
    TranscriberFailureReason.endpointUnreachable =>
      'custom_endpoint_unreachable',
    TranscriberFailureReason.modelMissing => 'custom_model_missing',
    TranscriberFailureReason.badResponse => 'custom_bad_response',
    TranscriberFailureReason.endpointNotConfigured =>
      'custom_endpoint_not_configured',
    TranscriberFailureReason.cancelled => 'cancelled',
    _ => error.message,
  };
}

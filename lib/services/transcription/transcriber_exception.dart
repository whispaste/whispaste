/// Structured error from any [Transcriber] adapter.
class TranscriberException implements Exception {
  const TranscriberException(
    this.message, {
    this.reason = TranscriberFailureReason.unknown,
  });

  final String message;
  final TranscriberFailureReason reason;

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

  /// Rate limit exceeded (HTTP 429).
  quotaExceeded,

  /// Request timed out.
  timeout,

  /// Catch-all for unexpected errors.
  unknown,
}

/// Pure interface for all STT transcriber adapters.
///
/// The abstract [Transcriber] class lives here so that concrete adapters
/// (Deepgram, OpenAI, local whisper) can import only this file and avoid
/// a circular dependency with the provider/factory layer.
library;

export 'transcriber_exception.dart';

/// Common interface for all STT adapters.
abstract class Transcriber {
  /// Ensures the backend is ready to accept transcription requests.
  ///
  /// For local whisper-server: starts subprocess if not running.
  /// For cloud: validates that an API key is configured.
  ///
  /// Throws [TranscriberException] on failure.
  Future<void> prepare();

  /// Transcribes [wavBytes] to text.
  ///
  /// Throws [TranscriberException] on any failure.
  Future<String> transcribe(List<int> wavBytes, {String? language});

  /// Releases resources held by the adapter.
  ///
  /// For local whisper-server: triggers stop/idle timer.
  /// For cloud: no-op (HTTP connections are stateless).
  void release();
}

/// Optional capability (IMP-PROG-2): an adapter that reports transcription
/// progress while it runs. [onProgress] gets fractions in `0..1`, monotone
/// within one call, and is never called after the returned future completes.
/// Adapters without it (cloud) stay indeterminate; callers probe with
/// `is ProgressReportingTranscriber`.
abstract class ProgressReportingTranscriber {
  Future<String> transcribeWithProgress(
    List<int> wavBytes, {
    String? language,
    void Function(double fraction)? onProgress,
  });
}

/// Optional capability: an adapter that can report the language the last
/// [Transcriber.transcribe] call decoded in (9.10). Only the local whisper
/// adapter has one; cloud adapters do not implement it.
abstract class LanguageReportingTranscriber {
  /// Whisper code such as `de`, or `null` when unknown.
  String? get lastDetectedLanguage;
}

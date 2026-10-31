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

/// Abstraction over all STT backends (local whisper-server, OpenAI, Groq, Deepgram).
///
/// [RecordingOrchestrator] calls [prepare] once before recording starts,
/// [transcribe] to convert WAV bytes to text, and [release] when done.
///
/// One adapter per [SttProviderType] value; selected by [transcriberProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import 'deepgram_transcriber.dart';
import 'groq_transcriber.dart';
import 'local_transcriber.dart';
import 'openai_transcriber.dart';

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

/// Selects the correct [Transcriber] adapter based on the current settings.
final transcriberProvider = Provider<Transcriber>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final providerType = settings?.sttProviderType ?? SttProviderType.onDevice;

  return switch (providerType) {
    SttProviderType.openAI => OpenAiTranscriber(ref: ref),
    SttProviderType.groq => GroqTranscriber(ref: ref),
    SttProviderType.deepgram => DeepgramTranscriber(ref: ref),
    SttProviderType.onDevice => LocalTranscriber(ref: ref),
  };
});

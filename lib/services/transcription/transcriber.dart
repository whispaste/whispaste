/// Abstraction over all STT backends (local whisper-server, OpenAI, Deepgram).
///
/// [RecordingOrchestrator] calls [prepare] once before recording starts,
/// [transcribe] to convert WAV bytes to text, and [release] when done.
///
/// One adapter per [SttProviderType] value; selected by [transcriberProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../stt/local_transcriber.dart' show LocalSttTranscriber;
import 'deepgram_transcriber.dart';
import 'openai_transcriber.dart';
import 'transcriber_interface.dart';

export 'transcriber_interface.dart';

/// Selects the correct [Transcriber] adapter based on the current settings.
final transcriberProvider = Provider<Transcriber>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final providerType = settings?.sttProviderType ?? SttProviderType.onDevice;

  return switch (providerType) {
    SttProviderType.openAI => OpenAiTranscriber(ref: ref),
    SttProviderType.deepgram => DeepgramTranscriber(ref: ref),
    SttProviderType.onDevice => LocalSttTranscriber(ref: ref),
  };
});

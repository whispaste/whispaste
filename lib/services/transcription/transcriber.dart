/// Abstraction over all STT backends (local whisper-server, OpenAI, Deepgram).
///
/// [RecordingOrchestrator] calls [prepare] once before recording starts,
/// [transcribe] to convert WAV bytes to text, and [release] when done.
///
/// One adapter per [SttProviderType] value; selected by [transcriberProvider].
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../path_service.dart' show sttModelPath;
import '../stt/local_transcriber.dart' show LocalSttTranscriber;
import '../stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelFilesExistSync, parakeetModelId;
import '../stt_parakeet/parakeet_transcriber.dart' show ParakeetTranscriber;
import '../system_speech/system_speech_channel.dart';
import '../system_speech/system_speech_status.dart';
import '../system_speech/system_speech_transcriber.dart';
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
    SttProviderType.customEndpoint => OpenAiTranscriber.customEndpoint(
      ref: ref,
    ),
    SttProviderType.deepgram => DeepgramTranscriber(ref: ref),
    SttProviderType.onDevice => switch (settings?.onDeviceEngine ??
        OnDeviceEngine.whisper) {
      OnDeviceEngine.whisper => LocalSttTranscriber(ref: ref),
      OnDeviceEngine.parakeet => ParakeetTranscriber(ref: ref),
      OnDeviceEngine.system =>
        systemSpeechOsSupported()
            ? SystemSpeechTranscriber(
                channel: ref.read(systemSpeechChannelProvider),
                fallback: () => _localFallback(ref),
                tempDirectory: () => Directory.systemTemp,
                fallbackModelId: () => _localFallbackModelId(ref),
                onFallback: (cause) =>
                    ref.read(systemSpeechFallbackProvider.notifier).show(cause),
                vocabulary: () => deepgramKeyterms(
                  ref.read(settingsProvider).value?.customVocabulary ?? '',
                ),
              )
            : LocalSttTranscriber(ref: ref),
    },
  };
});

/// The local engine that takes a recording the system engine cannot handle:
/// Whisper when its model is on disk, otherwise Parakeet when installed,
/// otherwise Whisper with its usual missing-model message.
Transcriber _localFallback(Ref ref) => _localFallbackUsesParakeet(ref)
    ? ParakeetTranscriber(ref: ref)
    : LocalSttTranscriber(ref: ref);

bool _localFallbackUsesParakeet(Ref ref) {
  final settings = ref.read(settingsProvider).value;
  final whisperPath = settings == null
      ? null
      : sttModelPath(settings.effectiveModelId);
  if (whisperPath != null && File(whisperPath).existsSync()) return false;
  return parakeetModelFilesExistSync();
}

/// The identity of the engine [_localFallback] picks, stored with the entry.
String _localFallbackModelId(Ref ref) => _localFallbackUsesParakeet(ref)
    ? parakeetModelId
    : (ref.read(settingsProvider).value ?? AppSettings.defaults)
          .effectiveModelId;

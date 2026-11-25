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
import '../stt_parakeet/parakeet_script_guard.dart';
import '../stt_parakeet/parakeet_transcriber.dart' show ParakeetTranscriber;
import '../system_speech/system_speech_channel.dart';
import '../system_speech/system_speech_status.dart';
import '../system_speech/system_speech_transcriber.dart';
import '../user_models/user_model_guards.dart';
import '../user_models/user_model_use.dart'
    show ownSpeechModelIdIn, userModelUseProvider;
import '../user_models/user_sherpa_runtime.dart' show UserSherpaTranscriber;
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
    SttProviderType.onDevice => _guardedOnDevice(
      ref,
      settings ?? AppSettings.defaults,
    ),
  };
});

/// The on-device adapter; an own model (#1789) gets the guard that hands a
/// failed recording to a checked model.
Transcriber _guardedOnDevice(Ref ref, AppSettings settings) {
  final plain = _onDevice(ref, settings);
  final ownId = ownSpeechModelIdIn(settings);
  if (ownId == null) return plain;
  return UserModelGuardedTranscriber(
    modelId: ownId,
    inner: plain,
    host: ref.read(userModelUseProvider),
    fallback: () =>
        _onDevice(ref, ref.read(settingsProvider).value ?? settings),
    fallbackModelId: () =>
        (ref.read(settingsProvider).value ?? settings).transcriptionModelId,
  );
}

Transcriber _onDevice(Ref ref, AppSettings settings) =>
    switch (settings.onDeviceEngine) {
      OnDeviceEngine.whisper => LocalSttTranscriber(ref: ref),
      OnDeviceEngine.parakeet => _scriptGuardedParakeet(ref),
      OnDeviceEngine.userModel => UserSherpaTranscriber(ref: ref),
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
    };

/// Parakeet with the script check (#2168): a result in a script none of the
/// user's languages uses goes to Whisper when its model is on disk.
Transcriber _scriptGuardedParakeet(Ref ref) {
  AppSettings current() =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;
  return ParakeetScriptGuardedTranscriber(
    inner: ParakeetTranscriber(ref: ref),
    languagesFor: (language) =>
        languagesForRequest(language, current().stt.autoDetectLanguages),
    whisperInstalled: () => _whisperModelOnDisk(current()),
    whisper: () => LocalSttTranscriber(ref: ref),
    whisperModelId: () => current().effectiveModelId,
    onNotice: (notice) =>
        ref.read(parakeetScriptNoticeProvider.notifier).show(notice),
  );
}

bool _whisperModelOnDisk(AppSettings settings) {
  final path = sttModelPath(settings.effectiveModelId);
  return path != null && File(path).existsSync();
}

/// The local engine that takes a recording the system engine cannot handle:
/// Whisper when its model is on disk, otherwise Parakeet when installed,
/// otherwise Whisper with its usual missing-model message.
Transcriber _localFallback(Ref ref) => _localFallbackUsesParakeet(ref)
    ? ParakeetTranscriber(ref: ref)
    : LocalSttTranscriber(ref: ref);

bool _localFallbackUsesParakeet(Ref ref) {
  final settings = ref.read(settingsProvider).value;
  if (settings != null && _whisperModelOnDisk(settings)) return false;
  return parakeetModelFilesExistSync();
}

/// The identity of the engine [_localFallback] picks, stored with the entry.
String _localFallbackModelId(Ref ref) => _localFallbackUsesParakeet(ref)
    ? parakeetModelId
    : (ref.read(settingsProvider).value ?? AppSettings.defaults)
          .effectiveModelId;

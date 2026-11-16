/// The speech part of the "Systemkarte" on the Übersicht: which engine, which
/// speech model and which microphone a dictation uses right now, and what is
/// missing. One pure function over the states the dock and Settings already
/// keep, so the card never asks the system anything of its own and the rules
/// are tested without widgets (#1567).
library;

import '../../services/microphone_selection_service.dart' show micDefaultLabel;
import '../config/selectable_speech_models.dart';
import '../config/settings_enums.dart';
import '../config/settings_provider.dart';
import '../recording/recording_state.dart' show SttServerState;

/// The state of the speech model a dictation would use.
enum OverviewModelState {
  /// Loaded and ready (Apple's engine: language asset installed).
  ready,

  /// Being loaded into the engine right now.
  loading,

  /// On disk, but not in memory; the next dictation loads it.
  loadsOnDictation,

  /// Not on disk; the status line above offers the download.
  notDownloaded,

  /// Being downloaded, see [OverviewSpeechSetup.downloadPercent].
  downloading,

  /// The last load failed.
  failed,

  /// The engine cannot write the language set in Settings.
  unavailable,

  /// A cloud provider: there is nothing to load on this device.
  cloud,
}

/// The microphone a dictation would record from.
enum OverviewMicState {
  /// The system default input, and at least one device is known.
  systemDefault,

  /// The device chosen in Settings, connected.
  device,

  /// The device chosen in Settings is not in the current device list.
  disconnected,

  /// The device list came back without any input device.
  noneFound,

  /// The system refused WhisPaste the microphone.
  noAccess,
}

/// What the card shows for speech: one value per row, decided here.
class OverviewSpeechSetup {
  const OverviewSpeechSetup({
    required this.engine,
    required this.modelId,
    required this.modelState,
    required this.micState,
    this.downloadPercent,
    this.micName,
  });

  final SpeechModelEngine engine;

  /// The model the dictation uses, as stored: the Whisper id, the fixed
  /// Parakeet/Apple id, or the cloud model name. Empty when a custom
  /// endpoint has no model set.
  final String modelId;
  final OverviewModelState modelState;

  /// Download progress while [modelState] is [OverviewModelState.downloading].
  final int? downloadPercent;
  final OverviewMicState micState;

  /// The chosen device's name; `null` for the system default.
  final String? micName;

  /// Whether the engine runs on this device (not a cloud provider).
  bool get onDevice => switch (engine) {
    SpeechModelEngine.whisper ||
    SpeechModelEngine.parakeet ||
    SpeechModelEngine.system => true,
    SpeechModelEngine.openAI ||
    SpeechModelEngine.deepgram ||
    SpeechModelEngine.customEndpoint => false,
  };
}

/// The fixed model names of the cloud providers (see `openai_transcriber.dart`
/// and `deepgram_transcriber.dart`; internal-notes §4.3).
const kOverviewOpenAiModel = 'gpt-transcribe';
const kOverviewDeepgramModel = 'nova-3';

/// The engine the settings select, in the vocabulary of the speech-model list.
SpeechModelEngine overviewActiveEngine(AppSettings settings) =>
    switch (settings.sttProviderType) {
      SttProviderType.openAI => SpeechModelEngine.openAI,
      SttProviderType.deepgram => SpeechModelEngine.deepgram,
      SttProviderType.customEndpoint => SpeechModelEngine.customEndpoint,
      SttProviderType.onDevice => switch (settings.onDeviceEngine) {
        OnDeviceEngine.whisper => SpeechModelEngine.whisper,
        OnDeviceEngine.parakeet => SpeechModelEngine.parakeet,
        OnDeviceEngine.system => SpeechModelEngine.system,
      },
    };

/// Builds the card's speech rows.
///
/// [models] is the speech-model list of the dock and Settings
/// (`selectableSpeechModelsProvider`), so download states agree with them.
/// [whisperState]/[whisperModelId] are the Whisper engine's lifecycle and the
/// model it holds; [parakeetState] the Parakeet engine's. [micDevices] is the
/// device list of the microphone row (system default sentinel first), `null`
/// while it is read. [micListingUnavailable] means the platform could not list
/// devices (Linux without `pactl`), so an empty list says nothing.
OverviewSpeechSetup overviewSpeechSetup({
  required AppSettings settings,
  required List<SelectableSpeechModel> models,
  required SttServerState whisperState,
  required String whisperModelId,
  required SttServerState parakeetState,
  required List<String>? micDevices,
  required bool micListingUnavailable,
  required bool micDenied,
}) {
  final engine = overviewActiveEngine(settings);
  final modelId = switch (engine) {
    SpeechModelEngine.whisper => settings.effectiveModelId,
    SpeechModelEngine.parakeet ||
    SpeechModelEngine.system => settings.transcriptionModelId,
    SpeechModelEngine.openAI => kOverviewOpenAiModel,
    SpeechModelEngine.deepgram => kOverviewDeepgramModel,
    SpeechModelEngine.customEndpoint =>
      settings.cloudProvider.customEndpointSttModel.trim(),
  };

  final entry = models
      .where(
        (m) =>
            m.engine == engine &&
            (engine != SpeechModelEngine.whisper || m.modelId == modelId),
      )
      .firstOrNull;

  OverviewModelState modelState;
  int? percent;
  switch (entry?.state) {
    case SpeechModelNotDownloaded():
      modelState = OverviewModelState.notDownloaded;
    case SpeechModelDownloading(percent: final p):
      modelState = OverviewModelState.downloading;
      percent = p;
    case SpeechModelUnavailable():
      modelState = OverviewModelState.unavailable;
    case _:
      modelState = _loadState(
        engine: engine,
        whisperState: whisperState,
        whisperHoldsModel: whisperModelId == modelId,
        parakeetState: parakeetState,
      );
  }

  final (micState, micName) = _mic(
    selected: settings.microphone,
    devices: micDevices,
    listingUnavailable: micListingUnavailable,
    denied: micDenied,
  );

  return OverviewSpeechSetup(
    engine: engine,
    modelId: modelId,
    modelState: modelState,
    downloadPercent: percent,
    micState: micState,
    micName: micName,
  );
}

OverviewModelState _loadState({
  required SpeechModelEngine engine,
  required SttServerState whisperState,
  required bool whisperHoldsModel,
  required SttServerState parakeetState,
}) {
  OverviewModelState fromLifecycle(SttServerState s) => switch (s) {
    SttServerState.starting => OverviewModelState.loading,
    SttServerState.ready => OverviewModelState.ready,
    SttServerState.error => OverviewModelState.failed,
    SttServerState.stopped => OverviewModelState.loadsOnDictation,
  };

  return switch (engine) {
    // The engine may still hold the previous model after a switch: only the
    // selected one counts as loaded.
    SpeechModelEngine.whisper =>
      whisperState == SttServerState.starting || whisperHoldsModel
          ? fromLifecycle(whisperState)
          : OverviewModelState.loadsOnDictation,
    SpeechModelEngine.parakeet => fromLifecycle(parakeetState),
    // macOS loads its own model; an installed language asset is ready.
    SpeechModelEngine.system => OverviewModelState.ready,
    SpeechModelEngine.openAI ||
    SpeechModelEngine.deepgram ||
    SpeechModelEngine.customEndpoint => OverviewModelState.cloud,
  };
}

(OverviewMicState, String?) _mic({
  required String selected,
  required List<String>? devices,
  required bool listingUnavailable,
  required bool denied,
}) {
  final chosen = selected.isEmpty || selected == micDefaultLabel
      ? null
      : selected;
  if (denied) return (OverviewMicState.noAccess, chosen);
  // Still being listed, or the platform cannot list: say what is set.
  if (devices == null || listingUnavailable) {
    return (
      chosen == null ? OverviewMicState.systemDefault : OverviewMicState.device,
      chosen,
    );
  }
  final named = devices.where((d) => d.isNotEmpty && d != micDefaultLabel);
  if (named.isEmpty) return (OverviewMicState.noneFound, chosen);
  if (chosen == null) return (OverviewMicState.systemDefault, null);
  return named.contains(chosen)
      ? (OverviewMicState.device, chosen)
      : (OverviewMicState.disconnected, chosen);
}

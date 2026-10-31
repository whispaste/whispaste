/// The one source of the speech models a user can pick: the dock's speech
/// selector and the Settings model choice both read [selectableSpeechModelsProvider].
/// A future model library only has to feed this provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/model_download_service.dart';
import '../../services/stt/stt_bundle.dart';
import '../../services/stt_parakeet/parakeet_download_service.dart';
import '../l10n/generated/app_localizations.dart';
import 'custom_endpoint_rules.dart';
import 'settings_enums.dart';
import 'settings_provider.dart';

/// Prefix of a choice key that selects a downloaded Whisper model.
const kSttModelChoicePrefix = 'whisper:';

/// Prefix of a choice key for a Whisper model that is not on disk yet. Picking
/// it does not download: the dock opens Settings, where the download starts.
const kSttDownloadChoicePrefix = 'download:';

/// Where a selectable model runs.
enum SpeechModelGroup { local, cloud }

/// The engine behind a selectable model.
enum SpeechModelEngine { whisper, parakeet, openAI, deepgram, customEndpoint }

/// What the user can see of a selectable model right now.
sealed class SpeechModelState {
  const SpeechModelState();
}

/// Not on disk; picking it opens the Settings download.
final class SpeechModelNotDownloaded extends SpeechModelState {
  const SpeechModelNotDownloaded();
}

/// Being downloaded; [percent] is the download progress.
final class SpeechModelDownloading extends SpeechModelState {
  const SpeechModelDownloading(this.percent);
  final int percent;
}

/// On disk and being loaded into the engine right now.
final class SpeechModelLoading extends SpeechModelState {
  const SpeechModelLoading();
}

/// Usable, but not the one in use.
final class SpeechModelReady extends SpeechModelState {
  const SpeechModelReady();
}

/// The model the recordings use.
final class SpeechModelActive extends SpeechModelState {
  const SpeechModelActive();
}

/// One entry the user can pick for speech recognition.
class SelectableSpeechModel {
  const SelectableSpeechModel({
    required this.engine,
    required this.modelId,
    required this.displayName,
    required this.group,
    required this.state,
    this.sizeLabel = '',
  });

  final SpeechModelEngine engine;

  /// The Whisper model id; for Parakeet and the cloud providers their fixed
  /// key (`parakeet`, `openAI`, `deepgram`).
  final String modelId;

  /// The localized name of the entry, without any state suffix.
  final String Function(L10n l10n) displayName;
  final SpeechModelGroup group;
  final SpeechModelState state;

  /// The download size shown before the model is on disk; empty when unknown.
  final String sizeLabel;

  /// The model is on disk (or needs no download), so it can be picked.
  bool get isInstalled =>
      state is! SpeechModelNotDownloaded && state is! SpeechModelDownloading;

  /// The choice key of this entry, as the dock's choice list uses it.
  String get choiceValue => switch (engine) {
    SpeechModelEngine.whisper when isInstalled =>
      '$kSttModelChoicePrefix$modelId',
    SpeechModelEngine.whisper => '$kSttDownloadChoicePrefix$modelId',
    SpeechModelEngine.parakeet => OnDeviceEngine.parakeet.value,
    SpeechModelEngine.openAI => SttProviderType.openAI.name,
    SpeechModelEngine.deepgram => SttProviderType.deepgram.name,
    SpeechModelEngine.customEndpoint => SttProviderType.customEndpoint.name,
  };

  /// The dock-menu value that downloads this model (UIA-MDL-GATE b).
  String get downloadChoiceValue => '$kSttDownloadChoicePrefix$modelId';
}

/// Builds the selectable entries from the settings and the download state:
/// the Whisper models in [models] order, then Parakeet, then each cloud
/// provider that is usable (a saved key, or the one in use).
List<SelectableSpeechModel> selectableSpeechModels({
  required AppSettings settings,
  required ModelDownloadState downloads,
  required ParakeetDownloadState parakeet,
  required List<SttModelInfo> models,
  String? loadingModelId,
}) {
  final onDevice = settings.sttProviderType.isLocal;
  final whisperInUse =
      onDevice && settings.onDeviceEngine != OnDeviceEngine.parakeet;
  final parakeetInUse =
      onDevice && settings.onDeviceEngine == OnDeviceEngine.parakeet;
  final openAiInUse = settings.sttProviderType == SttProviderType.openAI;
  final deepgramInUse = settings.sttProviderType == SttProviderType.deepgram;
  final customInUse =
      settings.sttProviderType == SttProviderType.customEndpoint;
  final cloud = settings.cloudProvider;

  SpeechModelState inUse(bool active) =>
      active ? const SpeechModelActive() : const SpeechModelReady();

  return [
    for (final model in models)
      SelectableSpeechModel(
        engine: SpeechModelEngine.whisper,
        modelId: model.id,
        displayName: (_) => 'Whisper · ${model.label}',
        group: SpeechModelGroup.local,
        sizeLabel: model.sizeLabel,
        state: _whisperState(
          model: model,
          downloads: downloads,
          loadingModelId: loadingModelId,
          active: whisperInUse && settings.effectiveModelId == model.id,
        ),
      ),
    SelectableSpeechModel(
      engine: SpeechModelEngine.parakeet,
      modelId: OnDeviceEngine.parakeet.value,
      displayName: (l10n) => l10n.settingsSttEngineParakeet,
      group: SpeechModelGroup.local,
      sizeLabel: parakeetDownloadSizeLabel(
        gpuWanted: parakeetGpuWantedForSetting(
          settings.behavior.gpuAcceleration,
        ),
      ),
      state: _parakeetState(parakeet, active: parakeetInUse),
    ),
    if (cloud.openAiApiKey.trim().isNotEmpty || openAiInUse)
      SelectableSpeechModel(
        engine: SpeechModelEngine.openAI,
        modelId: SttProviderType.openAI.name,
        displayName: (_) => SttProviderType.openAI.value,
        group: SpeechModelGroup.cloud,
        state: inUse(openAiInUse),
      ),
    if (cloud.deepgramApiKey.trim().isNotEmpty || deepgramInUse)
      SelectableSpeechModel(
        engine: SpeechModelEngine.deepgram,
        modelId: SttProviderType.deepgram.name,
        displayName: (_) => SttProviderType.deepgram.value,
        group: SpeechModelGroup.cloud,
        state: inUse(deepgramInUse),
      ),
    if (customInUse ||
        customEndpointReady(
          url: cloud.customEndpointUrl,
          model: cloud.customEndpointSttModel,
        ))
      SelectableSpeechModel(
        engine: SpeechModelEngine.customEndpoint,
        modelId: SttProviderType.customEndpoint.name,
        displayName: (l10n) => l10n.settingsSttCustomEndpoint,
        group: SpeechModelGroup.cloud,
        state: inUse(customInUse),
      ),
  ];
}

SpeechModelState _whisperState({
  required SttModelInfo model,
  required ModelDownloadState downloads,
  required String? loadingModelId,
  required bool active,
}) {
  if (downloads.isDownloading && downloads.activeModelId == model.id) {
    return SpeechModelDownloading(downloads.progressPercent);
  }
  if (!downloads.downloadedModels.contains(model.id)) {
    return const SpeechModelNotDownloaded();
  }
  if (model.id == loadingModelId) return const SpeechModelLoading();
  return active ? const SpeechModelActive() : const SpeechModelReady();
}

SpeechModelState _parakeetState(
  ParakeetDownloadState parakeet, {
  required bool active,
}) {
  if (parakeet.installed || parakeet.phase == ParakeetDownloadPhase.done) {
    return active ? const SpeechModelActive() : const SpeechModelReady();
  }
  if (parakeet.phase == ParakeetDownloadPhase.downloading ||
      parakeet.phase == ParakeetDownloadPhase.verifying) {
    return SpeechModelDownloading(parakeet.progressPercent);
  }
  return const SpeechModelNotDownloaded();
}

/// The speech models the user can pick, in the order of
/// [selectableSpeechModels].
final selectableSpeechModelsProvider = Provider<List<SelectableSpeechModel>>((
  ref,
) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final downloads = ref.watch(modelDownloadProvider);
  final parakeet = ref.watch(parakeetDownloadProvider);
  final sttStatus = ref.watch(localSttBundleProvider);
  return selectableSpeechModels(
    settings: settings,
    downloads: downloads,
    parakeet: parakeet,
    models: sttModels,
    loadingModelId: sttStatus.serverState == SttServerState.starting
        ? sttStatus.modelId
        : null,
  );
});

/// The selected local speech model when it is neither on disk nor
/// downloading, else `null` (UIA-MDL-GATE b). One rule for Whisper and
/// Parakeet, read from [models] so it can never disagree with the dock's
/// speech selector. Cloud providers have no model to miss; an unknown
/// Whisper id is left to the recording preflight.
SelectableSpeechModel? missingSelectedSpeechModel(
  AppSettings settings,
  List<SelectableSpeechModel> models,
) {
  if (!settings.sttProviderType.isLocal) return null;
  final parakeet = settings.onDeviceEngine == OnDeviceEngine.parakeet;
  for (final model in models) {
    final selected = parakeet
        ? model.engine == SpeechModelEngine.parakeet
        : model.engine == SpeechModelEngine.whisper &&
              model.modelId == settings.effectiveModelId;
    if (selected) {
      return model.state is SpeechModelNotDownloaded ? model : null;
    }
  }
  return null;
}

/// [missingSelectedSpeechModel] for the live state. `null` before onboarding
/// is done (onboarding fetches the model itself) and before the initial disk
/// scan has landed.
final missingSelectedSpeechModelProvider = Provider<SelectableSpeechModel?>((
  ref,
) {
  final settings = ref.watch(settingsProvider).value;
  if (settings == null || !settings.onboardingCompleted) return null;
  if (!ref.watch(modelDownloadProvider).scanned) return null;
  return missingSelectedSpeechModel(
    settings,
    ref.watch(selectableSpeechModelsProvider),
  );
});

/// Starts the download of [model]: the Whisper file or the Parakeet bundle.
/// Cloud entries have nothing to download.
Future<void> downloadSpeechModel({
  required SelectableSpeechModel model,
  required ModelDownloadNotifier whisper,
  required ParakeetDownloadNotifier parakeet,
}) => switch (model.engine) {
  SpeechModelEngine.whisper => whisper.downloadModel(model.modelId),
  SpeechModelEngine.parakeet => parakeet.downloadBundle(),
  SpeechModelEngine.openAI ||
  SpeechModelEngine.deepgram ||
  SpeechModelEngine.customEndpoint => Future.value(),
};

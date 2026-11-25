/// The model library (Modellbibliothek, #1514): every speech and Smart Mode
/// model the app knows, with what a user needs to choose one (size,
/// languages, speed, accuracy, local or cloud, status, recommendation).
///
/// No second inventory:
/// - the speech entries come from [selectableSpeechModelsProvider], the one
///   source the dock, the tray and the speech-recognition settings read too;
/// - speed, accuracy, languages and size of the local models come from the
///   bundled catalog (#1513, [bundledModelCatalog]);
/// - the Smart Mode entries from the Smart Mode download state and settings;
/// - the user's own models from `user_models.json` ([userModelsProvider],
///   #1789), always marked "not checked".
///
/// The page in `lib/features/settings/sections/model_library_section.dart`
/// only renders these entries and calls the existing download, cancel and
/// delete paths.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/download_error_kind.dart';
import '../../services/engine_recommendation.dart';
import '../../services/model_download_service.dart';
import '../../services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLocalEngineAvailableProvider;
import '../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../services/speech_recommendation.dart';
import '../../services/stt_parakeet/parakeet_download_service.dart';
import '../../services/user_models/user_model.dart';
import '../../services/user_models/user_model_use.dart'
    show ownSmartModelIdIn, ownSpeechModelIdIn, settingsUsingOwnModel;
import '../../services/user_models/user_models_provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/bundled_model_catalog.dart';
import '../models/model_catalog.dart';
import '../text/byte_size.dart';
import 'custom_endpoint_rules.dart';
import 'selectable_speech_models.dart';
import 'settings_enums.dart';
import 'settings_provider.dart';
import 'stt_choice.dart' show applySttChoice;

/// The two sections of the library.
enum ModelLibraryKind { speech, smartMode }

/// Where a model runs.
enum ModelLocation { local, cloud }

/// What the user sees of a model right now.
enum ModelLibraryStatus {
  /// Not on disk; can be installed.
  notInstalled,

  /// Being downloaded; see [ModelLibraryEntry.percent].
  downloading,

  /// Files are in place, the app checks that the model runs (own models).
  checking,

  /// On disk (or usable without download), not in use.
  installed,

  /// On disk and being loaded into the engine.
  loading,

  /// In use.
  active,

  /// Cannot be used here (the language set in Settings, or a build without
  /// the local Smart Mode engine).
  unavailable,

  /// An own model that failed its check or its download; see
  /// [ModelLibraryEntry.failure].
  failed,
}

/// Which languages a model writes.
enum ModelLanguages {
  /// A fixed number, see [ModelLibraryEntry.languageCount].
  counted,

  /// Many languages without a fixed list (the Smart Mode model).
  many,

  /// The languages the operating system offers (Apple speech).
  system,

  /// What the cloud provider supports.
  provider,

  /// Not known (an own model, not checked by us).
  unknown,
}

/// One model in the library.
class ModelLibraryEntry {
  const ModelLibraryEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.location,
    required this.status,
    required this.languages,
    this.speed,
    this.accuracy,
    this.languageCount = 0,
    this.sizeBytes = 0,
    this.percent = 0,
    this.verified = true,
    this.recommended = false,
    this.removable = false,
    this.failure,
    this.missingLanguages,
    this.speech,
    this.smartProvider,
    this.userModel,
  });

  /// Stable id, also the suffix of the entry's testIDs
  /// (`model-library-<id>-…`).
  final String id;
  final ModelLibraryKind kind;
  final String Function(L10n l10n) name;
  final ModelLocation location;
  final ModelLibraryStatus status;

  /// How quickly the text is there, relative to the other models of the
  /// section; null when not known (cloud custom endpoint, own models).
  final ModelLevel? speed;

  /// How few mistakes the text has; null when not known.
  final ModelLevel? accuracy;
  final ModelLanguages languages;

  /// Number of languages when [languages] is [ModelLanguages.counted].
  final int languageCount;

  /// Download size, also the space freed by removing it; 0 for cloud
  /// entries and models without a file of their own.
  final int sizeBytes;

  /// Download progress while [status] is [ModelLibraryStatus.downloading].
  final int percent;

  /// Checked and recommended by us; `false` for own models (endpoint, URL,
  /// file), which the page shows apart as "not checked".
  final bool verified;

  /// The recommendation for this device (speech) or the fixed recommendation
  /// (Gemma for Smart Mode).
  final bool recommended;

  /// The model has files of its own on this device that can be deleted.
  final bool removable;

  /// Why an own model is [ModelLibraryStatus.failed].
  final UserModelFailure? failure;

  /// The user's dictation languages this model does not write (#1953):
  /// empty when it writes all of them, `null` when the catalog states no
  /// language list for it (Apple speech, cloud, own models), so the library
  /// claims nothing. See [missingDictationLanguages].
  final List<String>? missingLanguages;

  /// The catalog says this model writes every dictation language.
  bool get fitsLanguages => missingLanguages?.isEmpty ?? false;

  /// The catalog says this model misses at least one dictation language.
  bool get missesLanguages => missingLanguages?.isNotEmpty ?? false;

  /// The speech entry behind this one, for its actions.
  final SelectableSpeechModel? speech;

  /// The Smart Mode service this entry selects.
  final SmartModeProviderType? smartProvider;

  /// The own model behind this one.
  final UserModel? userModel;

  /// [sizeBytes] for the UI; empty when there is none.
  String get sizeLabel => sizeBytes > 0 ? formatByteSize(sizeBytes) : '';

  bool get canInstall =>
      location == ModelLocation.local &&
      status == ModelLibraryStatus.notInstalled;

  bool get canCancel =>
      status == ModelLibraryStatus.downloading &&
      (speech?.engine == SpeechModelEngine.whisper ||
          speech?.engine == SpeechModelEngine.parakeet ||
          smartProvider == SmartModeProviderType.local ||
          userModel != null);

  /// An installed catalog model, or an own model that passed its check
  /// (its status is [ModelLibraryStatus.installed] only then).
  bool get canActivate => status == ModelLibraryStatus.installed;

  bool get canRetry =>
      status == ModelLibraryStatus.failed &&
      userModel?.sourceKind != UserModelSourceKind.file;

  bool get canRemove =>
      removable &&
      (status == ModelLibraryStatus.installed ||
          status == ModelLibraryStatus.active ||
          status == ModelLibraryStatus.failed);
}

/// The catalog entry behind a speech model, or null for the engines without
/// one (Apple speech, cloud).
CatalogModel? catalogModelForSpeech(SelectableSpeechModel model) =>
    switch (model.engine) {
      SpeechModelEngine.whisper => bundledModelCatalog.tryById(model.modelId),
      SpeechModelEngine.parakeet => bundledModelCatalog.tryById(
        CatalogIds.parakeet,
      ),
      _ => null,
    };

({ModelLanguages kind, int count}) _catalogLanguages(CatalogModel model) =>
    model.languages.contains(kAnyLanguage)
    ? (kind: ModelLanguages.many, count: 0)
    : (kind: ModelLanguages.counted, count: model.languages.length);

/// Which of [dictationLanguages] (ISO 639-1 codes, see
/// `dictationLanguagesFor`) [model] does not write, from its catalog
/// language list. `null` when there is nothing to say: no catalog entry, no
/// fixed list ([kAnyLanguage]) or no dictation language. The library then
/// shows no fit either way rather than guess (#1953).
List<String>? missingDictationLanguages(
  CatalogModel? model,
  List<String> dictationLanguages,
) {
  if (model == null || dictationLanguages.isEmpty) return null;
  if (model.languages.contains(kAnyLanguage)) return null;
  final written = model.languages.toSet();
  return [
    for (final code in dictationLanguages)
      if (!written.contains(code)) code,
  ];
}

/// Speed, accuracy and languages of a speech entry: from the catalog for the
/// local models, fixed guide values for the engines the catalog does not
/// hold.
({ModelLevel? speed, ModelLevel? accuracy, ModelLanguages languages, int count})
speechFacts(SelectableSpeechModel model) {
  final catalog = catalogModelForSpeech(model);
  if (catalog != null) {
    final langs = _catalogLanguages(catalog);
    return (
      speed: catalog.speed,
      accuracy: catalog.accuracy,
      languages: langs.kind,
      count: langs.count,
    );
  }
  return switch (model.engine) {
    SpeechModelEngine.system => (
      speed: ModelLevel.high,
      accuracy: ModelLevel.medium,
      languages: ModelLanguages.system,
      count: 0,
    ),
    SpeechModelEngine.openAI => (
      speed: ModelLevel.medium,
      accuracy: ModelLevel.high,
      languages: ModelLanguages.provider,
      count: 0,
    ),
    SpeechModelEngine.deepgram => (
      speed: ModelLevel.high,
      accuracy: ModelLevel.high,
      languages: ModelLanguages.provider,
      count: 0,
    ),
    _ => (
      speed: null,
      accuracy: null,
      languages: ModelLanguages.unknown,
      count: 0,
    ),
  };
}

ModelLibraryStatus _speechStatus(SpeechModelState state) => switch (state) {
  SpeechModelNotDownloaded() => ModelLibraryStatus.notInstalled,
  SpeechModelDownloading() => ModelLibraryStatus.downloading,
  SpeechModelLoading() => ModelLibraryStatus.loading,
  SpeechModelUnavailable() => ModelLibraryStatus.unavailable,
  SpeechModelReady() => ModelLibraryStatus.installed,
  SpeechModelActive() => ModelLibraryStatus.active,
};

/// The library id of a speech entry: the Whisper model id, else the engine.
String speechLibraryId(SelectableSpeechModel model) =>
    model.engine == SpeechModelEngine.whisper
    ? model.modelId
    : model.engine.name;

/// The library id of the speech model recommended for this device, or null
/// when the recommendation names no model (no measurement, no GPU figure).
String? recommendedSpeechLibraryId(EngineRecommendation? recommendation) {
  if (recommendation == null) return null;
  if (recommendation.engine == OnDeviceEngine.parakeet) {
    return SpeechModelEngine.parakeet.name;
  }
  if (recommendation.engine == OnDeviceEngine.system) {
    return SpeechModelEngine.system.name;
  }
  final tier = recommendation.tier;
  return tier == null ? null : bestModelForTier(tier).id;
}

/// The speech section, built from [models] (the entries of
/// [selectableSpeechModelsProvider], in their order) and the user's own
/// speech models. The entry for [recommendedId] is marked and comes first,
/// so the device's choice is visible at a glance. Each checked entry knows
/// which of [dictationLanguages] it misses; the ones that miss a language
/// move to the end of the checked list (#1953).
List<ModelLibraryEntry> speechLibraryEntries(
  List<SelectableSpeechModel> models, {
  String? recommendedId,
  List<String> dictationLanguages = const [],
  UserModelsState own = const UserModelsState(),
  String? activeOwnId,
}) {
  final checked = [
    for (final model in models)
      () {
        final facts = speechFacts(model);
        final id = speechLibraryId(model);
        final state = model.state;
        final catalog = catalogModelForSpeech(model);
        return ModelLibraryEntry(
          id: id,
          kind: ModelLibraryKind.speech,
          name: model.displayName,
          location: model.group == SpeechModelGroup.local
              ? ModelLocation.local
              : ModelLocation.cloud,
          status: _speechStatus(state),
          percent: state is SpeechModelDownloading ? state.percent : 0,
          speed: facts.speed,
          accuracy: facts.accuracy,
          languages: facts.languages,
          languageCount: facts.count,
          // Parakeet's size depends on the GPU variant; the selectable entry
          // already names the right one.
          sizeBytes: model.engine == SpeechModelEngine.parakeet
              ? _parakeetBytes(model)
              : catalog?.sizeBytes ?? 0,
          verified: model.engine != SpeechModelEngine.customEndpoint,
          recommended: id == recommendedId,
          missingLanguages: missingDictationLanguages(
            catalog,
            dictationLanguages,
          ),
          // Apple's engine keeps its language asset in the system.
          removable:
              model.engine == SpeechModelEngine.whisper ||
              model.engine == SpeechModelEngine.parakeet,
          speech: model,
        );
      }(),
  ];
  return [
    ..._recommendedFirst([
      ...checked.where((e) => !e.missesLanguages),
      ...checked.where((e) => e.missesLanguages),
    ]),
    ...ownLibraryEntries(own, UserModelPurpose.speech, activeId: activeOwnId),
  ];
}

int _parakeetBytes(SelectableSpeechModel model) {
  for (final id in [
    CatalogIds.parakeet,
    CatalogIds.parakeetGgufQ8,
    CatalogIds.parakeetGgufF16,
  ]) {
    final m = bundledModelCatalog.tryById(id);
    if (m != null && m.sizeLabel == model.sizeLabel) return m.sizeBytes;
  }
  return bundledModelCatalog.tryById(CatalogIds.parakeet)?.sizeBytes ?? 0;
}

/// The user's own models of [purpose], as library entries. [activeId] is
/// the own model the settings use for [purpose], if any.
List<ModelLibraryEntry> ownLibraryEntries(
  UserModelsState own,
  UserModelPurpose purpose, {
  String? activeId,
}) => [
  for (final model in own.forPurpose(purpose))
    ModelLibraryEntry(
      id: model.id,
      kind: purpose == UserModelPurpose.speech
          ? ModelLibraryKind.speech
          : ModelLibraryKind.smartMode,
      name: (_) => model.name,
      location: ModelLocation.local,
      status: own.installingId == model.id
          ? (own.progress?.checking ?? false)
                ? ModelLibraryStatus.checking
                : ModelLibraryStatus.downloading
          : switch (model.status) {
              UserModelStatus.checking => ModelLibraryStatus.checking,
              UserModelStatus.ready =>
                model.id == activeId
                    ? ModelLibraryStatus.active
                    : ModelLibraryStatus.installed,
              UserModelStatus.failed => ModelLibraryStatus.failed,
            },
      percent: own.installingId == model.id ? own.percent : 0,
      languages: ModelLanguages.unknown,
      sizeBytes: model.totalBytes,
      verified: false,
      removable: own.installingId != model.id,
      failure: model.failure,
      userModel: model,
    ),
];

/// The Smart Mode section: the local Gemma model (always the recommendation),
/// OpenAI when a key is saved or it is in use, the own endpoint when it is
/// set up or in use, and the user's own text models.
List<ModelLibraryEntry> smartModeLibraryEntries({
  required AppSettings settings,
  required SmartModeDownloadState download,
  required bool localEngineAvailable,
  UserModelsState own = const UserModelsState(),
}) {
  final provider = SmartModeProviderType.fromValue(settings.smartMode.provider);
  final cloud = settings.cloudProvider;
  // A ready own model in use replaces Gemma as the local model (#1789).
  final ownActive = own.models.any(
    (m) => m.id == ownSmartModelIdIn(settings) && m.isReady,
  );
  ModelLibraryStatus inUse(SmartModeProviderType p) =>
      provider == p && !(p.isLocal && ownActive)
      ? ModelLibraryStatus.active
      : ModelLibraryStatus.installed;

  final ModelLibraryStatus gemmaStatus;
  if (!localEngineAvailable) {
    gemmaStatus = ModelLibraryStatus.unavailable;
  } else if (download.isBusy) {
    gemmaStatus = ModelLibraryStatus.downloading;
  } else if (download.modelDownloaded) {
    gemmaStatus = inUse(SmartModeProviderType.local);
  } else {
    gemmaStatus = ModelLibraryStatus.notInstalled;
  }
  final gemma = smartModeModel;
  final gemmaLangs = _catalogLanguages(gemma);

  final openAiInUse = provider == SmartModeProviderType.openAI;
  final customInUse = provider == SmartModeProviderType.custom;
  return [
    ModelLibraryEntry(
      id: 'gemma',
      kind: ModelLibraryKind.smartMode,
      name: (_) => gemma.label,
      location: ModelLocation.local,
      status: gemmaStatus,
      percent: download.isBusy ? download.progressPercent : 0,
      speed: gemma.speed,
      accuracy: gemma.accuracy,
      languages: gemmaLangs.kind,
      languageCount: gemmaLangs.count,
      sizeBytes: gemma.sizeBytes,
      recommended: true,
      removable: true,
      smartProvider: SmartModeProviderType.local,
    ),
    if (cloud.openAiApiKey.trim().isNotEmpty || openAiInUse)
      ModelLibraryEntry(
        id: 'smart-openai',
        kind: ModelLibraryKind.smartMode,
        name: (_) => 'OpenAI',
        location: ModelLocation.cloud,
        status: inUse(SmartModeProviderType.openAI),
        speed: ModelLevel.medium,
        accuracy: ModelLevel.high,
        languages: ModelLanguages.provider,
        smartProvider: SmartModeProviderType.openAI,
      ),
    if (customInUse ||
        customEndpointReady(
          url: cloud.customEndpointUrl,
          model: cloud.customEndpointSmartModel,
        ))
      ModelLibraryEntry(
        id: 'smart-custom',
        kind: ModelLibraryKind.smartMode,
        name: (l10n) => l10n.settingsSttCustomEndpoint,
        location: ModelLocation.cloud,
        status: inUse(SmartModeProviderType.custom),
        languages: ModelLanguages.unknown,
        verified: false,
        smartProvider: SmartModeProviderType.custom,
      ),
    ...ownLibraryEntries(
      own,
      UserModelPurpose.smartMode,
      activeId: ownSmartModelIdIn(settings),
    ),
  ];
}

List<ModelLibraryEntry> _recommendedFirst(List<ModelLibraryEntry> entries) => [
  ...entries.where((e) => e.recommended),
  ...entries.where((e) => !e.recommended),
];

/// Settings with [entry] as the model in use: the speech choice the dock and
/// the tray apply, or the Smart Mode service. Unchanged for entries that
/// cannot be activated. An own model uses [settingsUsingOwnModel]; the page
/// goes through [UserModelUse.activate], which also remembers the fallback.
AppSettings activateLibraryEntry(
  AppSettings settings,
  ModelLibraryEntry entry,
) {
  if (!entry.canActivate && entry.status != ModelLibraryStatus.active) {
    return settings;
  }
  final own = entry.userModel;
  if (own != null) {
    return own.isReady ? settingsUsingOwnModel(settings, own) : settings;
  }
  final speech = entry.speech;
  if (speech != null) {
    if (!speech.isInstalled) return settings;
    return applySttChoice(settings, speech.choiceValue);
  }
  final smart = entry.smartProvider;
  if (smart == null) return settings;
  // Choosing the bundled local model sets an own one aside.
  return settings.copyWithSections(
    smartMode: settings.smartMode.copyWith(
      provider: smart.value,
      localModel: '',
    ),
  );
}

/// Whether the last download attempt failed for lack of a connection. The
/// library then says so: installed models keep working, downloads wait.
/// Read from the download states, so the page costs no network probe.
bool modelLibraryOffline({
  required ModelDownloadState whisper,
  required ParakeetDownloadState parakeet,
  required SmartModeDownloadState smartMode,
}) =>
    (whisper.isError && whisper.errorKind == DownloadErrorKind.offline) ||
    (parakeet.phase == ParakeetDownloadPhase.error &&
        parakeet.errorKind == DownloadErrorKind.offline) ||
    (smartMode.isError && smartMode.errorKind == DownloadErrorKind.offline);

/// The speech section of the library.
final speechLibraryEntriesProvider = Provider<List<ModelLibraryEntry>>((ref) {
  final recommendation = ref.watch(speechRecommendationProvider).value;
  return speechLibraryEntries(
    ref.watch(selectableSpeechModelsProvider),
    recommendedId: recommendedSpeechLibraryId(recommendation?.recommendation),
    dictationLanguages: ref.watch(dictationLanguagesProvider),
    own: ref.watch(userModelsProvider),
    activeOwnId: ownSpeechModelIdIn(
      ref.watch(settingsProvider).value ?? AppSettings.defaults,
    ),
  );
});

/// The Smart Mode section of the library.
final smartModeLibraryEntriesProvider = Provider<List<ModelLibraryEntry>>((
  ref,
) {
  return smartModeLibraryEntries(
    settings: ref.watch(settingsProvider).value ?? AppSettings.defaults,
    download: ref.watch(smartModeDownloadProvider),
    localEngineAvailable: ref.watch(smartModeLocalEngineAvailableProvider),
    own: ref.watch(userModelsProvider),
  );
});

/// [modelLibraryOffline] for the live download states.
final modelLibraryOfflineProvider = Provider<bool>(
  (ref) => modelLibraryOffline(
    whisper: ref.watch(modelDownloadProvider),
    parakeet: ref.watch(parakeetDownloadProvider),
    smartMode: ref.watch(smartModeDownloadProvider),
  ),
);

/// Using a model the user added themselves (#1789, stage 3): putting it in
/// use from the "Modelle" page, taking it out of use when it fails, and the
/// notice that says so.
///
/// Where the choice lives in the settings:
/// - own whisper.cpp model: `sttEngine: whisper`, `sttModel: user-…`
///   (`sttModelPath` resolves the id to its file);
/// - own sherpa-onnx model: `sttEngine: user_model`, `sttModel: user-…`;
/// - own GGUF Smart Mode model: `smartMode.provider: local`,
///   `smartMode.localModel: user-…`.
///
/// A failing own model is marked failed in `user_models.json` and the
/// settings return to a checked model ([pickSpeechFallback], Gemma for Smart
/// Mode). The recording in flight is handed to that model, so the dictation
/// is not lost (`user_model_guards.dart`). Logs name the model id only.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../model_hardware_telemetry.dart'
    show fallbackChoiceKey, modelLifecycleTelemetryProvider;
import '../model_telemetry_identity.dart' show ownModelFactsFrom, ownModelKey;
import '../path_service.dart' show isUserModelId, sttModelPath;
import '../smart_mode/smart_mode_model_download_service.dart'
    show smartModeDownloadProvider;
import '../stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelFilesExistSync;
import '../system_speech/system_speech_status.dart' show systemSpeechProvider;
import 'user_model.dart';
import 'user_model_fallback.dart';
import 'user_model_guards.dart';
import 'user_model_store.dart';
import 'user_models_provider.dart';

final _log = AppLogger('UserModelUse');

// ---------------------------------------------------------------------------
// Pure settings rules
// ---------------------------------------------------------------------------

/// The own speech model [settings] use, or null for a catalog or cloud one.
String? ownSpeechModelIdIn(AppSettings settings) {
  if (!settings.sttProviderType.isLocal) return null;
  final id = settings.effectiveModelId;
  if (!isUserModelId(id)) return null;
  return switch (settings.onDeviceEngine) {
    OnDeviceEngine.whisper || OnDeviceEngine.userModel => id,
    OnDeviceEngine.parakeet || OnDeviceEngine.system => null,
  };
}

/// The own Smart Mode model [settings] use, or null for Gemma or a cloud
/// service.
String? ownSmartModelIdIn(AppSettings settings) {
  final provider = SmartModeProviderType.fromValue(settings.smartMode.provider);
  if (!provider.isLocal) return null;
  final id = settings.smartMode.localModel;
  return isUserModelId(id) ? id : null;
}

/// [settings] with own model [model] in use.
AppSettings settingsUsingOwnModel(AppSettings settings, UserModel model) =>
    switch (model.runtime) {
      UserModelRuntime.whispercpp => settings.copyWith(
        sttProvider: SttProviderType.onDevice.value,
        sttEngine: OnDeviceEngine.whisper.value,
        sttModel: model.id,
      ),
      UserModelRuntime.sherpaOnnx => settings.copyWith(
        sttProvider: SttProviderType.onDevice.value,
        sttEngine: OnDeviceEngine.userModel.value,
        sttModel: model.id,
      ),
      UserModelRuntime.llamaCpp => settings.copyWithSections(
        smartMode: settings.smartMode.copyWith(
          provider: SmartModeProviderType.local.value,
          localModel: model.id,
        ),
      ),
    };

/// [settings] with the speech choice [choice].
AppSettings settingsWithSpeechChoice(
  AppSettings settings,
  SpeechFallbackChoice choice,
) => settings.copyWith(
  sttProvider: SttProviderType.onDevice.value,
  sttEngine: choice.engine,
  sttModel: choice.modelId,
);

/// [settings] with the bundled Smart Mode model instead of an own one.
AppSettings settingsWithoutOwnSmartModel(AppSettings settings) => settings
    .copyWithSections(smartMode: settings.smartMode.copyWith(localModel: ''));

/// The model file the local Smart Mode engine loads for [localModel]: the
/// GGUF file of a ready own model in [store], or null for the bundled model.
/// An id whose model is gone or failed falls back to the bundled model too.
String? ownSmartModelPathFor(String localModel, UserModelStore store) {
  if (!isUserModelId(localModel)) return null;
  final UserModel? model;
  try {
    model = store.readSync().byId(localModel);
  } on Object {
    return null;
  }
  if (model == null || !model.isReady) return null;
  final file = model.fileFor(UserModelFileRole.model);
  if (file == null) return null;
  return p.join(store.modelDir(model.id), file.name);
}

/// Whether the local Smart Mode engine has a text model to run: the ready
/// own model the settings name, or else the bundled model on disk. Every
/// "is the local model there" gate reads this, so an own model counts the
/// same as the bundled one.
final smartModeLocalModelReadyProvider = Provider<bool>((ref) {
  final localModel = ref.watch(
    settingsProvider.select((s) => s.value?.smartMode.localModel ?? ''),
  );
  if (ownSmartModelPathFor(localModel, ref.read(userModelStoreProvider)) !=
      null) {
    return true;
  }
  return ref.watch(smartModeDownloadProvider.select((s) => s.modelDownloaded));
});

// ---------------------------------------------------------------------------
// Notice
// ---------------------------------------------------------------------------

/// An own model failed and was taken out of use.
class UserModelFallbackNotice {
  const UserModelFallbackNotice({
    required this.modelName,
    required this.purpose,
    required this.replaced,
  });

  final String modelName;
  final UserModelPurpose purpose;

  /// A checked model took over; false when none is installed, so the
  /// recording waits for a retry.
  final bool replaced;
}

/// The fallback notice to show now, or null.
class UserModelFallbackNoticeNotifier
    extends Notifier<UserModelFallbackNotice?> {
  @override
  UserModelFallbackNotice? build() => null;

  void show(UserModelFallbackNotice notice) => state = notice;

  void clear() => state = null;
}

final userModelFallbackNoticeProvider =
    NotifierProvider<UserModelFallbackNoticeNotifier, UserModelFallbackNotice?>(
      UserModelFallbackNoticeNotifier.new,
    );

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Which checked speech models are on this device; replaced in tests.
typedef InstalledSpeechProbe =
    ({Set<String> whisper, bool parakeet, bool system}) Function(Ref ref);

({Set<String> whisper, bool parakeet, bool system}) _probeInstalled(Ref ref) {
  bool onDisk(String id) {
    final path = sttModelPath(id);
    return path != null && File(path).existsSync();
  }

  final system = ref.read(systemSpeechProvider);
  return (
    whisper: {
      for (final id in kWhisperFallbackOrder)
        if (onDisk(id)) id,
    },
    parakeet: parakeetModelFilesExistSync(),
    system: system.osSupported && system.installed,
  );
}

final installedSpeechProbeProvider = Provider<InstalledSpeechProbe>(
  (_) => _probeInstalled,
);

/// Puts own models in and out of use. Reads and writes `user_models.json`
/// through [userModelStoreProvider] and the settings through
/// [settingsProvider].
class UserModelUse implements UserModelGuardHost {
  UserModelUse(this.ref);

  final Ref ref;

  UserModelStore get _store => ref.read(userModelStoreProvider);

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  /// Makes ready model [model] the one in use. Before a speech model takes
  /// over, the catalog choice in use is remembered as its fallback.
  Future<void> activate(UserModel model) async {
    if (!model.isReady) return;
    if (model.purpose == UserModelPurpose.speech) {
      final current = currentCatalogSpeechChoice(
        engine: _settings.sttProviderType.isLocal
            ? _settings.stt.engine
            : OnDeviceEngine.whisper.value,
        whisperModelId: _settings.effectiveModelId,
      );
      if (current != null) {
        try {
          _store.writeSync(_store.readSync().copyWith(speechFallback: current));
        } on Object catch (e) {
          _log.warning('Could not remember the fallback: ${e.runtimeType}');
        }
      }
    }
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => settingsUsingOwnModel(s, model));
    _log.info('Own model ${model.id} in use');
  }

  /// Own speech model [id] failed in use (or crashed): marks it failed with
  /// [failure] and returns the settings to a checked model. Returns whether
  /// one took over; without one the selection stays and the model is
  /// refused until it is retried or removed.
  @override
  Future<bool> fallBackFromSpeech(
    String id, {
    UserModelFailure failure = UserModelFailure.failedInUse,
    bool notify = true,
  }) async {
    final model = _markFailed(id, failure);
    final installed = ref.read(installedSpeechProbeProvider)(ref);
    final choice = pickSpeechFallback(
      remembered: _readSafely().speechFallback,
      installedWhisper: installed.whisper,
      parakeetInstalled: installed.parakeet,
      systemReady: installed.system,
    );
    final inUse = ownSpeechModelIdIn(_settings) == id;
    if (choice != null && inUse) {
      await ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => settingsWithSpeechChoice(s, choice));
    }
    if (inUse && model != null) {
      _reportFallback(model, fallbackChoiceKey(choice), failure);
    }
    _log.warning(
      'Own speech model $id failed (${failure.value}); '
      '${choice == null ? 'no checked model installed' : 'back to ${choice.engine}'}',
    );
    if (notify && model != null) {
      ref
          .read(userModelFallbackNoticeProvider.notifier)
          .show(
            UserModelFallbackNotice(
              modelName: model.name,
              purpose: UserModelPurpose.speech,
              replaced: choice != null,
            ),
          );
    }
    return choice != null;
  }

  /// Own Smart Mode model [id] failed in use: marks it failed and returns
  /// Smart Mode to the bundled model. Returns whether that one is installed.
  @override
  Future<bool> fallBackFromSmartMode(
    String id, {
    UserModelFailure failure = UserModelFailure.failedInUse,
    bool notify = true,
  }) async {
    final model = _markFailed(id, failure);
    final inUse = ownSmartModelIdIn(_settings) == id;
    if (inUse) {
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(settingsWithoutOwnSmartModel);
    }
    final bundled = ref.read(smartModeDownloadProvider).modelDownloaded;
    if (inUse && model != null) {
      _reportFallback(model, bundled ? 'gemma' : 'none', failure);
    }
    _log.warning(
      'Own Smart Mode model $id failed (${failure.value}); '
      'bundled model ${bundled ? 'takes over' : 'not installed'}',
    );
    if (notify && model != null) {
      ref
          .read(userModelFallbackNoticeProvider.notifier)
          .show(
            UserModelFallbackNotice(
              modelName: model.name,
              purpose: UserModelPurpose.smartMode,
              replaced: bundled,
            ),
          );
    }
    return bundled;
  }

  /// Own model [id] is being removed: when it is in use, the settings
  /// return to a checked model first. Nothing is marked failed.
  Future<void> beforeRemove(String id) async {
    if (ownSmartModelIdIn(_settings) == id) {
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(settingsWithoutOwnSmartModel);
    }
    if (ownSpeechModelIdIn(_settings) != id) return;
    final installed = ref.read(installedSpeechProbeProvider)(ref);
    final choice = pickSpeechFallback(
      remembered: _readSafely().speechFallback,
      installedWhisper: installed.whisper,
      parakeetInstalled: installed.parakeet,
      systemReady: installed.system,
    );
    // With nothing checked installed, the default Whisper model is selected,
    // so the usual "download a model" path takes over.
    final target =
        choice ??
        SpeechFallbackChoice(
          engine: OnDeviceEngine.whisper.value,
          modelId: kWhisperFallbackOrder.last,
        );
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => settingsWithSpeechChoice(s, target));
  }

  /// At start: models a previous run died in or never finished checking are
  /// marked failed ([UserModelInstaller.recoverAtStart]); one of them in use
  /// is replaced by a checked model. An own model in use that is no longer
  /// ready (failed earlier, or removed by hand) is replaced as well.
  Future<void> recoverAtStart() async {
    List<String> marked;
    try {
      marked = ref.read(userModelInstallerProvider).recoverAtStart();
    } on Object catch (e) {
      _log.warning('Recovering own models failed: ${e.runtimeType}');
      marked = const [];
    }
    final data = _readSafely();
    final speechId = ownSpeechModelIdIn(_settings);
    if (speechId != null && !(data.byId(speechId)?.isReady ?? false)) {
      await fallBackFromSpeech(
        speechId,
        failure: marked.contains(speechId)
            ? UserModelFailure.crashed
            : UserModelFailure.failedInUse,
        notify: marked.contains(speechId),
      );
    }
    final smartId = ownSmartModelIdIn(_settings);
    if (smartId != null && !(data.byId(smartId)?.isReady ?? false)) {
      await fallBackFromSmartMode(
        smartId,
        failure: marked.contains(smartId)
            ? UserModelFailure.crashed
            : UserModelFailure.failedInUse,
        notify: marked.contains(smartId),
      );
    }
    _refreshList();
  }

  @override
  bool isReady(String id) => _readSafely().byId(id)?.isReady ?? false;

  /// Notes that native code is about to run own model [id] in this process,
  /// so a crash there takes it out of use at the next start.
  @override
  void markInFlight(String id) => _store.markInFlight(id);

  @override
  void clearInFlight() => _store.clearInFlight();

  UserModel? _markFailed(String id, UserModelFailure failure) {
    try {
      final data = _store.readSync();
      final model = data.byId(id);
      if (model == null) return null;
      if (model.status != UserModelStatus.failed || model.failure != failure) {
        _store.writeSync(
          data.upsert(
            model.copyWith(status: UserModelStatus.failed, failure: failure),
          ),
        );
      }
      _refreshList();
      return model;
    } on Object catch (e) {
      _log.warning('Could not mark $id failed: ${e.runtimeType}');
      return null;
    }
  }

  /// `model/fallback` `<own model>><target>|user_model|<failure>` (#1791).
  /// Telemetry never breaks a fallback.
  void _reportFallback(
    UserModel model,
    String toKey,
    UserModelFailure failure,
  ) {
    try {
      ref
          .read(modelLifecycleTelemetryProvider)
          .fallback(
            fromKey: ownModelKey(ownModelFactsFrom(model)),
            toKey: toKey,
            reason: 'user_model',
            detail: failure.value,
          );
    } on Object catch (e) {
      _log.debug('model telemetry skipped: ${e.runtimeType}');
    }
  }

  UserModelsData _readSafely() {
    try {
      return _store.readSync();
    } on Object {
      return const UserModelsData();
    }
  }

  void _refreshList() {
    if (ref.exists(userModelsProvider)) {
      ref.read(userModelsProvider.notifier).reload();
    }
  }
}

final userModelUseProvider = Provider<UserModelUse>(UserModelUse.new);

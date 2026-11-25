// loam-ignore: circular-dependencies – model telemetry reads the engine and user-model state it reports on, and those services send through it; breaking the cycle needs an event seam, too big right before a release
/// Telemetry hooks for the speech model and its use (T1, Matomo).
///
/// Every send goes through [onboardingTelemetryBufferProvider]: during a first
/// run it is held until the privacy choice on the closing page, like every
/// onboarding event; otherwise the buffer passes it straight to
/// [telemetryProvider], so usage sharing gates it like every
/// other event. The values come from
/// `telemetry_model_buckets.dart` and carry catalog ids and buckets only.
/// Dictation outcomes are counted in the orchestrator, not here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/settings_enums.dart'
    show OnDeviceEngine, SmartModeProviderType;
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'download_error_kind.dart' show DownloadErrorKind;
import 'model_download_service.dart'
    show
        DownloadPhase,
        ModelDownloadState,
        modelDeleteFailedError,
        modelDeleteInUseError,
        modelDownloadProvider;
import 'model_telemetry_identity.dart';
import 'path_service.dart' show isUserModelId;
import 'user_models/user_model.dart'
    show SpeechFallbackChoice, UserModel, UserModelFailure, UserModelStatus;
import 'user_models/user_models_provider.dart' show userModelStoreProvider;
import 'stt_parakeet/parakeet_download_service.dart'
    show ParakeetDownloadPhase, ParakeetDownloadState, parakeetDownloadProvider;
import 'speech_recommendation.dart' show speechRecommendationProvider;
import 'telemetry_model_buckets.dart';
import 'telemetry_service.dart';

final _log = AppLogger('ModelHardwareTelemetry');

/// SharedPreferences key for the local date of the last completed onboarding.
/// Stored on this device only and sent only as a bucket (days since).
const String _onboardingCompletedOnKey = 'telemetry_onboarding_completed_on';

/// Stores the local date on which onboarding completed. Fire-and-forget: a
/// failed write only leaves the bucket at `unknown`.
void recordOnboardingCompletedOn(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  SharedPreferences.getInstance()
      .then<void>((prefs) async {
        await prefs.setString(
          _onboardingCompletedOnKey,
          day.toIso8601String().substring(0, 10),
        );
      })
      .catchError((Object e) => _log.debug('onboarding date not stored: $e'));
}

/// The stored onboarding completion date, or `null` when none was recorded.
DateTime? readOnboardingCompletedOn(SharedPreferences prefs) {
  final raw = prefs.getString(_onboardingCompletedOnKey);
  return raw == null ? null : DateTime.tryParse(raw);
}

/// Sends the model events. Obtain through [modelHardwareTelemetryProvider].
class ModelHardwareTelemetry {
  ModelHardwareTelemetry(this._ref, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _clock;

  void _send({
    required String category,
    required String action,
    required String name,
  }) {
    try {
      _ref
          .read(onboardingTelemetryBufferProvider)
          .track(category: category, action: action, name: name);
    } catch (e) {
      _log.debug('model telemetry skipped: $e');
    }
  }

  /// `onboarding/model_chosen`, sent once when the user commits to a speech
  /// model in onboarding. The name is `<chosen>|<recommended>|<outcome>`, where
  /// the recommendation is the one [speechRecommendationProvider] gives for
  /// this machine (it calls [recommendEngine]).
  void modelChosen({required OnDeviceEngine engine, String? whisperModelId}) {
    final chosen = engine == OnDeviceEngine.parakeet
        ? 'parakeet'
        : whisperCatalogId(whisperModelId ?? '');
    final recommendation = _ref
        .read(speechRecommendationProvider)
        .value
        ?.recommendation;
    final recommended = recommendation == null
        ? 'unknown'
        : recommendedModelId(recommendation);
    final outcome = modelChoiceOutcome(
      chosen: chosen,
      recommended: recommended,
    );
    _send(
      category: 'onboarding',
      action: 'model_chosen',
      name: '$chosen|$recommended|$outcome',
    );
  }

  /// `model/switch` when the user picks another speech model or engine in
  /// Settings. [toCatalogId] is the new model in catalog ids. The current one
  /// is read from settings, so call this before the change is saved. The name
  /// is `<from>><to>|<days-since-onboarding bucket>`.
  void modelSwitched({required String toCatalogId}) {
    final settings = _ref.read(settingsProvider).value;
    if (settings == null) return;
    final from = telemetryModelId(settings);
    if (from == toCatalogId) return;
    final now = _clock();
    SharedPreferences.getInstance()
        .then((prefs) {
          final bucket = daysSinceOnboardingBucket(
            completedOn: readOnboardingCompletedOn(prefs),
            now: now,
          );
          _send(
            category: 'model',
            action: 'switch',
            name: '$from>$toCatalogId|$bucket',
          );
        })
        .catchError((Object e) => _log.debug('model switch skipped: $e'));
  }
}

final modelHardwareTelemetryProvider = Provider<ModelHardwareTelemetry>(
  (ref) => ModelHardwareTelemetry(ref),
);

/// The `model` lifecycle events (#1791): installed, removed, activated,
/// check failed, load failed, fallback. Each is rare and sent as it happens
/// through [onboardingTelemetryBufferProvider], so a first run holds it until
/// the privacy choice and usage sharing gates it. Names are model keys
/// (`telemetryModelId`, `ownModelKey`) and fixed reason ids; a name that
/// fails [isTelemetrySafeName] is dropped, never sent.
class ModelLifecycleTelemetry {
  ModelLifecycleTelemetry(this._ref);

  final Ref _ref;

  void _send(String action, String name) {
    if (!isTelemetrySafeName(name)) {
      _log.warning('model telemetry dropped: unsafe value for $action');
      return;
    }
    try {
      _ref
          .read(onboardingTelemetryBufferProvider)
          .track(category: 'model', action: action, name: name);
    } catch (e) {
      _log.debug('model telemetry skipped: $e');
    }
  }

  /// `model/installed`: a model finished its download and its check. For an
  /// own model ([own]) the name carries its details ([modelEventName]).
  void installed(String modelKey, {OwnModelFacts? own}) =>
      _send('installed', modelEventName(modelKey, own: own));

  /// `model/removed`: a model's files were deleted.
  void removed(String modelKey) => _send('removed', modelKey);

  /// `model/activated`: the speech model in use changed, by any path (the
  /// Settings choice alone is also `model/switch`). For an own model ([own])
  /// the name carries its details ([modelEventName]).
  void activated(String modelKey, {OwnModelFacts? own}) =>
      _send('activated', modelEventName(modelKey, own: own));

  /// `model/check_failed` with `<model>|<check>`: the file failed its hash
  /// (`hash`) or size (`size`) check, or the short test (`short_test`).
  void checkFailed(String modelKey, ModelCheck check) =>
      _send('check_failed', '$modelKey|${check.id}');

  /// `model/load_failed` with `<model>|<cause>|<gpu|cpu>`: loading the model
  /// failed; [cause] is `file`, `hardware` or `timeout`.
  void loadFailed(
    String modelKey, {
    required String cause,
    required bool gpu,
  }) => _send('load_failed', '$modelKey|$cause|${gpu ? 'gpu' : 'cpu'}');

  /// `model/fallback` with `<from>><to>|<reason>` (and `|<detail>` when
  /// given): WhisPaste moved off [fromKey] to a checked model ([toKey], a
  /// catalog model, `cloud`, or `none` when nothing checked is installed).
  /// [reason] is `oom` or `user_model`; for `user_model` the detail is the
  /// failure id (`failed_in_use`, `crashed`, …).
  void fallback({
    required String fromKey,
    required String toKey,
    required String reason,
    String? detail,
  }) => _send(
    'fallback',
    '$fromKey>$toKey|$reason${detail == null ? '' : '|$detail'}',
  );

  /// `model/check_failed` with `<model>|<failure>` for an own model (#1789)
  /// whose format check or short test failed, `failure` being the
  /// [UserModelFailure] id (`bad_format`, `short_test_failed`, …).
  void ownModelCheckFailed(String modelKey, UserModelFailure failure) =>
      _send('check_failed', '$modelKey|${failure.value}');

  /// The end of adding or retrying own model [model] (#1789): ready is
  /// `installed`, a failed download is counted like a catalog one
  /// (`model/download`, source `s1`: an own model has one address per file),
  /// a changed file is `check_failed` `hash`, every other failure
  /// `check_failed` with its id. A model still checking sends nothing.
  void ownModelAdded(UserModel model) {
    final facts = ownModelFactsFrom(model);
    final key = ownModelKey(facts);
    switch (model.status) {
      case UserModelStatus.ready:
        installed(key, own: facts);
      case UserModelStatus.checking:
        return;
      case UserModelStatus.failed:
        final failure = model.failure ?? UserModelFailure.checkUnavailable;
        switch (failure) {
          case UserModelFailure.download || UserModelFailure.diskSpace:
            _countDownloadFailure(
              modelKey: key,
              kind: failure == UserModelFailure.download
                  ? 'network'
                  : 'disk_space',
              source: 1,
            );
          case UserModelFailure.fileChanged:
            checkFailed(key, ModelCheck.hash);
          default:
            ownModelCheckFailed(key, failure);
        }
    }
  }

  void _countDownloadFailure({
    required String modelKey,
    required String kind,
    required int? source,
  }) {
    final name = downloadFailureName(
      modelKey: modelKey,
      kind: kind,
      sourceNumber: source,
    );
    if (!isTelemetrySafeName(name)) {
      _log.warning('model telemetry dropped: unsafe value for download');
      return;
    }
    try {
      _ref
          .read(telemetrySessionAggregatorProvider)
          .count(category: 'model', action: 'download', name: name);
    } catch (e) {
      _log.debug('model telemetry skipped: $e');
    }
  }
}

/// What a failed model check was.
enum ModelCheck {
  hash('hash'),
  size('size'),
  shortTest('short_test');

  const ModelCheck(this.id);
  final String id;
}

final modelLifecycleTelemetryProvider = Provider<ModelLifecycleTelemetry>(
  (ref) => ModelLifecycleTelemetry(ref),
);

/// Finds the own model behind a speech model id, `null` for a catalog id.
typedef OwnModelLookup = OwnModelFacts? Function(String modelId);

/// The telemetry's view of the own models (#1789): reads
/// `user_models.json` for a `user-…` id, so every model event and counter
/// names an own model by [ownModelKey] instead of `other`. Catalog ids,
/// unknown ids and a store that cannot be read give `null`.
final ownModelLookupProvider = Provider<OwnModelLookup>((ref) {
  final store = ref.watch(userModelStoreProvider);
  return (id) {
    if (!isUserModelId(id)) return null;
    try {
      final model = store.readSync().byId(id);
      return model == null ? null : ownModelFactsFrom(model);
    } on Object catch (e) {
      _log.debug('own model lookup failed: ${e.runtimeType}');
      return null;
    }
  };
});

/// The key of speech model id [modelId] (a Whisper catalog id or an own
/// model's `user-…` id): [whisperCatalogId], or [ownModelKey] for an own
/// model. An own model that is gone is `other`.
String modelKeyForId(OwnModelLookup lookup, String modelId) {
  if (!isUserModelId(modelId)) return whisperCatalogId(modelId);
  final own = lookup(modelId);
  return own == null ? 'other' : ownModelKey(own);
}

/// The key of a speech fallback target: the catalog id of [choice], or
/// `none` when no checked model is installed.
String fallbackChoiceKey(SpeechFallbackChoice? choice) {
  if (choice == null) return 'none';
  return switch (OnDeviceEngine.fromValue(choice.engine)) {
    OnDeviceEngine.whisper => whisperCatalogId(choice.modelId),
    OnDeviceEngine.parakeet => 'parakeet',
    OnDeviceEngine.system => 'system',
    OnDeviceEngine.userModel => 'other',
  };
}

/// The Smart Mode text model of [settings] for `model/activated`: `gemma`
/// (the bundled model), the key of an own GGUF model, or `null` when Smart
/// Mode does not run locally (that use is counted by `smart_mode/run`).
String? smartModeModelKey(OwnModelLookup lookup, AppSettings settings) {
  final provider = SmartModeProviderType.fromValue(settings.smartMode.provider);
  if (!provider.isLocal) return null;
  final id = settings.smartMode.localModel;
  if (!isUserModelId(id)) return 'gemma';
  final own = lookup(id);
  return own == null ? 'other' : ownModelKey(own);
}

/// The own model [settings] dictate with, `null` for a catalog model, the
/// system recognition or a cloud provider.
OwnModelFacts? activeOwnModel(OwnModelLookup lookup, AppSettings settings) {
  if (telemetryModelId(settings) != 'other') return null;
  return lookup(settings.effectiveModelId);
}

/// The model key of [settings]: [telemetryModelId], or [ownModelKey] for an
/// own model.
String telemetryModelKey(OwnModelLookup lookup, AppSettings settings) {
  final own = activeOwnModel(lookup, settings);
  return own == null ? telemetryModelId(settings) : ownModelKey(own);
}

/// `model/download` name for a failed download: `<model>|failed|<kind>|s<n>`,
/// where `s<n>` is the number of the source tried last (`s0` when none was
/// reached). Never the source's URL or host.
String downloadFailureName({
  required String modelKey,
  required String kind,
  required int? sourceNumber,
}) => '$modelKey|failed|$kind|s${sourceNumber ?? 0}';

/// Whether a download state's error is a failed delete, not a download.
bool isDeleteError(String? errorMessage) =>
    errorMessage == modelDeleteFailedError ||
    errorMessage == modelDeleteInUseError;

/// Model ids that disappeared from [before] to [after]: removed models.
Set<String> removedModelIds(Set<String> before, Set<String> after) =>
    before.difference(after);

/// Watches the model downloads and the active model for the lifecycle
/// events (#1791): a download that reaches `done` is `installed`, a model
/// that leaves the scanned set (or a Parakeet bundle that is no longer
/// installed) is `removed`, a changed model key in the settings is
/// `activated`. Failed downloads are counted per model, error class and
/// source as `model/download` (session counter). Read once at start
/// (`main.dart`), so the listeners live as long as the app.
final modelLifecycleTelemetryWatcherProvider = Provider<void>((ref) {
  final events = ref.read(modelLifecycleTelemetryProvider);
  void countFailure(String modelKey, DownloadErrorKind? kind, int? source) =>
      events._countDownloadFailure(
        modelKey: modelKey,
        kind: kind?.name ?? 'unknown',
        source: source,
      );

  ref.listen<ModelDownloadState>(modelDownloadProvider, (prev, next) {
    if (next.phase == DownloadPhase.error &&
        prev?.phase != DownloadPhase.error &&
        !isDeleteError(next.errorMessage)) {
      countFailure(
        whisperCatalogId(next.activeModelId ?? prev?.activeModelId ?? ''),
        next.errorKind,
        ref.read(modelDownloadProvider.notifier).lastSourceNumber,
      );
    }
    if (next.phase == DownloadPhase.done &&
        prev?.phase != DownloadPhase.done &&
        next.activeModelId != null) {
      events.installed(whisperCatalogId(next.activeModelId!));
    }
    if (prev != null && prev.scanned && next.scanned) {
      for (final id in removedModelIds(
        prev.downloadedModels,
        next.downloadedModels,
      )) {
        events.removed(whisperCatalogId(id));
      }
    }
  });

  ref.listen<ParakeetDownloadState>(parakeetDownloadProvider, (prev, next) {
    if (next.phase == ParakeetDownloadPhase.error &&
        prev?.phase != ParakeetDownloadPhase.error &&
        !isDeleteError(next.errorMessage)) {
      countFailure(
        'parakeet',
        next.errorKind,
        ref.read(parakeetDownloadProvider.notifier).lastSourceNumber,
      );
    }
    if (prev == null) return;
    if (!prev.installed && next.installed) events.installed('parakeet');
    if (prev.installed && !next.installed) events.removed('parakeet');
  });

  ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
    final before = prev?.value;
    final after = next.value;
    if (before == null || after == null) return;
    final lookup = ref.read(ownModelLookupProvider);
    final key = telemetryModelKey(lookup, after);
    if (telemetryModelKey(lookup, before) != key) {
      events.activated(key, own: activeOwnModel(lookup, after));
    }
    // Smart Mode's local text model, the bundled one or an own GGUF model.
    final smartKey = smartModeModelKey(lookup, after);
    if (smartKey != null && smartModeModelKey(lookup, before) != smartKey) {
      final id = after.smartMode.localModel;
      events.activated(smartKey, own: isUserModelId(id) ? lookup(id) : null);
    }
  });
});

/// Telemetry hooks for the speech model and its use (T1, Matomo spec
/// `internal-notes`).
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

import '../core/config/settings_enums.dart' show OnDeviceEngine;
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'model_download_service.dart'
    show DownloadPhase, ModelDownloadState, modelDownloadProvider;
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

/// Counts failed Whisper model downloads per model and error class, as
/// `model/download` with `<model>|failed|<kind>`. Listens to
/// [modelDownloadProvider]: an error state entered from a non-error state is
/// one failure, whichever path set it. Read once at start (`main.dart`), so
/// the listener lives as long as the app.
final modelDownloadFailureTelemetryProvider = Provider<void>((ref) {
  ref.listen<ModelDownloadState>(modelDownloadProvider, (prev, next) {
    if (next.phase != DownloadPhase.error) return;
    if (prev?.phase == DownloadPhase.error) return;
    final model = whisperCatalogId(
      next.activeModelId ?? prev?.activeModelId ?? '',
    );
    final kind = next.errorKind?.name ?? 'unknown';
    ref
        .read(telemetrySessionAggregatorProvider)
        .count(
          category: 'model',
          action: 'download',
          name: '$model|failed|$kind',
        );
  });
});

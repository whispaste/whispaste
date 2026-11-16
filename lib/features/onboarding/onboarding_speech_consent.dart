// Onboarding v6, V02 (page 1 "Start"): the speech model offered on the start
// page and the consent that starts its download in the background (S6).
//
// The download itself is the existing path ([modelDownloadProvider] for
// Whisper, [parakeetDownloadProvider] for the Parakeet bundle). This file only
// decides what is offered, and starts it once the user agreed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../services/engine_recommendation.dart' show recommendationLanguages;
import '../../services/free_disk_space.dart';
import '../../services/model_hardware_telemetry.dart';
import '../../services/model_download_service.dart';
import '../../services/path_service.dart' show sttDir;
import '../../services/speech_recommendation.dart';
import '../../services/stt_parakeet/parakeet_download_service.dart';
import '../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetSupportedLanguages;
import '../../services/system_speech/system_speech_status.dart';
import '../../widgets/dialog.dart' show showWpConfirmDialog;

final _log = AppLogger('OnboardingSpeech');

/// The speech model the start page offers: the recommendation this machine
/// gets in Settings too (see [speechRecommendationProvider]).
class WelcomeSpeechOffer {
  const WelcomeSpeechOffer({
    required this.engine,
    required this.sizeBytes,
    this.whisperModelId,
  });

  final OnDeviceEngine engine;

  /// The Whisper model to fetch; `null` for Parakeet, which downloads as one
  /// bundle.
  final String? whisperModelId;

  /// Bytes the download puts on disk.
  final int sizeBytes;

  String get sizeLabel => formatModelSizeLabel(sizeBytes);

  /// [sizeLabel] in the number format of [locale] ("1,3 GB" in German).
  String sizeLabelFor(String locale) =>
      formatModelSizeLabel(sizeBytes, locale: locale);

  /// Stable id of this model in the start page's model list.
  String get choiceId => whisperModelId ?? engine.value;

  String engineName(L10n l10n) => switch (engine) {
    OnDeviceEngine.whisper => l10n.onboardingModelEngineWhisperLabel,
    OnDeviceEngine.parakeet => l10n.onboardingModelEngineParakeetLabel,
    OnDeviceEngine.system => l10n.settingsSttEngineSystem,
  };
}

/// The model picked in the start page's model list; `null` keeps the
/// default of [welcomeDefaultOfferProvider].
class WelcomeModelChoiceNotifier extends Notifier<WelcomeSpeechOffer?> {
  @override
  WelcomeSpeechOffer? build() => null;

  void choose(WelcomeSpeechOffer? offer) => state = offer;
}

final welcomeModelChoiceProvider =
    NotifierProvider<WelcomeModelChoiceNotifier, WelcomeSpeechOffer?>(
      WelcomeModelChoiceNotifier.new,
    );

/// The recommended speech model with its download size.
final welcomeSpeechOfferProvider = FutureProvider<WelcomeSpeechOffer>((
  ref,
) async {
  final facts = await ref.watch(speechRecommendationProvider.future);
  final recommendation = facts.recommendation;
  if (recommendation.engine == OnDeviceEngine.parakeet) {
    final settings = await ref.watch(settingsProvider.future);
    return WelcomeSpeechOffer(
      engine: OnDeviceEngine.parakeet,
      sizeBytes: parakeetDownloadBytes(
        gpuWanted: parakeetGpuWantedForSetting(
          settings.behavior.gpuAcceleration,
        ),
      ),
    );
  }
  final model = bestModelForTier(
    recommendation.whisper.tier ?? QualityTier.balanced,
  );
  return WelcomeSpeechOffer(
    engine: OnDeviceEngine.whisper,
    whisperModelId: model.id,
    sizeBytes: model.sizeBytes,
  );
});

/// The catalog model already on disk that the start page offers instead of
/// downloading one (#982): "Einrichten" then sets up that model and fetches
/// nothing. `null` when no catalog model the start page lists is installed;
/// the recommendation and its consented download (S6) stay as they are.
///
/// Order: the recommendation itself when installed; Parakeet when installed
/// and it writes the dictation language; else the installed Whisper model
/// closest below the recommended tier, else the smallest installed one.
WelcomeSpeechOffer? installedWelcomeOffer({
  required WelcomeSpeechOffer recommended,
  required bool parakeetInstalled,
  required bool parakeetFits,
  required int parakeetSizeBytes,
  required Set<String> downloadedWhisperIds,
}) {
  final parakeet = WelcomeSpeechOffer(
    engine: OnDeviceEngine.parakeet,
    sizeBytes: parakeetSizeBytes,
  );
  final whisper = [
    for (final tier in QualityTier.values)
      if (downloadedWhisperIds.contains(bestModelForTier(tier).id))
        (
          tier: tier,
          offer: WelcomeSpeechOffer(
            engine: OnDeviceEngine.whisper,
            whisperModelId: bestModelForTier(tier).id,
            sizeBytes: bestModelForTier(tier).sizeBytes,
          ),
        ),
  ];
  final parakeetUsable = parakeetInstalled && parakeetFits;
  final recommendedInstalled = switch (recommended.engine) {
    OnDeviceEngine.parakeet => parakeetUsable,
    OnDeviceEngine.whisper => whisper.any(
      (w) => w.offer.choiceId == recommended.choiceId,
    ),
    // The welcome step never recommends the Apple engine (opt-in in Settings).
    OnDeviceEngine.system => false,
  };
  if (recommendedInstalled) return recommended;
  if (parakeetUsable) return parakeet;
  if (whisper.isEmpty) return null;
  final wantedTier =
      tierForModel(recommended.whisperModelId ?? '') ?? QualityTier.balanced;
  final atOrBelow = whisper.where((w) => w.tier.index <= wantedTier.index);
  return atOrBelow.isNotEmpty ? atOrBelow.last.offer : whisper.first.offer;
}

/// [installedWelcomeOffer] for this machine, after the first disk scan.
final welcomeInstalledOfferProvider = FutureProvider<WelcomeSpeechOffer?>((
  ref,
) async {
  final recommended = await ref.watch(welcomeSpeechOfferProvider.future);
  await ref.read(modelDownloadProvider.notifier).awaitInitialScan();
  final downloaded = ref.watch(
    modelDownloadProvider.select((s) => s.downloadedModels),
  );
  final parakeetInstalled = ref.watch(
    parakeetDownloadProvider.select((s) => s.installed),
  );
  final settings = await ref.watch(settingsProvider.future);
  final dictationCode = recommendationLanguages(
    sttLanguageCode: settings.sttLanguageCode,
    systemLanguages: ref.watch(systemLanguageCodesProvider),
    uiLocale: settings.locale,
  ).first;
  return installedWelcomeOffer(
    recommended: recommended,
    parakeetInstalled: parakeetInstalled,
    parakeetFits: parakeetSupportedLanguages.contains(dictationCode),
    parakeetSizeBytes: parakeetDownloadBytes(
      gpuWanted: parakeetGpuWantedForSetting(settings.behavior.gpuAcceleration),
    ),
    downloadedWhisperIds: downloaded,
  );
});

/// The model the start page shows before the user picks one: an installed
/// catalog model (no download), else the recommendation.
final welcomeDefaultOfferProvider = FutureProvider<WelcomeSpeechOffer>((
  ref,
) async {
  final installed = await ref.watch(welcomeInstalledOfferProvider.future);
  return installed ?? await ref.watch(welcomeSpeechOfferProvider.future);
});

/// Starts the download the user agreed to on the start page.
///
/// Runs in the background: the caller moves on at once, and the existing
/// download state carries the progress onward. Nothing starts without this
/// call, so a download never runs without the consent.
///
/// [settingsAlreadySet] is `true` once the other-model page has been opened:
/// its selection is then already saved and is the one downloaded. Otherwise
/// the recommendation is saved first.
///
/// Starts at most once: when a download is busy or the model is already on
/// disk, this does nothing further. Returns `false` only when the user declines
/// the disk-space warning, so the flow stays on the start page.
Future<bool> startWelcomeSpeechDownload({
  required BuildContext context,
  required WidgetRef ref,
  required bool settingsAlreadySet,
}) async {
  // A model picked in the start page's list wins over the default: an
  // installed catalog model, else the recommendation.
  final WelcomeSpeechOffer offer =
      ref.read(welcomeModelChoiceProvider) ??
      await ref.read(welcomeDefaultOfferProvider.future);
  await ref.read(modelDownloadProvider.notifier).awaitInitialScan();
  if (!context.mounted) return false;

  // Await the loaded value: while the notifier still builds, `.value` is null
  // and the saved choice would silently fall back to the defaults.
  final settings = await ref.read(settingsProvider.future);
  final engine = settingsAlreadySet
      ? OnDeviceEngine.fromValue(settings.stt.engine)
      : offer.engine;
  final whisperModelId = switch (engine) {
    OnDeviceEngine.parakeet || OnDeviceEngine.system => null,
    OnDeviceEngine.whisper =>
      settingsAlreadySet
          ? settings.stt.model
          : (offer.whisperModelId ?? settings.stt.model),
  };

  if (!settingsAlreadySet) {
    ref
        .read(modelHardwareTelemetryProvider)
        .modelChosen(engine: engine, whisperModelId: whisperModelId);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(sttEngine: engine.value, sttModel: whisperModelId),
        );
  }

  final modelDownload = ref.read(modelDownloadProvider);
  final parakeetDownload = ref.read(parakeetDownloadProvider);
  final installed = switch (engine) {
    // The system engine downloads its asset in Settings, not here.
    OnDeviceEngine.system => true,
    OnDeviceEngine.whisper =>
      whisperModelId != null &&
          modelDownload.downloadedModels.contains(whisperModelId),
    OnDeviceEngine.parakeet =>
      parakeetDownload.installed ||
          parakeetDownload.phase == ParakeetDownloadPhase.done,
  };
  if (installed || modelDownload.isBusy || parakeetDownload.isBusy) {
    _log.info(
      'Start page consent: no download started '
      '(installed=$installed, busy=${modelDownload.isBusy || parakeetDownload.isBusy})',
    );
    return true;
  }

  // Warn before a download the disk cannot hold, as the model step does. The
  // probe can be wrong, so the user may still go ahead.
  final needed = switch (engine) {
    OnDeviceEngine.system => 0,
    OnDeviceEngine.whisper =>
      findSttModel(whisperModelId ?? '')?.sizeBytes ?? offer.sizeBytes,
    OnDeviceEngine.parakeet => parakeetDownloadBytes(
      gpuWanted: parakeetGpuWantedForSetting(settings.behavior.gpuAcceleration),
    ),
  };
  final free = await ref.read(freeDiskSpaceProbeProvider)(sttDir());
  if (!context.mounted) return false;
  if (free != null && free < needed) {
    final l10n = L10n.of(context);
    final proceed = await showWpConfirmDialog(
      context: context,
      title: l10n.onboardingModelDiskSpaceTitle,
      message: l10n.onboardingModelDiskSpaceBody(
        formatModelSizeLabel(needed),
        formatModelSizeLabel(free),
      ),
      confirmLabel: l10n.onboardingModelDiskSpaceContinue,
      cancelLabel: l10n.actionCancel,
    );
    if (!proceed || !context.mounted) return false;
  }

  _log.info('Start page consent: speech model download for ${engine.value}');
  _startDownload(ref, engine, whisperModelId);
  return true;
}

/// Starts the download again for the engine the user chose: the retry after a
/// failed download, and the way to load a model that is missing on the
/// practice page. Failures land in the download state, which the page shows.
Future<void> retryWelcomeSpeechDownload(WidgetRef ref) async {
  final settings = await ref.read(settingsProvider.future);
  final engine = settings.onDeviceEngine;
  _log.info('Speech model download retried for ${engine.value}');
  _startDownload(ref, engine, settings.stt.model);
}

/// Switches the onboarding's speech model to the faster one the practice
/// page offers when the measurement found the chosen one too slow, and starts
/// its download. The previous model stays on disk until the user removes it.
Future<void> switchWelcomeSpeechModel(
  WidgetRef ref, {
  required OnDeviceEngine engine,
  String? whisperModelId,
}) async {
  await ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWith(sttEngine: engine.value, sttModel: whisperModelId),
      );
  _log.info('Practice page: switched to the faster ${engine.value} model');
  _startDownload(ref, engine, whisperModelId);
}

void _startDownload(
  WidgetRef ref,
  OnDeviceEngine engine,
  String? whisperModelId,
) {
  if (engine == OnDeviceEngine.parakeet) {
    unawaited(ref.read(parakeetDownloadProvider.notifier).downloadBundle());
  } else if (engine == OnDeviceEngine.system) {
    // The system loads its own language assets; no app model (#1079).
    unawaited(ref.read(systemSpeechProvider.notifier).install());
  } else if (whisperModelId != null) {
    unawaited(
      ref.read(modelDownloadProvider.notifier).downloadModel(whisperModelId),
    );
  }
}

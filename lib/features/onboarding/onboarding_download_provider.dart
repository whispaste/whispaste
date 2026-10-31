import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../services/model_download_service.dart';
import '../../services/stt_parakeet/parakeet_download_service.dart';
import 'onboarding_download_status.dart';
import 'stt_model_readiness.dart';

/// The engine the first-run setup chose, or null for a cloud provider. The
/// model step persists the choice before it starts a download, so this is the
/// engine that is downloading while the status is running.
final onboardingSelectedEngineProvider = Provider<OnDeviceEngine?>((ref) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  if (settings.sttProviderType != SttProviderType.onDevice) return null;
  return settings.onDeviceEngine;
});

/// The first-run speech-model download for the selected engine, read by the
/// footer on every page and by the practice gate.
///
/// Only the selected engine counts. A download of the other engine does not
/// change the status. The remaining time comes from [DownloadThroughput] over
/// the samples this provider sees and restarts whenever no transfer runs.
final onboardingDownloadStatusProvider =
    NotifierProvider<
      OnboardingDownloadStatusNotifier,
      OnboardingDownloadStatus
    >(OnboardingDownloadStatusNotifier.new);

class OnboardingDownloadStatusNotifier
    extends Notifier<OnboardingDownloadStatus> {
  final Stopwatch _clock = Stopwatch()..start();
  DownloadThroughput _throughput = DownloadThroughput();

  @override
  OnboardingDownloadStatus build() {
    final status = switch (ref.watch(onboardingSelectedEngineProvider)) {
      null => OnboardingDownloadStatus(
        phase: ref.watch(onboardingCloudSttKeyProvider)
            ? OnboardingDownloadPhase.ready
            : OnboardingDownloadPhase.idle,
      ),
      OnDeviceEngine.whisper => _whisper(ref.watch(modelDownloadProvider)),
      OnDeviceEngine.parakeet => _parakeet(ref.watch(parakeetDownloadProvider)),
    };
    if (status.phase != OnboardingDownloadPhase.running) {
      _throughput = DownloadThroughput();
      return status;
    }
    _throughput.record(_clock.elapsed, status.bytesDone);
    return OnboardingDownloadStatus(
      phase: status.phase,
      bytesDone: status.bytesDone,
      bytesTotal: status.bytesTotal,
      remaining: _throughput.remainingFor(status.bytesTotal - status.bytesDone),
    );
  }

  OnboardingDownloadStatus _whisper(ModelDownloadState s) =>
      onboardingStatusFromWhisper(
        phase: s.phase,
        bytesDone: s.bytesDownloaded,
        bytesTotal: s.totalBytes,
        installed: s.downloadedModels.isNotEmpty,
      );

  OnboardingDownloadStatus _parakeet(ParakeetDownloadState s) =>
      onboardingStatusFromParakeet(
        phase: s.phase,
        bytesDone: s.bytesDownloaded,
        bytesTotal: s.totalBytes,
        installed: s.installed,
      );
}

/// The try-out lock of the first-dictation page: a local engine whose model is
/// not ready locks it (see [practiceGateFor]). Read by the page to draw its
/// lock card and by the recording pipeline, through the page's hand-off, to
/// refuse a press.
final onboardingPracticeGateProvider = Provider<PracticeGate>((ref) {
  return practiceGateFor(
    localEngine: ref.watch(onboardingSelectedEngineProvider) != null,
    status: ref.watch(onboardingDownloadStatusProvider),
  );
});

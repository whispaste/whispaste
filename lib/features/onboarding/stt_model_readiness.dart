import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/cloud_stt_keys.dart';
import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../services/model_download_service.dart';
import '../../services/stt_parakeet/parakeet_download_service.dart';

/// Whether any speech-recognition model is on disk, for either engine.
///
/// Read by the onboarding shell (the model page's Next gate) and by the
/// final page (the "all set" claim), so both answer from the same state.
final onboardingSttModelInstalledProvider = Provider<bool>((ref) {
  final whisper = ref.watch(modelDownloadProvider);
  final parakeet = ref.watch(parakeetDownloadProvider);
  return whisper.downloadedModels.isNotEmpty ||
      parakeet.installed ||
      parakeet.phase == ParakeetDownloadPhase.done;
});

/// Whether a speech-model download is running for either engine. A running
/// download continues in the background after the user moves on, so it
/// counts as progress for the model page's Next gate.
final onboardingSttModelDownloadingProvider = Provider<bool>((ref) {
  final whisper = ref.watch(modelDownloadProvider).phase;
  final parakeet = ref.watch(parakeetDownloadProvider).phase;
  return whisper == DownloadPhase.downloading ||
      whisper == DownloadPhase.extracting ||
      whisper == DownloadPhase.verifying ||
      parakeet == ParakeetDownloadPhase.downloading ||
      parakeet == ParakeetDownloadPhase.verifying;
});

/// Whether the chosen speech provider is a cloud one with a saved API key
/// (UIA-MDL-GATE). Cloud transcription needs no local model, so such a user
/// needs no download. A key alone does not count while the local engine is
/// chosen: dictation would still fail for the missing model (G1a).
final onboardingCloudSttKeyProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  return hasSttApiKey(settings.cloudProvider, settings.sttProviderType);
});

/// The cloud provider the model step offers as a choice: one with a saved key
/// while the local engine is chosen. `null` when there is nothing to offer.
final onboardingOfferedCloudSttProvider = Provider<SttProviderType?>((ref) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  if (settings.sttProviderType != SttProviderType.onDevice) return null;
  return firstCloudSttProviderWithKey(settings.cloudProvider);
});

/// Whether speech recognition can work: a model is installed, a download is
/// running (it continues after the user moves on), or a cloud provider with
/// a saved key is chosen.
///
/// Gates the model page's Next and the closing page's Start CTA alike
/// (UIA-RT-01, UIA-MDL-GATE). Only the microphone condition can be bypassed
/// on the closing page, never this one.
final onboardingModelStepCanAdvanceProvider = Provider<bool>(
  (ref) =>
      ref.watch(onboardingSttModelInstalledProvider) ||
      ref.watch(onboardingSttModelDownloadingProvider) ||
      ref.watch(onboardingCloudSttKeyProvider),
);

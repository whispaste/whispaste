/// Categorical values for the model and hardware telemetry (Matomo dimensions
/// 8–12 and the `model` / `onboarding` events). Pure functions: callers pass
/// the facts, these return catalog ids and coarse classes only.
///
/// Never a device, GPU or chip name, a model file name, a serial number or a
/// free text. Every value is a fixed string from the lists in the doc comments.
library;

import '../core/config/settings_enums.dart'
    show OnDeviceEngine, SttProviderType;
import '../core/config/settings_provider.dart' show AppSettings;
import '../core/config/quality_tier.dart' show QualityTier;
import 'engine_recommendation.dart' show EngineRecommendation;
import 'hardware_info_service.dart' show GpuInfo, GpuVendor;
import 'model_download_service.dart' show bestModelForTier;
import 'stt_parakeet/parakeet_download_service.dart'
    show parakeetGpuWantedForSetting;

/// Catalog id for a Whisper model id: `small`, `medium`, `large-v3-turbo`.
/// Anything else is `other`.
String whisperCatalogId(String modelId) => switch (modelId) {
  'whisper-small' => 'small',
  'whisper-medium' => 'medium',
  'whisper-large-v3-turbo' => 'large-v3-turbo',
  _ => 'other',
};

/// The model a dictation or switch runs on: `small`, `medium`,
/// `large-v3-turbo`, `parakeet`, or `cloud` for any cloud provider.
String telemetryModelId(AppSettings settings) {
  if (settings.sttProviderType != SttProviderType.onDevice) return 'cloud';
  if (settings.onDeviceEngine == OnDeviceEngine.parakeet) return 'parakeet';
  return whisperCatalogId(settings.effectiveModelId);
}

/// The model [recommendation] names, in the same ids as [telemetryModelId].
/// `unknown` when no Whisper tier applies and Parakeet is not recommended.
String recommendedModelId(EngineRecommendation recommendation) {
  if (recommendation.engine == OnDeviceEngine.parakeet) return 'parakeet';
  final tier = recommendation.whisper.tier;
  return tier == null ? 'unknown' : whisperCatalogId(bestModelForTier(tier).id);
}

/// Whether the user kept the recommendation. `unknown` when there was no
/// recommendation to compare against, so it never counts as an override.
String modelChoiceOutcome({
  required String chosen,
  required String recommended,
}) {
  if (recommended == 'unknown') return 'unknown';
  return chosen == recommended ? 'accepted' : 'overridden';
}

/// Real-time-factor class: transcription time divided by audio length.
/// `null` when either length is missing or zero, so no bucket is sent.
///
/// RTF is measured across the decoder (since the Kurztest 2a change), so values
/// run somewhat higher than before it. The class edges are far apart on
/// purpose: a shift of a few percent only moves values that sit right on an
/// edge into a neighbouring class.
String? rtfBucket({required int? transcribeMs, required int audioMs}) {
  if (transcribeMs == null || transcribeMs <= 0 || audioMs <= 0) return null;
  final rtf = transcribeMs / audioMs;
  if (rtf < 0.5) return 'lt0_5';
  if (rtf < 1.5) return '0_5_1_5';
  if (rtf < 3) return '1_5_3';
  return 'gt3';
}

/// The compute backend a dictation ran on: `cpu`, `cuda`, `vulkan`, `metal`,
/// or `none` for a cloud provider. Parakeet counts as GPU only when its GPU
/// setting allows one. This is the detected backend, not a CPU fallback taken
/// after a crash.
String telemetryBackend({
  required AppSettings settings,
  required String? optimalBackend,
}) {
  if (settings.sttProviderType != SttProviderType.onDevice) return 'none';
  final gpu = switch (optimalBackend) {
    'cuda' || 'metal' || 'vulkan' => optimalBackend!,
    _ => 'cpu',
  };
  if (settings.onDeviceEngine == OnDeviceEngine.parakeet) {
    return parakeetGpuWantedForSetting(settings.behavior.gpuAcceleration)
        ? gpu
        : 'cpu';
  }
  return gpu;
}

/// RAM class from total RAM in MB. The edges sit a little below the nominal
/// sizes, because operating systems report less than the installed amount
/// (an 8 GB machine reports about 7.8 GB, a 16 GB machine about 15.7 GB).
String ramBucket(int? ramMB) {
  if (ramMB == null || ramMB <= 0) return 'unknown';
  if (ramMB < 7680) return 'lt8';
  if (ramMB <= 16896) return '8_16';
  return 'gt16';
}

/// GPU vendor class: `nvidia`, `amd`, `intel`, `apple`, `none`.
String gpuVendorDimension(GpuVendor? vendor) => vendor?.name ?? 'unknown';

final _appleChip = RegExp(r'\bM([1-4])\b');

/// Mac chip family (`m1`…`m4`, `intel`, or `other` for a chip name this does
/// not know). `n/a` on other systems. The chip name is read only to pick the
/// family and never sent.
String macChipDimension({
  required bool isMacOS,
  required GpuVendor? vendor,
  required String? gpuName,
}) {
  if (!isMacOS) return 'n/a';
  if (vendor == null) return 'unknown';
  if (vendor != GpuVendor.apple) return 'intel';
  final match = _appleChip.firstMatch(gpuName ?? '');
  return match == null ? 'other' : 'm${match.group(1)}';
}

/// Days since onboarding, as a bucket. `unknown` when the completion date is
/// not stored (installs from before this was recorded). [now] is injected so
/// the bucket is testable.
String daysSinceOnboardingBucket({
  required DateTime? completedOn,
  required DateTime now,
}) {
  if (completedOn == null) return 'unknown';
  final days = now.difference(completedOn).inDays;
  if (days < 1) return 'lt1d';
  if (days < 7) return '1_7d';
  if (days < 30) return '7_30d';
  return 'gt30d';
}

/// Visit dimensions 8–12 for the current settings and hardware. Categorical
/// only. The caller sends them only with usage sharing on.
Map<String, String> modelHardwareDimensions({
  required AppSettings settings,
  required GpuInfo? gpu,
  required int? ramMB,
  required bool isMacOS,
}) => {
  'dimension8': telemetryModelId(settings),
  'dimension9': telemetryBackend(
    settings: settings,
    optimalBackend: gpu?.optimalBackend,
  ),
  'dimension10': ramBucket(ramMB),
  'dimension11': gpuVendorDimension(gpu?.vendor),
  'dimension12': macChipDimension(
    isMacOS: isMacOS,
    vendor: gpu?.vendor,
    gpuName: gpu?.name,
  ),
};

/// Maps a [QualityTier] to its catalog id, for the Settings tier pickers.
String tierCatalogId(QualityTier tier) =>
    whisperCatalogId(bestModelForTier(tier).id);

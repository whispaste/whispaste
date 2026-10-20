/// The one speech-model recommendation for this machine, as a provider:
/// onboarding's model step and the Settings speech-recognition section both
/// read [speechRecommendationProvider], so they cannot disagree (MV-04).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart' as app;
import '../core/config/quality_tier.dart';
import '../core/config/settings_provider.dart';
import 'engine_recommendation.dart';
import 'hardware_info_service.dart' as hw;
import 'stt/backend_utilization_notifier.dart' show processorCountProvider;
import 'stt/benchmark_freshness.dart';

/// A recommendation plus the hardware facts its reason names.
class SpeechRecommendation {
  const SpeechRecommendation({
    required this.recommendation,
    required this.gpuName,
    required this.vramMB,
    required this.cpuCores,
    required this.ramMB,
  });

  final EngineRecommendation recommendation;
  final String gpuName;
  final int? vramMB;
  final int cpuCores;

  /// Total RAM, `null` when it could not be read.
  final int? ramMB;
}

/// Total RAM in MB, `null` while unknown. `main.dart` sets it from the RAM
/// preflight it runs at start anyway, so nothing probes twice and tests get a
/// fixed, host-independent figure.
final ramMBProvider = NotifierProvider<RamMB, int?>(RamMB.new);

/// Holder behind [ramMBProvider].
class RamMB extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? mb) => state = mb;
}

/// The recommendation for the current settings and this machine.
final speechRecommendationProvider = FutureProvider<SpeechRecommendation>((
  ref,
) async {
  final gpu = await ref.watch(hw.gpuInfoProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  return speechRecommendationFor(
    settings: settings,
    gpu: gpu,
    cpuCores: ref.watch(processorCountProvider),
    ramMB: ref.watch(ramMBProvider),
  );
});

/// The Whisper tier recommendation for [gpu] and [measuredRtf]: the same
/// call onboarding makes inside [speechRecommendationFor], so Settings, which
/// gets its GPU and filtered measurements from its parent, cannot drift from
/// it (MV-04).
EngineRecommendation whisperRecommendationFor({
  required hw.GpuInfo? gpu,
  required Map<QualityTier, double>? measuredRtf,
  required int cpuCores,
  required int? ramMB,
}) => recommendWhisper(
  vendor: gpu?.vendor,
  vramMB: gpu == null ? null : _vramFor(gpu),
  gpuName: gpu?.name,
  cudaUsable: gpu?.optimalBackend == 'cuda',
  cpuCores: cpuCores,
  ramMB: ramMB,
  measuredRtf: measuredRtf,
);

/// Apple Silicon has no VRAM of its own; its unified memory is the RAM. For
/// any other GPU an unreadable VRAM figure counts as none.
int? _vramFor(hw.GpuInfo gpu) =>
    gpu.vramMB ?? (gpu.vendor == hw.GpuVendor.apple ? null : 0);

/// The pure computation behind [speechRecommendationProvider].
SpeechRecommendation speechRecommendationFor({
  required AppSettings settings,
  required hw.GpuInfo gpu,
  required int cpuCores,
  required int? ramMB,
}) {
  final vramMB = _vramFor(gpu);
  return SpeechRecommendation(
    recommendation: recommendEngine(
      dictationLanguageCode: recommendationLanguage(
        sttLanguageCode: settings.sttLanguageCode,
        uiLocale: settings.locale,
      ),
      vendor: gpu.vendor,
      vramMB: vramMB,
      gpuName: gpu.name,
      cudaUsable: gpu.optimalBackend == 'cuda',
      cpuCores: cpuCores,
      ramMB: ramMB,
      // Only results measured on this machine, build and compute path.
      measuredRtf: benchmarkRtfForMachine(
        benchmark: settings.benchmark,
        gpu: gpu,
        appVersion: app.appVersion,
      ),
    ),
    gpuName: gpu.name,
    vramMB: gpu.vramMB,
    cpuCores: cpuCores,
    ramMB: ramMB,
  );
}

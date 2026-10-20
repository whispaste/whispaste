/// The one model recommendation for this machine: which on-device STT engine
/// to use and, for Whisper, which quality tier. Onboarding ([ModelStep]),
/// the Settings speech-recognition rows and the benchmark row all read it, so
/// they cannot disagree about the same hardware and measurements (UIA-RT-03).
///
/// Deliberately a pure, side-effect-free function so it is trivially unit
/// testable without a widget tree or Riverpod container — see
/// `test/services/engine_recommendation_test.dart`.
library;

import '../core/config/quality_tier.dart' show QualityTier;
import '../core/config/settings_enums.dart' show OnDeviceEngine;
import 'hardware_info_service.dart' show GpuVendor;
import 'model_download_service.dart'
    show TierRecommendationSource, recommendTier, recommendTierFromBenchmark;
import 'stt_parakeet/parakeet_model_registry.dart'
    show parakeetSupportedLanguages;

/// What a recommendation rests on, for its one-line reason (MV-03).
enum RecommendationBasis {
  /// Parakeet covers the dictation language (it is fast on every machine).
  language,

  /// The benchmark measured on this machine and build.
  measured,

  /// Apple Silicon: Metal on unified memory.
  appleSilicon,

  /// An NVIDIA GPU the CUDA build runs on.
  cudaGpu,

  /// Any other GPU, run through Vulkan.
  vulkanGpu,

  /// No usable GPU: the processor does the work.
  cpuOnly,

  /// A software Vulkan device such as llvmpipe, which is the processor in
  /// disguise and counts as such (UIA-XP-7-03).
  softwareRenderer,

  /// Neither GPU info nor a measurement yet.
  unknown,
}

/// Result of [recommendEngine]: which on-device engine is recommended and,
/// for Whisper, which quality tier.
class EngineRecommendation {
  const EngineRecommendation({
    required this.engine,
    this.tier,
    this.tierSource,
    this.basis = RecommendationBasis.unknown,
    this.withinWhisper,
  });

  /// The recommended engine.
  final OnDeviceEngine engine;

  /// The recommended Whisper quality tier, or `null` when no tier applies:
  /// Parakeet is recommended (it ships as one bundle), or there is neither a
  /// measurement nor a VRAM figure to estimate from.
  final QualityTier? tier;

  /// Whether [tier] rests on this machine's measurements or on the VRAM
  /// estimate. `null` exactly when [tier] is `null`.
  final TierRecommendationSource? tierSource;

  /// What the recommendation rests on.
  final RecommendationBasis basis;

  /// The Whisper recommendation behind a Parakeet one; `null` when this
  /// already is the Whisper recommendation. Read [whisper] instead.
  final EngineRecommendation? withinWhisper;

  /// The recommendation within Whisper, also when Parakeet is recommended:
  /// a user who switches to Whisper by hand gets the tier this machine
  /// warrants from the same rule.
  EngineRecommendation get whisper => withinWhisper ?? this;
}

/// Whether [gpuName] is a software renderer (llvmpipe, lavapipe, softpipe,
/// SwiftShader, Microsoft Basic Render Driver). Such a device runs on the
/// processor, so a recommendation treats it as CPU (UIA-XP-7-03).
bool isSoftwareRenderer(String gpuName) => _softwareRenderer.hasMatch(gpuName);

final _softwareRenderer = RegExp(
  r'llvmpipe|lavapipe|softpipe|swiftshader|microsoft basic render',
  caseSensitive: false,
);

/// Whether Parakeet is the recommended engine for [languageCode].
///
/// Language-only on purpose: Parakeet is faster than Whisper on every machine
/// (`CONTEXT.md` §4.2), so hardware never rules it out, only the language can.
bool parakeetRecommendedFor(String languageCode) =>
    parakeetSupportedLanguages.contains(_normalizeLanguageCode(languageCode));

/// The language a recommendation is made for: the chosen dictation language
/// (`AppSettings.sttLanguageCode`), or the UI locale while that is `'auto'`.
String recommendationLanguage({
  required String sttLanguageCode,
  required String uiLocale,
}) => sttLanguageCode == 'auto' ? uiLocale : sttLanguageCode;

/// Recommends an engine and, for Whisper, a tier.
///
/// - [dictationLanguageCode]: an ISO 639-1 code (or any locale string,
///   normalized internally). The app's UI locale stands in for the dictation
///   language until the user chooses one, see [parakeetRecommendedFor].
/// - Hardware and [measuredRtf]: as in [recommendWhisper].
///
/// A recommendation only marks a choice; it never locks one.
EngineRecommendation recommendEngine({
  required String dictationLanguageCode,
  GpuVendor? vendor,
  int? vramMB,
  String? gpuName,
  bool cudaUsable = false,
  int? cpuCores,
  int? ramMB,
  Map<QualityTier, double>? measuredRtf,
}) {
  final whisper = recommendWhisper(
    vendor: vendor,
    vramMB: vramMB,
    gpuName: gpuName,
    cudaUsable: cudaUsable,
    cpuCores: cpuCores,
    ramMB: ramMB,
    measuredRtf: measuredRtf,
  );
  if (parakeetRecommendedFor(dictationLanguageCode)) {
    return EngineRecommendation(
      engine: OnDeviceEngine.parakeet,
      basis: RecommendationBasis.language,
      withinWhisper: whisper,
    );
  }
  return whisper;
}

/// The Whisper tier this machine warrants, whatever the language: the
/// recommendation within Whisper once Whisper is the active engine
/// (UIA-RT-03, E2a), by hardware class (MV-03).
///
/// - [vendor] / [vramMB] / [gpuName] / [cudaUsable]: from `hw.GpuInfo`
///   ([cudaUsable] is `optimalBackend == 'cuda'`). When [vramMB] is `null`
///   and the GPU is not Apple Silicon, the GPU is unknown and the tier comes
///   only from [measuredRtf].
/// - [cpuCores] / [ramMB]: the processor count and total RAM. They decide
///   the tier when the processor does the work, and cap an integrated GPU on
///   a machine with little RAM. Unknown values count as weak.
/// - [measuredRtf]: the RTFs measured on this machine and build, already
///   filtered (see `benchmarkRtfForMachine`). When it names a tier that is
///   fast enough, that verdict wins over the estimate.
EngineRecommendation recommendWhisper({
  GpuVendor? vendor,
  int? vramMB,
  String? gpuName,
  bool cudaUsable = false,
  int? cpuCores,
  int? ramMB,
  Map<QualityTier, double>? measuredRtf,
}) {
  final measured = measuredRtf == null
      ? null
      : recommendTierFromBenchmark(measuredRtf);
  if (measured != null) {
    return EngineRecommendation(
      engine: OnDeviceEngine.whisper,
      tier: measured,
      tierSource: TierRecommendationSource.measured,
      basis: RecommendationBasis.measured,
    );
  }
  final apple = vendor == GpuVendor.apple;
  final memory = vramMB ?? (apple ? ramMB : null);
  if (memory == null) {
    return const EngineRecommendation(engine: OnDeviceEngine.whisper);
  }
  final software = gpuName != null && isSoftwareRenderer(gpuName);
  final basis = software
      ? RecommendationBasis.softwareRenderer
      : switch (vendor) {
          null || GpuVendor.none => RecommendationBasis.cpuOnly,
          GpuVendor.apple => RecommendationBasis.appleSilicon,
          GpuVendor.nvidia when cudaUsable => RecommendationBasis.cudaGpu,
          _ => RecommendationBasis.vulkanGpu,
        };
  final QualityTier tier = switch (basis) {
    RecommendationBasis.cpuOnly ||
    RecommendationBasis.softwareRenderer => _cpuTier(cpuCores, ramMB),
    RecommendationBasis.vulkanGpu
        when vendor != GpuVendor.nvidia &&
            (ramMB ?? 0) < _iGpuMinRamMB &&
            ramMB != null =>
      QualityTier.compact,
    _ => recommendTier(memory, vendor: vendor),
  };
  return EngineRecommendation(
    engine: OnDeviceEngine.whisper,
    tier: tier,
    tierSource: TierRecommendationSource.estimated,
    basis: basis,
  );
}

/// Below this much RAM an integrated GPU's shared memory is too tight for
/// more than the compact tier.
const _iGpuMinRamMB = 8192;

/// The tier the processor alone carries: never premium, balanced only on a
/// machine with many cores and plenty of RAM, compact otherwise.
QualityTier _cpuTier(int? cores, int? ramMB) =>
    (cores ?? 0) >= 8 && (ramMB ?? 0) >= 16384
    ? QualityTier.balanced
    : QualityTier.compact;

/// Reduces a locale string (`'de'`, `'de_DE'`, `'de-DE'`, `'auto'`, ...) to a
/// bare lowercase language code. Unknown/empty input falls through to a
/// value that will simply miss [parakeetSupportedLanguages] — no special
/// casing needed, Whisper is the correct fallback for anything unrecognized.
String _normalizeLanguageCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp('[_-]')).first.toLowerCase();
}

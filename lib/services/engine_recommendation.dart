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
import '../core/config/whisper_languages.dart' show systemDictationLanguages;
import 'hardware_info_service.dart' show GpuVendor;
import 'model_download_service.dart'
    show
        TierRecommendationSource,
        kFluentRtf,
        recommendTier,
        recommendTierFromBenchmark;
import 'stt_parakeet/parakeet_model_registry.dart'
    show parakeetSupportedLanguages;

/// What a recommendation rests on, for its one-line reason (MV-03).
enum RecommendationBasis {
  /// Parakeet writes the dictation languages and is the most accurate
  /// choice that runs fluently here (see [recommendEngine]).
  language,

  /// The benchmark measured on this machine and build.
  measured,

  /// Larger tiers extrapolated from the setup's compact-model speech test.
  projected,

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
    this.projectedFluent,
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

  /// Whether the chosen tier is projected below the fluent threshold.
  final bool? projectedFluent;

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

/// Whether Parakeet writes every one of [languageCodes], the precondition
/// for recommending it. A speaker of German and Japanese needs Whisper for
/// the Japanese. Whether it is then recommended depends on the hardware too,
/// see [recommendEngine].
bool parakeetRecommendedFor(Iterable<String> languageCodes) {
  final codes = languageCodes.map(_normalizeLanguageCode).toList();
  return codes.isNotEmpty && codes.every(parakeetSupportedLanguages.contains);
}

/// The languages a recommendation is made for, the user's dictation
/// languages: the chosen dictation language (`AppSettings.sttLanguageCode`,
/// skipped while it is `'auto'`) first, then the favorite languages
/// (`settings.stt.favoriteLanguages`, #1209), then every system language
/// Whisper writes, in the system's order. A German and Japanese speaker who
/// dictates German still speaks Japanese. The UI locale stands in when none
/// names a language. The model library marks against the same list which
/// models write them (#1953).
List<String> recommendationLanguages({
  required String sttLanguageCode,
  Iterable<String> favoriteLanguages = const [],
  required Iterable<String> systemLanguages,
  required String uiLocale,
}) {
  final languages = {
    if (sttLanguageCode != 'auto') _normalizeLanguageCode(sttLanguageCode),
    for (final code in favoriteLanguages)
      if (_normalizeLanguageCode(code) case final c
          when c.isNotEmpty && c != 'auto')
        c,
    ...systemDictationLanguages(systemLanguages),
  };
  return languages.isEmpty
      ? [_normalizeLanguageCode(uiLocale)]
      : languages.toList();
}

/// Recommends an engine and, for Whisper, a tier: the most accurate model
/// this machine runs fluently (maintainer, 2026-10-30).
///
/// - [dictationLanguageCodes]: ISO 639-1 codes (or any locale strings,
///   normalized internally), see [recommendationLanguages]. Parakeet only
///   when it writes all of them, see [parakeetRecommendedFor].
/// - Hardware and [measuredRtf]: as in [recommendWhisper], which yields the
///   largest Whisper tier that runs fluently here.
///
/// Accuracy order behind the choice (public WER figures, FLEURS and the
/// open ASR leaderboard): outside English the premium Whisper tier is a
/// little more accurate than Parakeet, Parakeet clearly more than the
/// balanced and compact tiers; in English Parakeet leads. Parakeet runs
/// fluently on every machine, so it is the answer wherever the hardware
/// does not carry the premium tier.
///
/// A recommendation only marks a choice; it never locks one.
EngineRecommendation recommendEngine({
  required Iterable<String> dictationLanguageCodes,
  GpuVendor? vendor,
  int? vramMB,
  String? gpuName,
  bool cudaUsable = false,
  int? cpuCores,
  int? ramMB,
  Map<QualityTier, double>? measuredRtf,
  double? compactBenchmarkRtf,
}) {
  final whisper = recommendWhisper(
    vendor: vendor,
    vramMB: vramMB,
    gpuName: gpuName,
    cudaUsable: cudaUsable,
    cpuCores: cpuCores,
    ramMB: ramMB,
    measuredRtf: measuredRtf,
    compactBenchmarkRtf: compactBenchmarkRtf,
  );
  final codes = dictationLanguageCodes.map(_normalizeLanguageCode).toSet();
  final premiumWins =
      whisper.tier == QualityTier.premium && !codes.every((c) => c == 'en');
  if (parakeetRecommendedFor(codes) && !premiumWins) {
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
  double? compactBenchmarkRtf,
}) {
  final projected = projectCompactBenchmark(compactBenchmarkRtf);
  final candidates = {...?projected, ...?measuredRtf};
  final measuredTier = recommendTierFromBenchmark(candidates);
  if (measuredTier != null) {
    final directlyMeasured = measuredRtf?.containsKey(measuredTier) ?? false;
    return EngineRecommendation(
      engine: OnDeviceEngine.whisper,
      tier: measuredTier,
      tierSource: directlyMeasured
          ? TierRecommendationSource.measured
          : TierRecommendationSource.estimated,
      basis: directlyMeasured
          ? RecommendationBasis.measured
          : RecommendationBasis.projected,
      projectedFluent: directlyMeasured
          ? null
          : candidates[measuredTier]! < kFluentRtf,
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

/// Strong hardware uses the existing static tier table without a short test.
/// Unknown hardware, CPU/software Vulkan and smaller GPUs need a measurement.
bool needsShortModelBenchmark({
  required GpuVendor? vendor,
  required int? vramMB,
  required int? ramMB,
  required String? gpuName,
  required bool cudaUsable,
  bool gpuAccelerationEnabled = true,
}) {
  if (!gpuAccelerationEnabled) return true;
  if (gpuName != null && isSoftwareRenderer(gpuName)) return true;
  return switch (vendor) {
    GpuVendor.apple => (ramMB ?? 0) < 8192,
    GpuVendor.nvidia when cudaUsable => (vramMB ?? 0) < 4096,
    GpuVendor.amd ||
    GpuVendor.intel => (vramMB ?? 0) < 12288 || (ramMB ?? 0) < 16384,
    _ => true,
  };
}

/// CPU calibration, 2026-11-10, tc-m93p / i5-4570T, whisper.cpp v1.9.5,
/// three threads, reference-de.wav, warm-up + mean of two runs.
/// Compact is small-q5_1. Full protocol: internal-notes.
const compactBenchmarkRatios = <QualityTier, double>{
  QualityTier.compact: 1,
  QualityTier.balanced: 3.2239,
  QualityTier.premium: 5.6154,
};

/// RTF < 0.8 is fluent (strict boundary): under eight seconds of processing
/// per ten seconds of speech. Invalid/missing results retain the static rule.
Map<QualityTier, double>? projectCompactBenchmark(double? compactRtf) {
  if (compactRtf == null || !compactRtf.isFinite || compactRtf <= 0) {
    return null;
  }
  return {
    for (final entry in compactBenchmarkRatios.entries)
      entry.key: compactRtf * entry.value,
  };
}

/// The faster choice to offer when the chosen Whisper [tier] measured [rtf]
/// on this machine (maintainer decision 2a, 2026-10-30): `null` while it is
/// fluent or unmeasured. Otherwise Parakeet when [recommendation] names it,
/// else the smaller Whisper tier the recommendation now gives, or `null`
/// when there is none smaller.
EngineRecommendation? fasterChoiceWhenSlow({
  required QualityTier tier,
  required double? rtf,
  required EngineRecommendation recommendation,
}) {
  if (rtf == null || rtf < kFluentRtf) return null;
  if (recommendation.engine == OnDeviceEngine.parakeet) return recommendation;
  final faster = recommendation.whisper.tier;
  if (faster == null || faster.index >= tier.index) return null;
  return recommendation.whisper;
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

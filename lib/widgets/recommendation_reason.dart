/// The one-line reason under a speech-model recommendation (MV-03), shared by
/// onboarding's model step and the Settings speech-recognition section.
library;

import '../core/l10n/generated/app_localizations.dart';
import '../services/engine_recommendation.dart';
import '../services/speech_recommendation.dart';

/// The reason for [recommendation], or `null` when it rests on nothing yet
/// (no GPU info, no measurement).
String? recommendationReason(
  L10n l10n,
  SpeechRecommendation facts,
  EngineRecommendation recommendation,
) {
  final memory = facts.ramMB == null
      ? l10n.recommendationMemoryUnknown
      : l10n.recommendationMemory(_gb(facts.ramMB!));
  return switch (recommendation.basis) {
    RecommendationBasis.language => l10n.recommendationReasonLanguage,
    RecommendationBasis.measured => l10n.recommendationReasonMeasured,
    RecommendationBasis.appleSilicon => l10n.recommendationReasonApple(memory),
    RecommendationBasis.cudaGpu => l10n.recommendationReasonCuda(
      _gb(facts.vramMB ?? 0),
    ),
    RecommendationBasis.vulkanGpu => l10n.recommendationReasonVulkan(
      facts.gpuName,
    ),
    RecommendationBasis.cpuOnly => l10n.recommendationReasonCpu(
      facts.cpuCores,
      memory,
    ),
    RecommendationBasis.softwareRenderer => l10n.recommendationReasonSoftware(
      facts.gpuName,
      facts.cpuCores,
      memory,
    ),
    RecommendationBasis.unknown => null,
  };
}

/// MB as whole GB, rounded.
String _gb(int mb) => (mb / 1024).round().toString();

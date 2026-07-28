/// Auto-recommends an on-device STT engine (and, for Whisper, a quality
/// tier) for the onboarding [ModelStep]'s two-way choice.
///
/// Deliberately a pure, side-effect-free function so it is trivially unit
/// testable without a widget tree or Riverpod container — see
/// `test/services/engine_recommendation_test.dart`.
library;

import '../core/config/settings_enums.dart' show OnDeviceEngine;
import 'hardware_info_service.dart' show GpuVendor;
import 'model_download_service.dart' show QualityTier, recommendTier;
import 'stt_parakeet/parakeet_model_registry.dart'
    show parakeetSupportedLanguages;

/// Result of [recommendEngine]: which on-device engine to preselect, and —
/// only when [engine] is [OnDeviceEngine.whisper] — which Whisper quality
/// tier to preselect for the download.
class EngineRecommendation {
  const EngineRecommendation({required this.engine, this.tier});

  /// The recommended engine.
  final OnDeviceEngine engine;

  /// The recommended Whisper quality tier, or `null` when [engine] is
  /// [OnDeviceEngine.parakeet] (Parakeet has no quality tiers — it ships as
  /// one bundle).
  final QualityTier? tier;
}

/// Recommends an engine for the given dictation language and hardware.
///
/// The decision is language-first: Parakeet is faster than Whisper on every
/// machine (see `CONTEXT.md` §4.2 — RTF 0.10–0.13 vs. 0.43–1.16), so hardware
/// never rules Parakeet *out*. It only decides which Whisper tier to
/// recommend when Parakeet isn't eligible in the first place.
///
/// - [dictationLanguageCode]: an ISO 639-1 code (or any locale string —
///   normalized internally). Typically the onboarding Welcome step's chosen
///   UI locale, since the app has no earlier signal for the language the
///   user will actually dictate in.
/// - [vendor] / [vramMB]: from `hw.GpuInfo`, feeds [recommendTier] for the
///   Whisper branch exactly as the pre-existing tier-only recommendation did.
EngineRecommendation recommendEngine({
  required String dictationLanguageCode,
  required GpuVendor vendor,
  required int vramMB,
}) {
  final code = _normalizeLanguageCode(dictationLanguageCode);
  if (parakeetSupportedLanguages.contains(code)) {
    return const EngineRecommendation(engine: OnDeviceEngine.parakeet);
  }
  return EngineRecommendation(
    engine: OnDeviceEngine.whisper,
    tier: recommendTier(vramMB, vendor: vendor),
  );
}

/// Reduces a locale string (`'de'`, `'de_DE'`, `'de-DE'`, `'auto'`, ...) to a
/// bare lowercase language code. Unknown/empty input falls through to a
/// value that will simply miss [parakeetSupportedLanguages] — no special
/// casing needed, Whisper is the correct fallback for anything unrecognized.
String _normalizeLanguageCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp('[_-]')).first.toLowerCase();
}

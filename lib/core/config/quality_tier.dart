/// Quality-tier enum — shared between [settings_sections.dart],
/// [settings_provider.dart], and [model_download_service.dart].
///
/// Kept in `core/config/` so the settings layer can reference it without
/// importing the full model-download service, breaking a circular dependency.
library;

/// User-facing quality tiers that abstract away model internals.
enum QualityTier { compact, balanced, premium }

/// Shared helper utilities for recording UI/UX logic.
library;

import '../l10n/generated/app_localizations.dart';
import '../../services/model_download_service.dart';

/// Context-aware done message based on the afterAction setting.
///
/// Extracted from RecordingPill so it can be reused by the floating overlay
/// service without depending on the widget layer.
String doneMessageFor(String? afterAction, L10n l10n) {
  return switch (afterAction) {
    'paste' => l10n.overlayDonePasted,
    'copy_and_paste' || 'clipboard_and_paste' => l10n.overlayDoneBoth,
    'clipboard' || 'copy' => l10n.overlayDone,
    _ => l10n.overlayDoneReady,
  };
}

/// Maps a raw model ID (e.g. "whisper-small") to a user-facing label
/// showing the quality tier as primary and the Whisper model in parentheses.
///
/// Example: "Ausgewogen (Whisper Medium)" for "whisper-medium".
/// Falls back to [modelId] when no matching tier or model is found.
String displayNameForModel(String modelId, L10n l10n) {
  final tier = tierForModel(modelId);
  if (tier == null) return modelId;

  final tierLabel = switch (tier) {
    QualityTier.compact => l10n.qualityTierCompactLabel,
    QualityTier.balanced => l10n.qualityTierBalancedLabel,
    QualityTier.premium => l10n.qualityTierPremiumLabel,
  };

  final model = findSttModel(modelId);
  if (model == null) return tierLabel;

  return l10n.analyticsModelDisplayName(tierLabel, model.label);
}

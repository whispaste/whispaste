/// Shared helper utilities for recording UI/UX logic.
library;

import '../l10n/generated/app_localizations.dart';
import 'recording_state.dart' show RecordingTarget;
import '../../services/model_download_service.dart';
import '../../services/stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelId;

/// Context-aware done message based on the afterAction setting.
///
/// Extracted from RecordingPill so it can be reused by the floating overlay
/// service without depending on the widget layer.
///
/// [target] überstimmt die Ableitung aus [afterAction]: bei
/// [RecordingTarget.quickNote] wird nichts kopiert und nichts eingefügt — der
/// Text hängt an der Schnellnotiz. Die Auto-Einfügen-Einstellung sagt über
/// diesen Vorgang also gar nichts aus (Ticket 25). Voreinstellung ist
/// [RecordingTarget.clipboard], damit alle bisherigen Aufrufer unverändert
/// bleiben.
String doneMessageFor(
  String? afterAction,
  L10n l10n, {
  RecordingTarget target = RecordingTarget.clipboard,
}) {
  if (target == RecordingTarget.quickNote) return l10n.overlayDoneQuickNote;
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
/// Parakeet has no quality tiers — it maps directly to its display title.
/// Falls back to [modelId] when no matching tier or model is found.
String displayNameForModel(String modelId, L10n l10n) {
  if (modelId == parakeetModelId) return l10n.parakeetModelTitle;

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

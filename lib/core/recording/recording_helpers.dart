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
///
/// [pasteFailed] ist das reale Ergebnis des Einfügeversuchs: ein fehlgeschlagenes
/// Einfügen darf nie als „Eingefügt“ erscheinen, auch wenn die Einstellung
/// einfügt. Ob der Text zusätzlich in der Zwischenablage liegt, meldet der
/// Fehlerpfad nicht, daher steht hier bewusst nur „nicht eingefügt“.
String doneMessageFor(
  String? afterAction,
  L10n l10n, {
  RecordingTarget target = RecordingTarget.clipboard,
  bool pasteFailed = false,
  bool copiedOnly = false,
  bool historyOnly = false,
}) {
  if (target == RecordingTarget.quickNote) return l10n.overlayDoneQuickNote;
  if (target == RecordingTarget.selectionEdit) {
    return l10n.overlayDoneSelectionEdit;
  }
  if (historyOnly) return l10n.overlayDoneNotPasted;
  if (copiedOnly) return l10n.overlayDoneCopiedOnly;
  if (pasteFailed) return l10n.overlayDonePasteFailed;
  return switch (afterAction) {
    'paste' => l10n.overlayDonePasted,
    'copy_and_paste' || 'clipboard_and_paste' => l10n.overlayDoneBoth,
    'clipboard' || 'copy' => l10n.overlayDone,
    _ => l10n.overlayDoneReady,
  };
}

/// Family names of the local speech models. These are proper nouns and are
/// never translated (CONTEXT.md §5.3a, UIA-NAM-01).
const String sttWhisperFamilyName = 'Whisper';
const String sttParakeetFamilyName = 'Parakeet';

/// The localized tier word of [tier] ("Fast" / "Balanced" / "Accurate").
String sttTierLabel(QualityTier tier, L10n l10n) => switch (tier) {
  QualityTier.compact => l10n.qualityTierCompactLabel,
  QualityTier.balanced => l10n.qualityTierBalancedLabel,
  QualityTier.premium => l10n.qualityTierPremiumLabel,
};

/// The one display name of a speech model, used by every surface (dock,
/// settings, onboarding, statistics, history, toasts). Main name is always
/// `<Family> · <Tier>`, e.g. "Whisper · Balanced"; Parakeet has no tier and is
/// just "Parakeet". Technical IDs, sizes and quantisation never appear here.
///
/// Falls back to [modelId] when the model is unknown.
String displayNameForModel(String modelId, L10n l10n) {
  if (modelId == parakeetModelId) return sttParakeetFamilyName;

  final tier = tierForModel(modelId);
  if (tier == null) return modelId;

  return '$sttWhisperFamilyName · ${sttTierLabel(tier, l10n)}';
}

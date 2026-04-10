/// Shared helper utilities for recording UI/UX logic.
library;

import '../l10n/generated/app_localizations.dart';

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

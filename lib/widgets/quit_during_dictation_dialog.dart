/// Asks before the tray quits the app while a dictation is still running.
library;

import 'package:flutter/widgets.dart';

import '../core/l10n/generated/app_localizations.dart';
import 'dialog.dart';

/// Quitting stops the recording or transcription and loses its text, so the
/// confirm is destructive and Cancel is the focused default (UIA-SHL-15).
/// Returns `true` only when the user confirms the quit.
Future<bool> showWpQuitDuringDictationDialog({
  required BuildContext context,
  required L10n l10n,
}) {
  return confirmDestructive(
    context: context,
    title: l10n.quitDuringDictationTitle,
    message: l10n.quitDuringDictationMessage,
    confirmLabel: l10n.trayQuit,
    cancelLabel: l10n.actionCancel,
  );
}

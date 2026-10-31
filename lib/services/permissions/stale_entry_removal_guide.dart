/// The one recovery for a stale Auto-Paste permission entry on the sandboxed
/// Mac App Store build — shared by the startup gate, the restart watch and the
/// manual "repair" buttons so all of them walk the same path.
///
/// A sandboxed app cannot delete its own TCC entry, and a stale entry can
/// neither be re-requested (macOS shows no dialog while an entry exists) nor
/// re-bound by toggling it. What works, verified on macOS 26: the user removes
/// the row with "−", then a fresh process requests again and macOS shows its
/// own dialog. The native guide explains the removal, opens the pane and
/// offers the relaunch once the user is back.
library;

import 'dart:async';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/platform/macos_lifecycle_channel.dart';
import '../paste/paste_capability_notifier.dart';

/// Shows the native removal guide and, when the user asks for it, relaunches
/// via [PasteCapabilityNotifier.restartForEntryRemoval]. Resolves `true` when
/// the relaunch was requested.
Future<bool> runStaleEntryRemovalGuide({
  required L10n l10n,
  required PasteCapabilityNotifier notifier,
}) async {
  final choice = Completer<bool>();
  final dispatched = await MacOSLifecycleChannel.showStaleEntryRemovalGuide(
    id: 'stale_entry_removal',
    title: l10n.pasteStaleEntryGuideTitle,
    body: l10n.pasteStaleEntryGuideBody,
    confirmLabel: l10n.pasteStaleEntryGuideConfirm,
    cancelLabel: l10n.permissionAlertLaterButton,
    restartTitle: l10n.pasteStaleEntryRestartTitle,
    restartBody: l10n.pasteStaleEntryRestartBody,
    restartConfirmLabel: l10n.pasteStaleEntryRestartConfirm,
    restartCancelLabel: l10n.permissionAlertLaterButton,
    onDismiss: (restart) {
      if (!choice.isCompleted) choice.complete(restart);
    },
  );
  if (!dispatched) return false;
  final restart = await choice.future;
  if (restart) await notifier.restartForEntryRemoval();
  return restart;
}

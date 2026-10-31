/// Block C: the "Rückgängig" toast after a Smart-Mode dictation and the
/// undo/restore row in the History detail panel.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../services/paste/paster.dart';
import '../../../services/selection_edit/selection_undo.dart';
import '../../../services/smart_mode/smart_mode_name_change_notice.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../data/history_detail_provider.dart';

/// Shows the success toast with a one-click undo for [entryId].
void showSmartModeUndoToast({
  required BuildContext context,
  required WidgetRef ref,
  required String entryId,
}) {
  final l10n = L10n.of(context);
  WpToast.show(
    context,
    message: l10n.smartModeUndoToastMessage,
    type: WpToastType.success,
    action: WpToastAction(
      label: l10n.smartModeUndoAction,
      testId: 'toast-smart-undo',
      onPressed: () => unawaited(_undoFromToast(context, ref, entryId)),
    ),
  );
}

/// The toast's undo. With an open detail panel it runs through the notifier,
/// so the `applyingPreset` check and the shared lock apply (DEV-155) and the
/// panel updates at once (DEV-154). Without one the provider is auto-disposed
/// and no preset can be running, so the same lock guards a direct write.
Future<void> _undoFromToast(
  BuildContext context,
  WidgetRef ref,
  String entryId,
) async {
  final detail = historyDetailProvider(entryId);
  final panelBusy =
      ref.exists(detail) &&
      (ref.read(detail).asData?.value.applyingPreset ?? false);
  final lock = ref.read(smartModeBusyProvider.notifier);
  if (panelBusy || ref.read(smartModeBusyProvider).contains(entryId)) {
    _showBusy(context);
    return;
  }
  if (ref.exists(detail)) {
    await ref.read(detail.notifier).undoSmartMode();
    return;
  }
  // No detail panel: take the lock here, so a concurrent apply cannot start.
  if (!lock.tryAcquire(entryId)) {
    _showBusy(context);
    return;
  }
  try {
    await ref.read(historyDatabaseProvider).undoSmartMode(entryId);
  } finally {
    lock.release(entryId);
  }
  ref.invalidate(detail);
}

/// Says so instead of dropping the tap silently (DEV-175).
void _showBusy(BuildContext context) {
  if (!context.mounted) return;
  WpToast.show(
    context,
    message: L10n.of(context).smartModeBusyRetry,
    type: WpToastType.info,
  );
}

/// Undo or restore for a Smart-Mode run, shown above the entry content. It
/// disappears as soon as a manual edit or re-transcription ends the run.
class SmartModeUndoRow extends ConsumerWidget {
  const SmartModeUndoRow({
    super.key,
    required this.entryId,
    required this.fallback,
  });

  final String entryId;

  /// Shown until the detail state has loaded.
  final HistoryEntry fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(historyDetailProvider(entryId)).asData?.value;
    final entry = detail?.entry ?? fallback;
    // Locked while a preset or another undo/restore writes this entry (DEV-175).
    final locked = ref.watch(smartModeBusyProvider).contains(entryId);
    final busy = (detail?.applyingPreset ?? false) || locked;
    final hasInput =
        entry.smartModeInput != null || entry.originalTranscript != null;
    if (entry.smartModeApplied != true || !hasInput) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context);
    final undone = entry.smartModeOutput != null;
    final notifier = ref.read(historyDetailProvider(entryId).notifier);
    final button = WpButton(
      testId: undone
          ? 'history-entry-smart-restore'
          : 'history-entry-smart-undo',
      label: undone ? l10n.historySmartModeRestore : l10n.historySmartModeUndo,
      variant: WpButtonVariant.secondary,
      disabledTooltip: busy ? l10n.smartModeBusy : null,
      onPressed: busy
          ? null
          : () =>
                undone ? notifier.restoreSmartMode() : notifier.undoSmartMode(),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: busy
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                button,
                // Visible for keyboard users, who get no hover tooltip (BIZ-48).
                // A live region announces the switch to busy (review).
                Semantics(
                  liveRegion: true,
                  identifier: 'history-entry-smart-busy',
                  child: KeyedSubtree(
                    key: const ValueKey<String>('history-entry-smart-busy'),
                    child: Text(
                      l10n.smartModeBusy,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            )
          : button,
    );
  }
}

/// The name-change toast after a selection edit (2c, DEV-165). Non-blocking;
/// it shows only the count, never the names.
void showSmartModeNameChangeToast({
  required BuildContext context,
  required WidgetRef ref,
  required SmartModeNameChangeNotice notice,
}) {
  final l10n = L10n.of(context);
  // Dismissing the toast (timeout, close button, undo) drops the offer and
  // with it the original text (GS-048). The notifier is captured so a late
  // dismissal does not touch a ref that may be gone.
  final notifier = ref.read(smartModeNameChangeNoticeProvider.notifier);
  WpToast.show(
    context,
    message: l10n.smartModeNameChangeToast(notice.count),
    type: WpToastType.info,
    messageTestId: 'toast-smart-name-changes',
    duration: const Duration(seconds: 6),
    action: WpToastAction(
      label: l10n.smartModeUndoAction,
      testId: 'toast-smart-name-undo',
      onPressed: () =>
          unawaited(_undoSelectionEdit(context, ref, notice.ticket)),
    ),
    onDismissed: () => notifier.clearIfSerial(notice.serial),
  );
}

/// Reverts the selection edit: the keystroke when the conditions in
/// `undoSelectionEdit` hold, otherwise the original text goes to the clipboard
/// and the user is told to paste it.
Future<void> _undoSelectionEdit(
  BuildContext context,
  WidgetRef ref,
  SelectionUndoTicket ticket,
) async {
  ref.read(smartModeNameChangeNoticeProvider.notifier).clear();
  final paster = ref.read(pasterProvider);
  if (paster == null) {
    // Nothing to paste into: say so instead of doing nothing (UIA-HIS-26).
    if (context.mounted) {
      WpToast.show(
        context,
        message: L10n.of(context).selectionUndoUnavailable,
        type: WpToastType.info,
      );
    }
    return;
  }
  final outcome = await undoSelectionEdit(ticket: ticket, paster: paster);
  if (outcome == SelectionUndoOutcome.copiedToClipboard && context.mounted) {
    WpToast.show(
      context,
      message: L10n.of(
        context,
      ).selectionUndoCopiedToClipboard(_pasteShortcutLabel(context)),
      type: WpToastType.info,
      duration: const Duration(seconds: 6),
    );
  }
}

/// The paste shortcut as the user knows it on this platform.
String _pasteShortcutLabel(BuildContext context) => pasteShortcutLabelFor(
  platform: defaultTargetPlatform,
  languageCode: Localizations.localeOf(context).languageCode,
);

/// Pure form of [_pasteShortcutLabel] so each platform can be tested.
@visibleForTesting
String pasteShortcutLabelFor({
  required TargetPlatform platform,
  required String languageCode,
}) {
  if (platform == TargetPlatform.macOS) return '⌘V';
  return languageCode == 'de' ? 'Strg+V' : 'Ctrl+V';
}

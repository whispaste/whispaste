/// The preview of an AI edit on a selection (#589).
///
/// An edit never replaces the selection right away: its result waits here
/// until the user decides. Enter (or the first button) applies it, Esc (or
/// the close button) discards it and leaves the selection as it was, and
/// holding the edit hotkey again refines it with a further instruction. The
/// app shell turns each new preview into the overlay card; the orchestrator
/// keeps or drops the waiting proposal when a recording starts.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../paste/paster.dart';
import '../smart_mode/smart_mode_name_change_notice.dart';
import 'selection_edit_service.dart';

final _log = AppLogger('SelectionEditPreview');

/// Stable id of the preview card, for the overlay, logs and tests.
const kSelectionEditPreviewNoticeId = 'selection-edit-preview';

/// A proposal that waits for the user's decision.
@immutable
class SelectionEditPreview {
  const SelectionEditPreview({required this.proposal, required this.serial});

  final SelectionEditProposal proposal;

  /// Makes two previews distinct for listeners, also for the same text.
  final int serial;
}

/// The paste settings of an edit, shared by the direct run and the preview.
PasteOptions selectionEditPasteOptions(AppSettings settings) => PasteOptions(
  autoPasteDelayMs: settings.autoPasteDelay,
  blocklist: settings.autoPasteBlocklist,
  // With saving off a blocked paste must still leave the text on the
  // clipboard: there is no history entry to fall back on.
  copyBlockedToClipboard:
      settings.behavior.copyBlockedToClipboard || !settings.history.saveHistory,
  restoreClipboardAfterPaste: settings.behavior.restoreClipboardAfterPaste,
  restoreClipboardWithoutReceipt:
      settings.behavior.restoreClipboardWithoutReceipt,
);

class SelectionEditPreviewNotifier extends Notifier<SelectionEditPreview?> {
  @override
  SelectionEditPreview? build() => null;

  /// The proposal a refining instruction builds on, null when none waits.
  SelectionEditProposal? get pending => state?.proposal;

  /// Shows [proposal] for a decision; replaces a proposal that waited, which
  /// is how a refinement takes the place of the text it refined.
  void offer(SelectionEditProposal proposal) {
    state = SelectionEditPreview(
      proposal: proposal,
      serial: (state?.serial ?? 0) + 1,
    );
  }

  /// Drops the waiting proposal. The selection in the target app was never
  /// touched, so nothing else has to happen.
  void discard() {
    if (state == null) return;
    _log.info('Selection edit preview discarded');
    state = null;
  }

  /// Replaces the selection with the waiting proposal. Returns null when
  /// none waited (already decided), otherwise the paste outcome; a name
  /// change still offers its undo as after a direct edit (DEV-165).
  Future<SelectionEditOutcome?> apply() async {
    final preview = state;
    if (preview == null) return null;
    state = null;
    final service = ref.read(selectionEditServiceProvider);
    if (service == null) {
      return const SelectionEditOutcome.failed(
        SelectionEditFailure.pasteFailed,
      );
    }
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final outcome = await service.apply(
      preview.proposal,
      pasteOptions: selectionEditPasteOptions(settings),
    );
    _log.info(
      'Selection edit preview applied '
      '(failure=${outcome.failure?.name ?? "none"})',
    );
    final undo = outcome.undo;
    if (undo != null && outcome.nameChanges.isNotEmpty) {
      ref
          .read(smartModeNameChangeNoticeProvider.notifier)
          .announce(count: outcome.nameChanges.length, ticket: undo);
    }
    return outcome;
  }
}

final selectionEditPreviewProvider =
    NotifierProvider<SelectionEditPreviewNotifier, SelectionEditPreview?>(
      SelectionEditPreviewNotifier.new,
    );

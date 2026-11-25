/// Shared write-preview presentation for overlay and main-window fallback.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/recording_behavior.dart';
import '../../floating_overlay/dictation_notice.dart';
import '../../floating_overlay/overlay_notice.dart' show OverlayNoticeNote;
import 'smart_write_preview.dart';

/// The preview card for [next]. With [localModel] the draft came from the
/// local model, and the card carries its quality hint (ADR 0015 D6, #251).
/// The link to the OpenAI key lives in Settings: the card's two buttons are
/// insert and discard. Quiet lines under the draft name the snippet it is
/// based on (#252), or that an instruction named a snippet that was not
/// used, then the local model's quality hint, then how to refine the draft
/// by voice or, after [kSmartWriteMaxRefineRounds] rounds, to insert or
/// discard it (#250).
///
/// With [editor] the draft is editable (D13, #254): a toggle opens a field
/// in which Enter inserts the edited text, Shift+Enter breaks the line and
/// Esc discards (D21). Only where the platform can hand the focus back
/// ([SmartWriteEnvironment.canEditPreview]); without it the card is as
/// before.
DictationNotice smartWriteDraftNotice(
  L10n l10n,
  SmartWriteDraft next, {
  required VoidCallback onInsert,
  required VoidCallback onDiscard,
  bool localModel = false,
  SmartWritePreviewNotifier? editor,
}) => DictationNotice(
  id: next.targetChanged
      ? 'smart-write-error-target-changed'
      : next.wayland
      ? 'smart-write-target-unverifiable-hint'
      : kSmartWritePreviewNoticeId,
  cause: next.errorCode != null
      ? localizeRecordingError(l10n, next.errorCode!)
      : next.targetChanged
      ? localizeRecordingError(l10n, 'smart_write_target_changed')
      : l10n.smartWritePreviewTitle,
  nextStep: next.targetChanged
      ? l10n.smartWriteConfirmCurrentTarget
      : '${next.focusNotReturned ? '${l10n.smartWriteFocusNotReturned}\n' : ''}'
            '${next.wayland ? '${l10n.smartWriteWaylandHint}\n' : ''}'
            '${l10n.smartWritePreviewInsertHint} · '
            '${l10n.smartWritePreviewDiscardHint}',
  detail: next.text,
  notes: [
    // What the draft is based on (#252); a revision keeps it.
    if (!next.targetChanged && next.snippetTitle != null)
      OverlayNoticeNote(
        id: kSmartWriteSnippetLineId,
        text: l10n.smartWriteSnippetUsed(next.snippetTitle!),
      )
    else if (!next.targetChanged && next.snippetMissed)
      OverlayNoticeNote(
        id: kSmartWriteSnippetLineId,
        text: l10n.smartWriteSnippetNone,
      ),
    if (localModel && !next.targetChanged && next.errorCode == null)
      OverlayNoticeNote(
        id: 'smart-write-local-quality-hint',
        text: l10n.smartWriteLocalQualityHint,
      ),
    // How to refine by voice, or that the rounds are used up (#250).
    if (!next.targetChanged)
      next.refineLimitReached
          ? OverlayNoticeNote(
              id: kSmartWriteRefineLimitHintId,
              text: l10n.smartWriteRefineLimitHint,
            )
          : OverlayNoticeNote(
              id: kSmartWriteRefineHintId,
              text: l10n.smartWritePreviewRefineHint,
            ),
  ],
  // Not while a target change waits for its confirmation: that card asks
  // about the app, not the text.
  edit: editor == null || next.targetChanged
      ? null
      : DictationNoticeEdit(
          key: next.serial,
          text: next.text,
          open: next.editorOpen,
          toggleLabel: l10n.smartWriteEditToggle,
          fieldLabel: l10n.smartWriteEditFieldLabel,
          insertHint: l10n.smartWriteEditInsertHint,
          onOpen: editor.openEditor,
          onChanged: editor.updateText,
          onFocus: editor.setEditingFocus,
          onSubmit: (text) => unawaited(editor.submitEdited(text)),
          onCancel: onDiscard,
        ),
  managesOwnKeys: true,
  offersNewDictation: false,
  firstActionOnEnter: true,
  onDismiss: onDiscard,
  actions: [
    DictationNoticeAction(
      id: 'insert',
      label: l10n.smartWriteInsert,
      onPressed: onInsert,
    ),
    DictationNoticeAction(
      id: 'discard',
      label: l10n.smartWriteDiscard,
      onPressed: onDiscard,
    ),
  ],
);

/// Voice note button — records a short voice clip in the history detail panel,
/// transcribes it, and dispatches the result as a note, tag, or correction.
///
/// The recording pipeline itself lives in [WpVoiceInputButton] (shared with
/// the note editor); everything here is the history-specific *sink* for the
/// finished transcript.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/replacements/correction_learning_service.dart';
import '../../../services/replacements/correction_signal.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/voice_action_service.dart';
import '../../../widgets/wp_notice_bar.dart';
import '../../../widgets/wp_voice_input_button.dart';
import '../data/history_detail_provider.dart';
import 'history_write_failure.dart';
import '../../../widgets/wp_page_notice.dart';
import '../../../widgets/wp_banner.dart';

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Mic button that starts a mini voice-recording session in the detail panel.
///
/// On completion the transcription is parsed via [parseVoiceAction] and
/// dispatched to the entry's [HistoryDetailNotifier]:
/// - **note** → `addNote`
/// - **tag** → `addTag`
/// - **correction** → `updateContent`
class VoiceNoteButton extends ConsumerWidget {
  const VoiceNoteButton({super.key, required this.entryId});

  final String entryId;

  static final _log = AppLogger('VoiceNoteButton');

  Future<void> _dispatch(
    BuildContext context,
    WidgetRef ref,
    String transcript,
  ) async {
    final l10n = L10n.of(context);
    final action = parseVoiceAction(transcript);
    if (action == null) {
      showWpPageNotice(
        context,
        page: WpNoticePage.history,
        notice: WpPageNotice(
          id: 'voice-empty',
          message: l10n.voiceNoteEmpty,
          tone: WpBannerTone.warning,
          area: entryId,
        ),
      );
      return;
    }

    // All reads happen before the first await: the writes below outlive the
    // button when the panel closes mid-dispatch, and `ref` is only valid while
    // this element is mounted.
    final notifier = ref.read(historyDetailProvider(entryId).notifier);
    final telemetry = ref.read(telemetrySessionAggregatorProvider);
    // The content *before* this correction is applied -- this is the
    // "Ausgangstext" half of the correction signal; `updateContent` below
    // overwrites it, so it must be captured now.
    final contentBeforeCorrection = ref
        .read(historyDetailProvider(entryId))
        .value
        ?.entry
        .content;
    final correctionLearningEnabled =
        ref.read(
          settingsProvider.select(
            (s) => s.value?.behavior.correctionLearningEnabled,
          ),
        ) ??
        true;
    final correctionLearningService = ref.read(
      correctionLearningServiceProvider,
    );
    final db = ref.read(historyDatabaseProvider);

    switch (action.type) {
      case VoiceActionType.note:
        await notifier.addNote(action.payload);
      case VoiceActionType.tag:
        await notifier.addTag(action.payload);
      case VoiceActionType.correction:
        try {
          await notifier.updateContent(action.payload);
        } catch (e, st) {
          // An entry that is not loaded cannot take the correction; say so
          // instead of letting the button hang on an unhandled error.
          // Warnings are breadcrumbs only: an Error (e.g. the StateError for
          // an entry that is not loaded) must reach Sentry as an error.
          if (e is Error) {
            _log.error('Applying the voice correction failed', e, st);
          } else {
            _log.warning('Applying the voice correction failed', e, st);
          }
          if (context.mounted) {
            showHistoryWriteFailed(context, entryId: entryId);
          }
          return;
        }
        // The command replaces the *entire* entry content in one shot with
        // no confirmation step -- a misheard "korrektur:" prefix (or a
        // correction aimed at fixing one word further up that accidentally
        // clobbers an edit made elsewhere) silently destroys the rest of the
        // transcript. An inline undo is the cheapest guardrail that doesn't
        // require turning this into a two-step confirm dialog and slowing
        // down the common case.
        if (context.mounted) {
          _showDone(
            context,
            l10n.voiceCorrectionApplied,
            undo: contentBeforeCorrection == null
                ? null
                : () => _undoCorrection(
                    context,
                    notifier,
                    contentBeforeCorrection,
                  ),
          );
        }
        // Only a real change is a "correction" worth learning from -- a
        // `correct:`/`korrektur:` command dictated at all (even with the
        // same content, e.g. re-recorded to fix a different word further up
        // that a fresh full-content overwrite happens to match again) tells
        // us nothing about a repeated *mistake* if source == target.
        if (correctionLearningEnabled &&
            contentBeforeCorrection != null &&
            contentBeforeCorrection != action.payload) {
          try {
            await correctionLearningService.recordSignal(
              CorrectionSignal(
                sourceText: contentBeforeCorrection,
                targetText: action.payload,
                timestamp: DateTime.now(),
                source: CorrectionSignalSource.voiceCommand,
              ),
              db,
            );
          } catch (e, st) {
            // The correction itself is applied; failing to learn from it
            // must not turn the voice action into an error.
            if (e is Error) {
              _log.error('Recording correction signal failed', e, st);
            } else {
              _log.warning('Recording correction signal failed', e, st);
            }
          }
        }
    }

    _log.info(
      'Voice action dispatched: ${action.type.name} → "${action.payload}"',
    );
    telemetry.count(category: 'voice_note', action: 'create');
  }

  /// Puts the pre-correction text back; a failing write is reported like any
  /// other history write, never thrown out of the undo button.
  Future<bool> _undoCorrection(
    BuildContext context,
    HistoryDetailNotifier notifier,
    String previous,
  ) async {
    try {
      await notifier.updateContent(previous);
      return true;
    } catch (e, st) {
      if (e is Error) {
        _log.error('Undoing the voice correction failed', e, st);
      } else {
        _log.warning('Undoing the voice correction failed', e, st);
      }
      if (context.mounted) showHistoryWriteFailed(context, entryId: entryId);
      return false;
    }
  }

  /// The confirmation of a correction. With a way back it is an undo in the
  /// notice bar, which stays long enough to notice a wrong correction
  /// (UIA-HIS-16); a plain confirmation belongs to the entry and closes
  /// itself there.
  void _showDone(
    BuildContext context,
    String message, {
    Future<bool> Function()? undo,
  }) {
    final l10n = L10n.of(context);
    if (undo == null) {
      showWpConfirmation(context, id: 'voice-done', message: message);
      return;
    }
    showWpNotice(
      context,
      WpNotice(
        id: 'voice-correction',
        kind: WpNoticeKind.undo,
        message: message,
        actionLabel: l10n.undo,
        onAction: () async {
          final undone = await undo();
          if (undone && context.mounted) {
            _showDone(context, l10n.voiceCorrectionUndone);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WpVoiceInputButton(
      idleTooltip: L10n.of(context).historyVoiceNoteButtonTooltip,
      onTranscript: (transcript) => _dispatch(context, ref, transcript),
      onError: (message) => showWpPageNotice(
        context,
        page: WpNoticePage.history,
        notice: WpPageNotice(
          id: 'voice-failed',
          message: message,
          area: entryId,
        ),
      ),
    );
  }
}

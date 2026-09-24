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
import '../../../widgets/toast.dart';
import '../../../widgets/wp_voice_input_button.dart';
import '../data/history_detail_provider.dart';

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
      _showToast(context, l10n.voiceNoteEmpty, isError: true);
      return;
    }

    // All reads happen before the first await: the writes below outlive the
    // button when the panel closes mid-dispatch, and `ref` is only valid while
    // this element is mounted.
    final notifier = ref.read(historyDetailProvider(entryId).notifier);
    final telemetry = ref.read(telemetrySessionAggregatorProvider);
    // The content *before* this correction is applied -- this is the
    // "Ausgangstext" half of the correction signal (ticket 01
    // `.scratch/vocab-learning-corrections/`); `updateContent` below
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
        if (context.mounted) _showToast(context, l10n.voiceNoteAdded);
      case VoiceActionType.tag:
        await notifier.addTag(action.payload);
        if (context.mounted) {
          _showToast(context, l10n.voiceTagAdded(action.payload));
        }
      case VoiceActionType.correction:
        await notifier.updateContent(action.payload);
        // The command replaces the *entire* entry content in one shot with
        // no confirmation step -- a misheard "korrektur:" prefix (or a
        // correction aimed at fixing one word further up that accidentally
        // clobbers an edit made elsewhere) silently destroys the rest of the
        // transcript. An inline undo is the cheapest guardrail that doesn't
        // require turning this into a two-step confirm dialog and slowing
        // down the common case.
        if (context.mounted) {
          _showToast(
            context,
            l10n.voiceCorrectionApplied,
            undo: contentBeforeCorrection == null
                ? null
                : () => notifier.updateContent(contentBeforeCorrection),
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
          await correctionLearningService.recordSignal(
            CorrectionSignal(
              sourceText: contentBeforeCorrection,
              targetText: action.payload,
              timestamp: DateTime.now(),
              source: CorrectionSignalSource.voiceCommand,
            ),
            db,
          );
        }
    }

    _log.info(
      'Voice action dispatched: ${action.type.name} → "${action.payload}"',
    );
    telemetry.count(category: 'voice_note', action: 'create');
  }

  void _showToast(
    BuildContext context,
    String message, {
    bool isError = false,
    VoidCallback? undo,
  }) {
    final l10n = L10n.of(context);
    WpToast.show(
      context,
      message: message,
      type: isError ? WpToastType.error : WpToastType.success,
      duration: const Duration(seconds: 2),
      action: undo == null
          ? null
          : WpToastAction(
              label: l10n.undo,
              onPressed: () {
                undo();
                if (context.mounted) {
                  _showToast(context, l10n.voiceCorrectionUndone);
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
    );
  }
}

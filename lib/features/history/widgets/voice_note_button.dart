/// Voice note button — records a short voice clip in the history detail panel,
/// transcribes it, and dispatches the result as a note, tag, or correction.
///
/// The recording pipeline itself lives in [WpVoiceInputButton] (shared with
/// the note editor); everything here is the history-specific *sink* for the
/// finished transcript.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
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
  const VoiceNoteButton({
    super.key,
    required this.entryId,
    required this.isDark,
  });

  final String entryId;
  final bool isDark;

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

    // Both reads happen before the first await: the writes below outlive the
    // button when the panel closes mid-dispatch, and `ref` is only valid while
    // this element is mounted.
    final notifier = ref.read(historyDetailProvider(entryId).notifier);
    final telemetry = ref.read(telemetrySessionAggregatorProvider);

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
        if (context.mounted) _showToast(context, l10n.voiceCorrectionApplied);
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
  }) {
    WpToast.show(
      context,
      message: message,
      type: isError ? WpToastType.error : WpToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WpVoiceInputButton(
      isDark: isDark,
      onTranscript: (transcript) => _dispatch(context, ref, transcript),
    );
  }
}

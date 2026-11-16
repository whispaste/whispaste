/// Shared correction-signal type for vocabulary-learning-from-corrections.
///
/// A [CorrectionSignal] is source-agnostic on purpose: voice corrections
/// (`VoiceActionType.correction`, see `voice_action_service.dart`) and manual
/// transcript edits on history entries (ticket 02, `history_detail_panel.dart`
/// `_saveTranscript`) both feed it through the same
/// [CorrectionSignal]/candidate-detection logic in
/// `correction_candidate_detector.dart`, distinguished only by
/// [CorrectionSignalSource].
library;

/// Where a [CorrectionSignal] came from.
enum CorrectionSignalSource {
  /// A spoken `correct:`/`korrektur:` voice command (`VoiceActionType.correction`,
  /// dispatched via `VoiceNoteButton`).
  voiceCommand,

  /// A manual text edit saved on a history entry in the History Detail view
  /// (`history_detail_panel.dart` `_saveTranscript`, ticket 02).
  manualEdit,

  /// An edit the user made in the target app right after a paste, read back
  /// from the focused field via accessibility (issue #384,
  /// `target_field_learning.dart`). Only the pasted section is read.
  targetAppEdit,

  /// The user selected the corrected words in another app and pressed the
  /// "Learn correction" hotkey (#934, `selection_correction_match.dart`).
  /// A deliberate act, so one press is enough for a suggestion.
  selectionHotkey,
}

/// One observed instance of a user correcting a piece of transcribed text —
/// the raw input to correction-candidate detection.
class CorrectionSignal {
  const CorrectionSignal({
    required this.sourceText,
    required this.targetText,
    required this.timestamp,
    required this.source,
    this.contextBefore = '',
  });

  /// The text as it was before the correction (what the user was
  /// unhappy with).
  final String sourceText;

  /// The text the user corrected it to.
  final String targetText;

  final DateTime timestamp;
  final CorrectionSignalSource source;

  /// A few words in front of the change, with their punctuation, as the
  /// target field had them (target-app edits only, empty otherwise). Tells a
  /// capital at a sentence start from a name mid-sentence. Kept in memory
  /// only, never logged or stored.
  final String contextBefore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CorrectionSignal &&
          runtimeType == other.runtimeType &&
          sourceText == other.sourceText &&
          targetText == other.targetText &&
          timestamp == other.timestamp &&
          source == other.source &&
          contextBefore == other.contextBefore;

  @override
  int get hashCode =>
      Object.hash(sourceText, targetText, timestamp, source, contextBefore);

  @override
  String toString() =>
      'CorrectionSignal("$sourceText" -> "$targetText", $source, $timestamp)';
}

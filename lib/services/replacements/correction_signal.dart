/// Shared correction-signal type for vocabulary-learning-from-corrections
/// (ticket 01 `.scratch/vocab-learning-corrections/`).
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
}

/// One observed instance of a user correcting a piece of transcribed text —
/// the raw input to correction-candidate detection.
class CorrectionSignal {
  const CorrectionSignal({
    required this.sourceText,
    required this.targetText,
    required this.timestamp,
    required this.source,
  });

  /// The text as it was before the correction (what the user was
  /// unhappy with).
  final String sourceText;

  /// The text the user corrected it to.
  final String targetText;

  final DateTime timestamp;
  final CorrectionSignalSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CorrectionSignal &&
          runtimeType == other.runtimeType &&
          sourceText == other.sourceText &&
          targetText == other.targetText &&
          timestamp == other.timestamp &&
          source == other.source;

  @override
  int get hashCode => Object.hash(sourceText, targetText, timestamp, source);

  @override
  String toString() =>
      'CorrectionSignal("$sourceText" -> "$targetText", $source, $timestamp)';
}

/// Normalizes correction text for case-insensitive, whitespace-tolerant
/// grouping: trims, lowercases, and collapses any run of whitespace to a
/// single space. Used to decide whether two observed corrections are "the
/// same correction" (PRD: "normalisiert, case-insensitive").
String normalizeCorrectionText(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

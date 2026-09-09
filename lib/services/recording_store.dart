/// Seam for the post-transcription write path.
///
/// Encapsulates the four DB operations [RecordingOrchestrator] performs after
/// a successful transcription: apply text replacements, save history entry,
/// record daily stat, trim to max entries.
library;

export 'drift_recording_store.dart';

/// Input to [RecordingStore.save].
class RecordingInput {
  const RecordingInput({
    required this.transcript,
    required this.audioDuration,
    required this.modelId,
    required this.isLocal,
    required this.languageCode,
    required this.applyTextReplacements,
    required this.historyMaxEntries,
    required this.wordCount,
    required this.processingDurationSec,
    this.insertHistoryEntry = true,
    this.recordDailyStat = true,
    this.originalTranscript,
    this.targetApp,
  });

  final String transcript;
  final Duration audioDuration;
  final String modelId;
  final bool isLocal;
  final String languageCode;
  final bool applyTextReplacements;

  /// Transcript before live Smart-Mode refinement was applied (ticket 12) —
  /// `null` when Smart Mode was off/unavailable for this recording, or for
  /// callers (quick note, interactive snippet) that never captured it.
  /// Persisted as-is; the detail panel decides whether it differs from the
  /// final [transcript]/[processedTranscript] before showing it.
  final String? originalTranscript;

  /// Bundle ID / process identifier of the app this dictation is about to
  /// be pasted into (ticket 12) — `null` when no target was captured or the
  /// lookup is unsupported (Linux, quick note, interactive snippet).
  final String? targetApp;

  /// False for a quick-note dictation: text replacements still apply (below)
  /// but no row is written to `history_entries` — a quick note lives only in
  /// Notes, never duplicated into Verlauf.
  final bool insertHistoryEntry;

  /// False for an interactive snippet's final composed entry
  /// (`RecordingOrchestrator.completeInteractiveSnippet`): each of its
  /// fields already recorded its own daily stat (word count, audio/
  /// processing duration) via its own `templateField` save — recording the
  /// combined totals again here would double-count them.
  final bool recordDailyStat;

  /// 0 = unlimited.
  final int historyMaxEntries;
  final int wordCount;
  final int processingDurationSec;
}

/// Result of [RecordingStore.save].
class SavedRecording {
  const SavedRecording({
    required this.entryId,
    required this.processedTranscript,
    required this.trimmedCount,
  });

  final String entryId;

  /// Transcript after text replacements were applied.
  final String processedTranscript;

  /// Number of old entries soft-deleted to stay within
  /// [RecordingInput.historyMaxEntries].
  final int trimmedCount;
}

/// Saves a completed transcription to the history database.
abstract class RecordingStore {
  Future<SavedRecording> save(RecordingInput input);
}

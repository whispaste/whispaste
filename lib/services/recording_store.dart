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
    this.numericOnlyMode = false,
  });

  final String transcript;
  final Duration audioDuration;
  final String modelId;
  final bool isLocal;
  final String languageCode;
  final bool applyTextReplacements;

  /// Whether the transcript is reduced to digits-only (`toNumericOnly`)
  /// after replacements are applied — must run after replacements (which
  /// match on number *words*) but before the row is persisted, since the
  /// history entry must store the already-transformed text (Zahlen-Modus
  /// PRD §6.2 Option D1). That ordering constraint is why the transform
  /// happens inside [RecordingStore.save] rather than by the caller.
  final bool numericOnlyMode;

  /// False for a quick-note dictation: text replacements still apply (below)
  /// but no row is written to `history_entries` — a quick note lives only in
  /// Notes, never duplicated into Verlauf.
  final bool insertHistoryEntry;

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

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
  });

  final String transcript;
  final Duration audioDuration;
  final String modelId;
  final bool isLocal;
  final String languageCode;
  final bool applyTextReplacements;

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

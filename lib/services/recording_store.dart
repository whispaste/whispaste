/// Seam for the post-transcription write path.
///
/// Encapsulates the four DB operations [RecordingOrchestrator] performs after
/// a successful transcription: apply text replacements, save history entry,
/// record daily stat, trim to max entries.
library;

import 'dart:math' as math;

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
    this.entryId,
    this.createdAt,
    this.smartModeInput,
    this.smartModeApplied = false,
    this.detectedLanguage,
  });

  final String transcript;
  final Duration audioDuration;
  final String modelId;
  final bool isLocal;
  final String languageCode;

  /// Language the engine detected, when [languageCode] was `auto` (DEV-132).
  /// Stored in the entry's `languageHint` column for retroactive runs.
  final String? detectedLanguage;
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

  /// Input of the Smart-Mode run that produced [transcript] (v27 undo). `null`
  /// when it equals [originalTranscript] (BIZ-25) or no run changed the text.
  final String? smartModeInput;

  /// Whether a Smart-Mode run changed [transcript] (v27 undo marker).
  final bool smartModeApplied;

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

  /// Fixed history entry ID. Set when the caller may save this recording
  /// again later (see `PendingAudioQueue`), so a retry can detect an entry
  /// that already exists. `null` lets the store generate one.
  final String? entryId;

  /// Capture time of the dictation. Set together with [entryId] for a
  /// deferred save; `null` means "now".
  final DateTime? createdAt;

  /// The same save without a history row (see [insertHistoryEntry]): used
  /// while "Aufnahmen speichern" is off. Everything else stays as it is.
  RecordingInput withoutHistoryEntry() => RecordingInput(
    transcript: transcript,
    audioDuration: audioDuration,
    modelId: modelId,
    isLocal: isLocal,
    languageCode: languageCode,
    applyTextReplacements: applyTextReplacements,
    historyMaxEntries: historyMaxEntries,
    wordCount: wordCount,
    processingDurationSec: processingDurationSec,
    insertHistoryEntry: false,
    recordDailyStat: recordDailyStat,
    originalTranscript: originalTranscript,
    targetApp: targetApp,
    entryId: entryId,
    createdAt: createdAt,
    smartModeInput: smartModeInput,
    smartModeApplied: smartModeApplied,
    detectedLanguage: detectedLanguage,
  );
}

/// Generates a history entry ID: `<epoch-ms>-<4 random digits>`.
String newRecordingEntryId(DateTime now) =>
    '${now.millisecondsSinceEpoch}-'
    '${math.Random().nextInt(9999).toString().padLeft(4, '0')}';

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
  /// Applies the dictionary replacements to [text] and counts their usage.
  /// Non-fatal: returns [text] unchanged if the replacements cannot be read.
  Future<String> applyReplacements(String text);

  /// Dictionary targets (the correct spellings), used as protected names by
  /// the Smart-Mode fact guard. Non-fatal: empty when they cannot be read.
  Future<List<String>> dictionaryTerms();

  Future<SavedRecording> save(RecordingInput input);
}

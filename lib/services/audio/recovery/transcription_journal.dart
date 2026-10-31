/// Journal entry that covers one transcription: from the moment its WAV is
/// handed to the engine until the audio is saved, parked or deleted. A crash
/// in between leaves the entry behind, so the startup recovery transcribes the
/// WAV once. The entry id lets it skip a recording that was saved before the
/// entry was removed.
library;

import '../../../core/logging/app_logger.dart';
import 'recording_journal.dart';

final _log = AppLogger('TranscriptionJournal');

/// The journal id of the transcription of history entry [entryId].
String transcriptionJournalId(String entryId) => 'tx-$entryId';

class TranscriptionJournal {
  TranscriptionJournal(this.journal);

  final RecordingJournal journal;

  /// Writes the entry before the engine starts. Returns its journal id, or
  /// null when the write failed; the transcription then runs unprotected, as
  /// it did before this entry existed.
  Future<String?> begin({
    required String wavPath,
    required String entryId,
    required DateTime now,
  }) async {
    final id = transcriptionJournalId(entryId);
    try {
      await journal.begin(
        id: id,
        startedAt: now,
        wavPath: wavPath,
        entryId: entryId,
      );
      return id;
    } on Object catch (e) {
      _log.warning('Transcription journal not written: $e');
      return null;
    }
  }

  /// Removes the entry once the audio has been saved, parked or deleted.
  Future<void> end(String? id) async {
    if (id == null) return;
    try {
      await journal.end(id);
    } on Object catch (e) {
      _log.warning('Transcription journal not removed: $e');
    }
  }
}

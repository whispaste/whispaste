/// Save of a dictation that comes back from parked audio, either recovered on
/// start or retried by hand.
library;

import '../recording_store.dart';

/// Saves [input] like a normal dictation while [historyOn]. With "Aufnahmen
/// speichern" off no history entry is written, and the text is copied instead,
/// so a recovered recording never lands in Recordings.
Future<SavedRecording> saveParkedDictation(
  RecordingInput input, {
  required bool historyOn,
  required Future<SavedRecording> Function(RecordingInput input) save,
  required Future<void> Function(String text) copyText,
}) async {
  if (historyOn) return save(input);
  final saved = await save(input.withoutHistoryEntry());
  await copyText(saved.processedTranscript);
  return saved;
}

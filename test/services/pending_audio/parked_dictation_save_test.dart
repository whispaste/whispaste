/// Save of a recovered or retried dictation while "Aufnahmen speichern" is off
/// (history-off feature): no history entry is written, the text is copied.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/pending_audio/parked_dictation_save.dart';
import 'package:whispaste/services/recording_store.dart';

RecordingInput _input(String text) => RecordingInput(
  transcript: text,
  audioDuration: const Duration(seconds: 2),
  modelId: 'whisper-small',
  isLocal: true,
  languageCode: 'de',
  applyTextReplacements: false,
  historyMaxEntries: 1000,
  wordCount: 1,
  processingDurationSec: 0,
  entryId: 'parked-1',
  createdAt: DateTime(2026, 10, 29),
);

void main() {
  test('with history on the parked dictation is saved as an entry and '
      'nothing is copied', () async {
    RecordingInput? saved;
    String? copied;

    await saveParkedDictation(
      _input('Wiederhergestellt'),
      historyOn: true,
      save: (input) async {
        saved = input;
        return SavedRecording(
          entryId: input.entryId!,
          processedTranscript: input.transcript,
          trimmedCount: 0,
        );
      },
      copyText: (text) async => copied = text,
    );

    expect(saved?.insertHistoryEntry, isTrue);
    expect(copied, isNull);
  });

  test('with history off nothing is written as an entry, and the text is '
      'copied instead', () async {
    RecordingInput? saved;
    String? copied;

    final result = await saveParkedDictation(
      _input('Wiederhergestellt'),
      historyOn: false,
      save: (input) async {
        saved = input;
        return SavedRecording(
          entryId: input.entryId!,
          processedTranscript: input.transcript,
          trimmedCount: 0,
        );
      },
      copyText: (text) async => copied = text,
    );

    expect(saved?.insertHistoryEntry, isFalse);
    expect(copied, 'Wiederhergestellt');
    expect(result.processedTranscript, 'Wiederhergestellt');
  });
}

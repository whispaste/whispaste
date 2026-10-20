/// Re-runs speech-to-text on the retained audio of a history entry and replaces
/// the entry's text with the new transcript.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../../core/data/database.dart';
import '../text_transforms.dart';
import '../transcription/transcriber.dart';

enum RetranscribeOutcome {
  /// The entry's text was replaced with the new transcript.
  done,

  /// The entry has no retained audio, or the file is gone.
  noAudio,

  /// Transcription failed or produced no text. The entry is unchanged.
  failed,
}

Future<RetranscribeOutcome> retranscribeEntry({
  required HistoryDatabase db,
  required Transcriber transcriber,
  required String entryId,
}) async {
  final attachment = await db.latestAudioAttachment(entryId);
  if (attachment == null) return RetranscribeOutcome.noAudio;
  final file = File(attachment.filepath);
  if (!await file.exists()) return RetranscribeOutcome.noAudio;
  final bytes = await file.readAsBytes();

  try {
    await transcriber.prepare();
    final text = collapseTranscriptWhitespace(
      await transcriber.transcribe(bytes),
    );
    if (text.isEmpty) return RetranscribeOutcome.failed;
    await db.updateEntry(
      entryId,
      HistoryEntriesCompanion(content: Value(text)),
    );
    return RetranscribeOutcome.done;
  } on Exception {
    return RetranscribeOutcome.failed;
  } finally {
    transcriber.release();
  }
}

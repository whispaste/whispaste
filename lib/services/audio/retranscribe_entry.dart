/// Re-runs speech-to-text on the retained audio of a history entry. The new
/// transcript replaces the entry's text only when the caller applies it
/// ([applyRetranscript]), so the user can look at it first (#586).
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../text_transforms.dart';
import '../transcription/transcriber.dart';
import 'encryption/recording_vault.dart';

enum RetranscribeOutcome {
  /// The entry's text was replaced with the new transcript.
  done,

  /// The entry has no retained audio, or the file is gone.
  noAudio,

  /// Transcription failed or produced no text. The entry is unchanged.
  failed,
}

/// Whether [entryId] still has its audio on disk: the "Transcribe again"
/// action is offered only then.
final entryHasAudioProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  entryId,
) async {
  final attachment = await ref
      .read(historyDatabaseProvider)
      .latestAudioAttachment(entryId);
  return attachment != null && await File(attachment.filepath).exists();
});

/// Transcribes the retained audio of [entryId] again and returns the text
/// without touching the entry; [text] is set only for [RetranscribeOutcome.done].
/// The audio is read through [vault], so an encrypted recording (#1021) is
/// opened first; one that cannot be opened reports [RetranscribeOutcome.failed].
Future<({RetranscribeOutcome outcome, String? text})> transcribeEntryAudio({
  required HistoryDatabase db,
  required Transcriber transcriber,
  required RecordingVault vault,
  required String entryId,
}) async {
  final attachment = await db.latestAudioAttachment(entryId);
  if (attachment == null) {
    return (outcome: RetranscribeOutcome.noAudio, text: null);
  }
  final file = File(attachment.filepath);
  if (!await file.exists()) {
    return (outcome: RetranscribeOutcome.noAudio, text: null);
  }
  final List<int> bytes;
  try {
    bytes = await vault.read(file.path);
  } on Exception {
    return (outcome: RetranscribeOutcome.failed, text: null);
  }

  try {
    await transcriber.prepare();
    final text = collapseTranscriptWhitespace(
      await transcriber.transcribe(bytes),
    );
    if (text.isEmpty) return (outcome: RetranscribeOutcome.failed, text: null);
    return (outcome: RetranscribeOutcome.done, text: text);
  } on Exception {
    return (outcome: RetranscribeOutcome.failed, text: null);
  } finally {
    transcriber.release();
  }
}

/// Replaces the text of [entryId] with [text]. The text it had so far moves to
/// the "original" of the entry, so the replacement can be looked at again.
Future<void> applyRetranscript(
  HistoryDatabase db,
  String entryId,
  String text, {
  String? previousText,
}) => db.updateEntry(
  entryId,
  HistoryEntriesCompanion(
    content: Value(text),
    originalTranscript: previousText == null
        ? const Value.absent()
        : Value(previousText),
  ),
);

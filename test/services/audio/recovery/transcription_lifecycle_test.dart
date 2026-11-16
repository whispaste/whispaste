/// Life cycle of one transcription across a crash: the journal entry written
/// before the engine starts makes the startup recovery transcribe the WAV once,
/// and a recording already saved to history is never saved a second time.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/services/audio/recovery/transcription_journal.dart';

void main() {
  late Directory tmp;
  late Directory capture;
  late RecordingJournal journal;
  late TranscriptionJournal txJournal;
  final now = DateTime(2026, 10, 26, 10);
  const entryId = '1761472800000-0007';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp-tx-lifecycle-');
    capture = Directory(p.join(tmp.path, 'capture'))..createSync();
    journal = RecordingJournal(p.join(tmp.path, 'journal'));
    txJournal = TranscriptionJournal(journal);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String?> startTranscription() async {
    final wav = p.join(capture.path, 'whispaste_1.wav');
    File(wav).writeAsBytesSync(Uint8List(2000));
    return txJournal.begin(wavPath: wav, entryId: entryId, now: now);
  }

  /// One startup pass: recovers each interrupted recording with [saved] as the
  /// history entries that exist and counts the transcriptions it started.
  Future<({RecoveryOutcome? outcome, int transcriptions})> restart({
    required Set<String> saved,
  }) async {
    var transcriptions = 0;
    final recovery = RecordingRecovery(
      audioDir: p.join(tmp.path, 'retained'),
      captureDir: () async => capture.path,
      transcribe: (_) async {
        transcriptions++;
        return const RecoveryTranscription.ok();
      },
      entryExists: (id) async => saved.contains(id),
    );
    final scan = await journal.scan();
    RecoveryOutcome? outcome;
    for (final recording in scan.recordings) {
      outcome = await recovery.recover(recording);
    }
    return (outcome: outcome, transcriptions: transcriptions);
  }

  test('a crash during transcription is recovered once, without a second '
      'history entry', () async {
    await startTranscription();

    // Crash: the entry is never ended.
    final first = await restart(saved: {});
    expect(first.outcome, RecoveryOutcome.recovered);
    expect(first.transcriptions, 1);
    expect((await journal.scan()).recordings, isEmpty);

    // The next start finds nothing left to transcribe.
    final second = await restart(saved: {});
    expect(second.transcriptions, 0);
  });

  test('a crash after the save but before the end does not transcribe '
      'again', () async {
    await startTranscription();

    // The save reached history; the crash came before the entry was ended.
    final result = await restart(saved: {entryId});
    expect(result.outcome, RecoveryOutcome.recovered);
    expect(result.transcriptions, 0);
    expect((await journal.scan()).recordings, isEmpty);
    expect(File(p.join(capture.path, 'whispaste_1.wav')).existsSync(), isFalse);
  });

  test(
    'a transcription that ends normally leaves nothing to recover',
    () async {
      final id = await startTranscription();

      await txJournal.end(id);

      expect((await journal.scan()).recordings, isEmpty);
    },
  );
}

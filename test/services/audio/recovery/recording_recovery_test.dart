/// Behaviour of interrupted-recording recovery: recovered audio is removed
/// after a successful import, failed imports keep the audio for a retry, and
/// entries without audio only lose their journal file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';

void main() {
  late Directory tmp;
  late RecordingJournal journal;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp35-recovery-');
    journal = RecordingJournal('${tmp.path}/journal');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  /// Writes the journal entry and, if [audioBytes] is given, the WAV file.
  Future<InterruptedRecording> interrupted(String id, {int? audioBytes}) async {
    final wavPath = audioBytes == null ? null : '${tmp.path}/$id.wav';
    if (wavPath != null && audioBytes != null) {
      File(wavPath).writeAsBytesSync(Uint8List(audioBytes));
    }
    await journal.begin(
      id: id,
      startedAt: DateTime(2026, 10, 17),
      wavPath: wavPath,
    );
    final scan = await journal.scan();
    return scan.recordings.singleWhere((r) => r.id == id);
  }

  test('recovered audio and its journal entry are removed', () async {
    final recording = await interrupted('rec-1', audioBytes: 1000);
    final transcribed = <String>[];
    final recovery = RecordingRecovery(
      audioDir: tmp.path,
      transcribe: (path) async {
        transcribed.add(path);
        return true;
      },
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.recovered);
    expect(transcribed, [recording.wavPath]);
    expect(File(recording.wavPath!).existsSync(), isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test('failed import keeps the audio and the journal for a retry', () async {
    final recording = await interrupted('rec-2', audioBytes: 1000);
    final recovery = RecordingRecovery(
      audioDir: tmp.path,
      transcribe: (_) async => false,
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.failed);
    expect(File(recording.wavPath!).existsSync(), isTrue);
    expect(File(recording.journalPath).existsSync(), isTrue);
  });

  test('retention off: no audio path, journal removed, no import', () async {
    final recording = await interrupted('rec-3');
    var called = false;
    final recovery = RecordingRecovery(
      audioDir: tmp.path,
      transcribe: (_) async {
        called = true;
        return true;
      },
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.noAudio);
    expect(called, isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test('a WAV too short to hold audio counts as no audio', () async {
    final recording = await interrupted('rec-4', audioBytes: 44);
    var called = false;
    final recovery = RecordingRecovery(
      audioDir: tmp.path,
      transcribe: (_) async {
        called = true;
        return true;
      },
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.noAudio);
    expect(called, isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test('discard removes the audio and the journal without importing', () async {
    final recording = await interrupted('rec-5', audioBytes: 1000);
    var called = false;
    final recovery = RecordingRecovery(
      audioDir: tmp.path,
      transcribe: (_) async {
        called = true;
        return true;
      },
    );

    await recovery.discard(recording);

    expect(called, isFalse);
    expect(File(recording.wavPath!).existsSync(), isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });
}

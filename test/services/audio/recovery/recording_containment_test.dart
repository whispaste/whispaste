/// Containment of recovery paths (WP-43a I-M-3): a tampered journal must not
/// make discard delete, or recover import, a file outside the audio folder.
/// Symlinks inside the journal folder are never followed.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';

void main() {
  late Directory tmp;
  late Directory audioDir;
  late RecordingJournal journal;
  late Directory outside;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp43a-contain-');
    audioDir = Directory('${tmp.path}/retained')..createSync();
    outside = Directory('${tmp.path}/documents')..createSync();
    journal = RecordingJournal('${tmp.path}/journal');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  /// Writes a journal entry whose wavPath is [wavPath], as a tampered file would.
  Future<InterruptedRecording> journalPointingAt(
    String id,
    String? wavPath,
  ) async {
    await journal.begin(
      id: id,
      startedAt: DateTime(2026, 10, 17),
      wavPath: wavPath,
    );
    return (await journal.scan()).recordings.singleWhere((r) => r.id == id);
  }

  RecordingRecovery recoveryWith(
    List<String> transcribed, {
    bool result = true,
  }) => RecordingRecovery(
    audioDir: audioDir.path,
    transcribe: (path) async {
      transcribed.add(path);
      return result
          ? const RecoveryTranscription.ok()
          : const RecoveryTranscription.failed(errorCode: 'stt_server_failed');
    },
  );

  test('discard never deletes a WAV outside the audio folder', () async {
    final victim = File('${outside.path}/Besprechung.wav')
      ..writeAsBytesSync(Uint8List(1000));
    final recording = await journalPointingAt('rec-out-1', victim.path);

    await recoveryWith([]).discard(recording);

    expect(victim.existsSync(), isTrue);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test(
    'recover neither imports nor deletes a WAV outside the audio folder',
    () async {
      final victim = File('${outside.path}/Interview.wav')
        ..writeAsBytesSync(Uint8List(1000));
      final recording = await journalPointingAt('rec-out-2', victim.path);
      final transcribed = <String>[];

      final outcome = await recoveryWith(transcribed).recover(recording);

      expect(outcome, RecoveryOutcome.noAudio);
      expect(transcribed, isEmpty);
      expect(victim.existsSync(), isTrue);
    },
  );

  test(
    'a path with a non-WAV extension inside the folder is not touched',
    () async {
      final notAudio = File('${audioDir.path}/keys.txt')
        ..writeAsBytesSync(Uint8List(1000));
      final recording = await journalPointingAt('rec-ext', notAudio.path);

      await recoveryWith([]).discard(recording);

      expect(notAudio.existsSync(), isTrue);
    },
  );

  test(
    'a symlink inside the audio folder pointing outside is not deleted',
    () async {
      final victim = File('${outside.path}/Diktat.wav')
        ..writeAsBytesSync(Uint8List(1000));
      final link = Link('${audioDir.path}/whispaste_1.wav')
        ..createSync(victim.path);
      final recording = await journalPointingAt('rec-link', link.path);

      await recoveryWith([]).discard(recording);

      expect(victim.existsSync(), isTrue);
    },
  );

  test('a WAV inside the audio folder is still discarded normally', () async {
    final own = File('${audioDir.path}/whispaste_42.wav')
      ..writeAsBytesSync(Uint8List(1000));
    final recording = await journalPointingAt('rec-own', own.path);

    await recoveryWith([]).discard(recording);

    expect(own.existsSync(), isFalse);
  });

  test('scan ignores symlinked journal files', () async {
    final external = File('${outside.path}/fake.json')
      ..writeAsStringSync(
        '{"version":1,"id":"x","startedAt":"2026-01-01T00:00:00",'
        '"wavPath":null}',
      );
    Directory(journal.directory).createSync(recursive: true);
    Link('${journal.directory}/linked.json').createSync(external.path);

    final scan = await journal.scan();

    expect(scan.recordings, isEmpty);
  });
}

/// Behaviour of interrupted-recording recovery: recovered audio is removed,
/// a repeatable failure parks it for a retry, a permanent failure discards it,
/// and entries without audio only lose their journal file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';

class _Park {
  final calls = <({String wavPath, String errorCode, DateTime expiresAt})>[];
}

void main() {
  late Directory tmp;
  late RecordingJournal journal;
  // Relative to now: a fixed date would pass its 7-day retry window and make
  // every repeatable-failure case look expired.
  final startedAt = DateTime.now().subtract(const Duration(hours: 1));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp35-recovery-');
    journal = RecordingJournal('${tmp.path}/journal');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  /// Writes the journal entry and, if [audioBytes] is given, the WAV file in
  /// [folder] (the retained-audio folder by default).
  Future<InterruptedRecording> interrupted(
    String id, {
    int? audioBytes,
    String? folder,
  }) async {
    final dir = folder ?? tmp.path;
    final wavPath = audioBytes == null ? null : '$dir/$id.wav';
    if (wavPath != null && audioBytes != null) {
      File(wavPath).writeAsBytesSync(Uint8List(audioBytes));
    }
    await journal.begin(id: id, startedAt: startedAt, wavPath: wavPath);
    final scan = await journal.scan();
    return scan.recordings.singleWhere((r) => r.id == id);
  }

  RecordingRecovery recoveryWith({
    required Future<RecoveryTranscription> Function(String) transcribe,
    _Park? park,
    bool retainAudio = false,
    String? captureDir,
  }) => RecordingRecovery(
    audioDir: tmp.path,
    captureDir: captureDir == null ? null : () async => captureDir,
    transcribe: transcribe,
    retainAudio: () => retainAudio,
    park: park == null
        ? null
        : ({
            required wavPath,
            required errorCode,
            required capturedAt,
            required audioDuration,
            required expiresAt,
          }) async {
            park.calls.add((
              wavPath: wavPath,
              errorCode: errorCode,
              expiresAt: expiresAt,
            ));
          },
  );

  test('recovered audio and its journal entry are removed', () async {
    final recording = await interrupted('rec-1', audioBytes: 1000);
    final transcribed = <String>[];
    final recovery = recoveryWith(
      transcribe: (path) async {
        transcribed.add(path);
        return const RecoveryTranscription.ok();
      },
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.recovered);
    expect(transcribed, [recording.wavPath]);
    expect(File(recording.wavPath!).existsSync(), isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test(
    'a repeatable failure parks the audio for 7 days without retention',
    () async {
      final recording = await interrupted('rec-2', audioBytes: 1000);
      final park = _Park();
      final recovery = recoveryWith(
        transcribe: (_) async =>
            const RecoveryTranscription.failed(errorCode: 'stt_server_failed'),
        park: park,
      );

      final outcome = await recovery.recover(recording);

      expect(outcome, RecoveryOutcome.parked);
      expect(park.calls.single.wavPath, recording.wavPath);
      expect(park.calls.single.errorCode, 'stt_server_failed');
      expect(
        park.calls.single.expiresAt,
        startedAt.add(const Duration(days: 7)),
      );
      expect(File(recording.journalPath).existsSync(), isFalse);
    },
  );

  test('a repeatable failure with retention on keeps 30 days', () async {
    final recording = await interrupted('rec-2b', audioBytes: 1000);
    final park = _Park();
    final recovery = recoveryWith(
      transcribe: (_) async =>
          const RecoveryTranscription.failed(errorCode: 'cloud_timeout'),
      park: park,
      retainAudio: true,
    );

    await recovery.recover(recording);

    expect(
      park.calls.single.expiresAt,
      startedAt.add(const Duration(days: 30)),
    );
  });

  test('a permanent failure discards the audio and parks nothing', () async {
    final recording = await interrupted('rec-3', audioBytes: 1000);
    final park = _Park();
    final recovery = recoveryWith(
      transcribe: (_) async =>
          const RecoveryTranscription.failed(errorCode: 'cloud_auth_error'),
      park: park,
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.discarded);
    expect(park.calls, isEmpty);
    expect(File(recording.wavPath!).existsSync(), isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test('a failure without an error code is parked as save_failed', () async {
    final recording = await interrupted('rec-3b', audioBytes: 1000);
    final park = _Park();
    final recovery = recoveryWith(
      transcribe: (_) async => const RecoveryTranscription.failed(),
      park: park,
    );

    expect(await recovery.recover(recording), RecoveryOutcome.parked);
    expect(park.calls.single.errorCode, 'save_failed');
    expect(park.calls.single.expiresAt, startedAt.add(const Duration(days: 7)));
  });

  test('when keeping the audio fails, it and the journal stay', () async {
    final recording = await interrupted('rec-4', audioBytes: 1000);
    final recovery = RecordingRecovery(
      audioDir: tmp.path,
      transcribe: (_) async =>
          const RecoveryTranscription.failed(errorCode: 'stt_server_failed'),
      park:
          ({
            required wavPath,
            required errorCode,
            required capturedAt,
            required audioDuration,
            required expiresAt,
          }) async => throw const FileSystemException('disk full'),
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.failed);
    expect(File(recording.wavPath!).existsSync(), isTrue);
    expect(File(recording.journalPath).existsSync(), isTrue);
  });

  test('retention off: no audio path, journal removed, no import', () async {
    final recording = await interrupted('rec-5');
    var called = false;
    final recovery = recoveryWith(
      transcribe: (_) async {
        called = true;
        return const RecoveryTranscription.ok();
      },
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.noAudio);
    expect(called, isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test('a WAV too short to hold audio counts as no audio', () async {
    final recording = await interrupted('rec-6', audioBytes: 44);
    var called = false;
    final recovery = recoveryWith(
      transcribe: (_) async {
        called = true;
        return const RecoveryTranscription.ok();
      },
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.noAudio);
    expect(called, isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test('a recording already in history is not transcribed again', () async {
    final capture = Directory('${tmp.path}/capture')..createSync();
    await journal.begin(
      id: 'rec-10',
      startedAt: startedAt,
      wavPath: '${capture.path}/rec-10.wav',
      entryId: '1760000000000-0042',
    );
    File('${capture.path}/rec-10.wav').writeAsBytesSync(Uint8List(1000));
    final recording = (await journal.scan()).recordings.single;
    var called = false;
    final recovery = RecordingRecovery(
      audioDir: tmp.path,
      captureDir: () async => capture.path,
      transcribe: (_) async {
        called = true;
        return const RecoveryTranscription.ok();
      },
      entryExists: (id) async => id == '1760000000000-0042',
    );

    final outcome = await recovery.recover(recording);

    expect(outcome, RecoveryOutcome.recovered);
    expect(called, isFalse);
    expect(File(recording.wavPath!).existsSync(), isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test('a WAV in the capture folder is recovered', () async {
    final capture = Directory('${tmp.path}/capture')..createSync();
    final recording = await interrupted(
      'rec-7',
      audioBytes: 1000,
      folder: capture.path,
    );
    final transcribed = <String>[];
    final recovery = recoveryWith(
      captureDir: capture.path,
      transcribe: (path) async {
        transcribed.add(path);
        return const RecoveryTranscription.ok();
      },
    );

    expect(await recovery.recover(recording), RecoveryOutcome.recovered);
    expect(transcribed, [recording.wavPath]);
  });

  test('a WAV outside both audio folders is never touched', () async {
    final outside = Directory('${tmp.path}/elsewhere')..createSync();
    final recording = await interrupted(
      'rec-8',
      audioBytes: 1000,
      folder: outside.path,
    );
    var called = false;
    final recovery = recoveryWith(
      transcribe: (_) async {
        called = true;
        return const RecoveryTranscription.ok();
      },
    );

    expect(await recovery.recover(recording), RecoveryOutcome.noAudio);
    expect(called, isFalse);
    expect(File(recording.wavPath!).existsSync(), isTrue);
  });

  test('discard removes the audio and the journal without importing', () async {
    final recording = await interrupted('rec-9', audioBytes: 1000);
    var called = false;
    final recovery = recoveryWith(
      transcribe: (_) async {
        called = true;
        return const RecoveryTranscription.ok();
      },
    );

    await recovery.discard(recording);

    expect(called, isFalse);
    expect(File(recording.wavPath!).existsSync(), isFalse);
    expect(File(recording.journalPath).existsSync(), isFalse);
  });

  test(
    'a saved recording with retention on keeps its retained audio',
    () async {
      await journal.begin(
        id: 'rec-11',
        startedAt: startedAt,
        wavPath: '${tmp.path}/rec-11.wav',
        entryId: '1760000000000-0043',
      );
      File('${tmp.path}/rec-11.wav').writeAsBytesSync(Uint8List(1000));
      final recording = (await journal.scan()).recordings.single;
      final recovery = RecordingRecovery(
        audioDir: tmp.path,
        transcribe: (_) async => const RecoveryTranscription.ok(),
        entryExists: (_) async => true,
      );

      expect(await recovery.recover(recording), RecoveryOutcome.recovered);
      expect(File(recording.wavPath!).existsSync(), isTrue);
      expect(File(recording.journalPath).existsSync(), isFalse);
    },
  );

  test('discard removes the slice manifest with the audio', () async {
    final recording = await interrupted('rec-12', audioBytes: 1000);
    final manifest = File('${tmp.path}/rec-12.slices')
      ..writeAsStringSync('{"wavBytes":1000,"parts":["eins"]}');
    final recovery = recoveryWith(
      transcribe: (_) async => const RecoveryTranscription.ok(),
    );

    await recovery.discard(recording);

    expect(manifest.existsSync(), isFalse);
    expect(File(recording.wavPath!).existsSync(), isFalse);
  });

  test('a recovered recording takes its slice manifest along', () async {
    final recording = await interrupted('rec-13', audioBytes: 1000);
    final manifest = File('${tmp.path}/rec-13.slices')
      ..writeAsStringSync('{"wavBytes":1000,"parts":["eins"]}');
    final recovery = recoveryWith(
      transcribe: (_) async => const RecoveryTranscription.ok(),
    );

    expect(await recovery.recover(recording), RecoveryOutcome.recovered);
    expect(manifest.existsSync(), isFalse);
  });

  test('a permanent failure discards the slice manifest too', () async {
    final recording = await interrupted('rec-14', audioBytes: 1000);
    final manifest = File('${tmp.path}/rec-14.slices')
      ..writeAsStringSync('{"wavBytes":1000,"parts":["eins"]}');
    final recovery = recoveryWith(
      transcribe: (_) async =>
          const RecoveryTranscription.failed(errorCode: 'cloud_quota_exceeded'),
    );

    expect(await recovery.recover(recording), RecoveryOutcome.discarded);
    expect(manifest.existsSync(), isFalse);
  });
}

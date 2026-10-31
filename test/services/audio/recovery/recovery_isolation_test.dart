/// Startup recovery under failure and overlap: one failing recording never
/// stops the others, a journal owned by a live run is left alone, a repeatable
/// failure past its retry window discards the audio, and an exception from the
/// transcription keeps the audio for a retry.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_journal_provider.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';

void main() {
  late Directory tmp;
  late RecordingJournal journal;
  final startedAt = DateTime.now().subtract(const Duration(hours: 1));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp31-recovery-');
    journal = RecordingJournal('${tmp.path}/journal');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Writes an interrupted journal file (no live registration) and, when
  /// [audioBytes] is given, its WAV in the audio folder.
  InterruptedRecording interrupted(
    String id, {
    DateTime? at,
    int? audioBytes,
    String? entryId,
  }) {
    final wavPath = audioBytes == null ? null : '${tmp.path}/$id.wav';
    if (wavPath != null) {
      File(wavPath).writeAsBytesSync(Uint8List(audioBytes!));
    }
    final journalPath = '${journal.directory}/$id.json';
    File(journalPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': kRecordingJournalVersion,
          'id': id,
          'startedAt': (at ?? startedAt).toIso8601String(),
          'wavPath': wavPath,
          'entryId': entryId,
        }),
      );
    return InterruptedRecording(
      id: id,
      startedAt: at ?? startedAt,
      wavPath: wavPath,
      journalPath: journalPath,
      entryId: entryId,
    );
  }

  RecordingRecovery recoveryWith({
    required Future<RecoveryTranscription> Function(String) transcribe,
    List<String>? parkedCodes,
    Future<bool> Function(String entryId)? entryExists,
  }) => RecordingRecovery(
    audioDir: tmp.path,
    transcribe: transcribe,
    entryExists: entryExists,
    park:
        ({
          required wavPath,
          required errorCode,
          required capturedAt,
          required audioDuration,
          required expiresAt,
        }) async {
          parkedCodes?.add(errorCode);
        },
  );

  test(
    'an exception from the transcription keeps the audio as save_failed',
    () async {
      final recording = interrupted('exc-1', audioBytes: 1000);
      final parked = <String>[];
      final recovery = recoveryWith(
        transcribe: (_) async => throw StateError('engine crashed'),
        parkedCodes: parked,
      );

      expect(await recovery.recover(recording), RecoveryOutcome.parked);
      expect(parked, ['save_failed']);
      expect(File(recording.journalPath).existsSync(), isFalse);
    },
  );

  test(
    'a repeatable failure past its retry window discards the audio, parks nothing',
    () async {
      final old = DateTime.now().subtract(const Duration(days: 8));
      final recording = interrupted('old-1', at: old, audioBytes: 1000);
      final parked = <String>[];
      final recovery = recoveryWith(
        transcribe: (_) async =>
            const RecoveryTranscription.failed(errorCode: 'cloud_timeout'),
        parkedCodes: parked,
      );

      expect(await recovery.recover(recording), RecoveryOutcome.discarded);
      expect(parked, isEmpty);
      expect(File(recording.wavPath!).existsSync(), isFalse);
      expect(File(recording.journalPath).existsSync(), isFalse);
    },
  );

  test(
    'a WAV too short to hold audio is removed with its journal entry',
    () async {
      final recording = interrupted('tiny-1', audioBytes: 44);
      final recovery = recoveryWith(
        transcribe: (_) async => fail('no audio, nothing to transcribe'),
      );

      expect(await recovery.recover(recording), RecoveryOutcome.noAudio);
      expect(File(recording.wavPath!).existsSync(), isFalse);
      expect(File(recording.journalPath).existsSync(), isFalse);
    },
  );

  test('one failing recording does not stop the others', () async {
    // The first recording's history check throws; the second must still be
    // transcribed in the same startup run.
    final first = interrupted('a-first', audioBytes: 1000, entryId: 'e-1');
    final second = interrupted('b-second', audioBytes: 1000);
    final transcribed = <String>[];
    final recovery = recoveryWith(
      transcribe: (path) async {
        transcribed.add(path);
        return const RecoveryTranscription.ok();
      },
      entryExists: (_) async => throw const FileSystemException('locked'),
    );
    final container = ProviderContainer(
      overrides: [
        recordingJournalProvider.overrideWithValue(journal),
        recordingRecoveryProvider.overrideWithValue(recovery),
        interruptedRecordingsProvider.overrideWith(
          (ref) async => RecordingJournalScan(
            recordings: [first, second],
            skippedCorrupt: 0,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await recoverInterruptedRecordings(container);

    expect(transcribed, [second.wavPath]);
    expect(File(second.journalPath).existsSync(), isFalse);
  });

  test('a journal owned by a live run is not recovered', () async {
    await journal.begin(
      id: 'live-1',
      startedAt: startedAt,
      wavPath: '${tmp.path}/live-1.wav',
    );
    File('${tmp.path}/live-1.wav').writeAsBytesSync(Uint8List(1000));
    final live = (await journal.scan()).recordings.single;
    final transcribed = <String>[];
    final recovery = recoveryWith(
      transcribe: (path) async {
        transcribed.add(path);
        return const RecoveryTranscription.ok();
      },
    );
    final container = ProviderContainer(
      overrides: [
        recordingJournalProvider.overrideWithValue(journal),
        recordingRecoveryProvider.overrideWithValue(recovery),
        interruptedRecordingsProvider.overrideWith(
          (ref) async =>
              RecordingJournalScan(recordings: [live], skippedCorrupt: 0),
        ),
      ],
    );
    addTearDown(container.dispose);

    await recoverInterruptedRecordings(container);

    expect(transcribed, isEmpty);
    expect(File(live.journalPath).existsSync(), isTrue);
    expect(File(live.wavPath!).existsSync(), isTrue);

    await journal.end('live-1');
  });

  test('a journal that vanished after the scan is not recovered', () async {
    final gone = interrupted('gone-1', audioBytes: 1000);
    File(gone.journalPath).deleteSync();
    final transcribed = <String>[];
    final recovery = recoveryWith(
      transcribe: (path) async {
        transcribed.add(path);
        return const RecoveryTranscription.ok();
      },
    );
    final container = ProviderContainer(
      overrides: [
        recordingJournalProvider.overrideWithValue(journal),
        recordingRecoveryProvider.overrideWithValue(recovery),
        interruptedRecordingsProvider.overrideWith(
          (ref) async =>
              RecordingJournalScan(recordings: [gone], skippedCorrupt: 0),
        ),
      ],
    );
    addTearDown(container.dispose);

    await recoverInterruptedRecordings(container);

    expect(transcribed, isEmpty);
  });

  test(
    'a journal is live from begin until end, and not when begin fails',
    () async {
      await journal.begin(id: 'lv-1', startedAt: startedAt, wavPath: null);
      expect(journal.isLive('lv-1'), isTrue);

      await journal.end('lv-1');
      expect(journal.isLive('lv-1'), isFalse);

      // A directory that is a file cannot hold journals: begin fails and the
      // id must not stay registered as live.
      final blocker = File('${tmp.path}/blocker')..writeAsStringSync('x');
      final broken = RecordingJournal(blocker.path);
      await expectLater(
        broken.begin(id: 'lv-2', startedAt: startedAt, wavPath: null),
        throwsA(isA<FileSystemException>()),
      );
      expect(broken.isLive('lv-2'), isFalse);
    },
  );
}

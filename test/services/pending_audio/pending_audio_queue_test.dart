import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';
import 'package:whispaste/services/recording_store.dart';

const _transcript = 'Ein Diktat, das nicht gespeichert werden konnte';
final _capturedAt = DateTime(2026, 10, 18, 9, 30, 15);

void main() {
  late Directory tmp;
  late String pendingDir;
  late String captureDir;
  late HistoryDatabase db;
  late DriftRecordingStore store;
  late bool failSaves;
  late int saveCalls;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_pending_audio_test_');
    pendingDir = p.join(tmp.path, 'pending-audio');
    captureDir = p.join(tmp.path, 'capture');
    Directory(captureDir).createSync();
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    store = DriftRecordingStore(db);
    failSaves = false;
    saveCalls = 0;
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Queue wired like the app: the real store and the real history database.
  /// [failSaves] makes every save throw, to simulate a failing history write.
  PendingAudioQueue queue({
    int maxEntries = 20,
    int maxAttempts = 5,
    Future<void> Function(String entryId, String wavPath)? retain,
  }) => PendingAudioQueue(
    directory: () => pendingDir,
    save: (input) async {
      saveCalls++;
      if (failSaves) throw StateError('history write failed');
      return store.save(input);
    },
    entryExists: (id) async => (await db.getEntry(id)) != null,
    retainAudio: retain,
    maxEntries: maxEntries,
    maxAttempts: maxAttempts,
  );

  /// A dictation as the orchestrator builds it, with a fixed entry ID.
  RecordingInput input({String id = '1781775015000-0042'}) => RecordingInput(
    transcript: _transcript,
    audioDuration: const Duration(seconds: 7),
    modelId: 'parakeet-tdt',
    isLocal: true,
    languageCode: 'de',
    applyTextReplacements: false,
    historyMaxEntries: 0,
    wordCount: 7,
    processingDurationSec: 2,
    originalTranscript: 'roher Text',
    targetApp: 'com.example.editor',
    entryId: id,
    createdAt: _capturedAt,
  );

  /// Writes a WAV into the capture folder, as the recorder does, and returns
  /// its path.
  String captureWav(String name) {
    final path = p.join(captureDir, name);
    File(path).writeAsBytesSync(List.filled(64, 1));
    return path;
  }

  List<String> pendingFiles() => Directory(pendingDir).existsSync()
      ? (Directory(
          pendingDir,
        ).listSync().map((e) => p.basename(e.path)).toList()..sort())
      : const [];

  group('park', () {
    test('moves the audio out of the capture folder and records the '
        'dictation next to it', () async {
      final wav = captureWav('whispaste_1.wav');

      await queue().park(wav, input());

      expect(File(wav).existsSync(), isFalse);
      expect(pendingFiles(), [
        '1781775015000-0042.json',
        '1781775015000-0042.wav',
      ]);
    });

    test(
      'creates the pending folder with mode 0700 (user audio)',
      () async {
        await queue().park(captureWav('whispaste_9.wav'), input());

        expect(FileStat.statSync(pendingDir).mode & 0x1FF, 0x1C0);
      },
      skip: Platform.isWindows ? 'POSIX permissions only' : null,
    );

    test('rejects an input without an entry ID', () async {
      final wav = captureWav('whispaste_2.wav');
      const noId = RecordingInput(
        transcript: _transcript,
        audioDuration: Duration.zero,
        modelId: 'm',
        isLocal: true,
        languageCode: 'de',
        applyTextReplacements: false,
        historyMaxEntries: 0,
        wordCount: 1,
        processingDurationSec: 0,
      );

      await expectLater(queue().park(wav, noId), throwsA(isA<ArgumentError>()));
      expect(File(wav).existsSync(), isTrue);
    });

    test('puts the audio back when the record cannot be written', () async {
      final wav = captureWav('whispaste_3.wav');
      // A folder where the record's temp file should go makes that write fail.
      Directory(
        p.join(pendingDir, '1781775015000-0042.json.tmp'),
      ).createSync(recursive: true);

      await expectLater(queue().park(wav, input()), throwsA(anything));

      expect(File(wav).existsSync(), isTrue, reason: 'audio must not be lost');
    });
  });

  group('recoverAll', () {
    test('saves a parked dictation with its original ID and time, then '
        'removes its files', () async {
      await queue().park(captureWav('whispaste_4.wav'), input());

      final result = await queue().recoverAll(retainAudio: false);

      expect(result.saved, 1);
      final entry = await db.getEntry('1781775015000-0042');
      expect(entry, isNotNull);
      expect(entry!.content, _transcript);
      expect(entry.timestamp, _capturedAt);
      expect(entry.originalTranscript, 'roher Text');
      expect(entry.targetApp, 'com.example.editor');
      expect(pendingFiles(), isEmpty);
    });

    test('does not write a duplicate when the first save did reach the '
        'history', () async {
      // The first save finished after its 5 s budget: the entry exists and
      // the audio was parked anyway.
      await queue().park(captureWav('whispaste_5.wav'), input());
      await store.save(input());
      saveCalls = 0;

      final result = await queue().recoverAll(retainAudio: false);

      expect(saveCalls, 0);
      expect(result.saved, 0);
      expect(await db.allEntries(limit: 100, offset: 0), hasLength(1));
      expect(pendingFiles(), isEmpty);
    });

    test('keeps the audio and counts a failure when the save fails', () async {
      await queue().park(captureWav('whispaste_6.wav'), input());
      failSaves = true;

      final result = await queue().recoverAll(retainAudio: false);

      expect(result.failed, 1);
      expect(result.saved, 0);
      expect(
        pendingFiles(),
        containsAll(['1781775015000-0042.json', '1781775015000-0042.wav']),
      );
    });

    test('stops retrying after maxAttempts failures and never calls the '
        'store again', () async {
      await queue(maxAttempts: 3).park(captureWav('whispaste_7.wav'), input());
      failSaves = true;

      for (var run = 0; run < 3; run++) {
        await queue(maxAttempts: 3).recoverAll(retainAudio: false);
      }
      saveCalls = 0;
      final result = await queue(maxAttempts: 3).recoverAll(retainAudio: false);

      expect(saveCalls, 0);
      expect(result.skipped, 1);
      expect(result.failed, 0);
      expect(
        pendingFiles(),
        containsAll(['1781775015000-0042.json', '1781775015000-0042.wav']),
        reason: 'the capped entry stays until the cap evicts it',
      );
    });

    test('a save that succeeds after earlier failures is not affected by '
        'the counter', () async {
      await queue(maxAttempts: 3).park(captureWav('whispaste_8.wav'), input());
      failSaves = true;
      await queue(maxAttempts: 3).recoverAll(retainAudio: false);
      failSaves = false;

      final result = await queue(maxAttempts: 3).recoverAll(retainAudio: false);

      expect(result.saved, 1);
      expect(await db.getEntry('1781775015000-0042'), isNotNull);
    });

    test(
      'drops a record whose audio is gone, without a save attempt',
      () async {
        await queue().park(captureWav('whispaste_9.wav'), input());
        File(p.join(pendingDir, '1781775015000-0042.wav')).deleteSync();

        final result = await queue().recoverAll(retainAudio: false);

        expect(saveCalls, 0);
        expect(result.skipped, 1);
        expect(pendingFiles(), isEmpty);
      },
    );

    test('skips an unreadable record and still recovers the others', () async {
      await queue().park(captureWav('whispaste_10.wav'), input());
      File(p.join(pendingDir, 'broken.json')).writeAsStringSync('{not json');

      final result = await queue().recoverAll(retainAudio: false);

      expect(result.saved, 1);
      expect(
        File(p.join(pendingDir, 'broken.json')).existsSync(),
        isTrue,
        reason: 'an unreadable record is kept, not guessed at',
      );
    });

    test('hands the audio to retention when it is on, and deletes it when '
        'it is off', () async {
      await queue().park(captureWav('whispaste_11.wav'), input());
      // Stands in for the app callback, which moves the WAV into retained
      // audio and links it to the entry.
      final retainedDir = p.join(tmp.path, 'retained');
      String? retainedFrom;
      await queue(
        retain: (id, wav) async {
          retainedFrom = wav;
          Directory(retainedDir).createSync();
          File(wav).renameSync(p.join(retainedDir, p.basename(wav)));
        },
      ).recoverAll(retainAudio: true);
      expect(retainedFrom, endsWith('1781775015000-0042.wav'));
      expect(
        File(p.join(retainedDir, '1781775015000-0042.wav')).existsSync(),
        isTrue,
      );

      await queue().park(captureWav('whispaste_12.wav'), input(id: 'b-2'));
      await queue().recoverAll(retainAudio: false);
      expect(pendingFiles(), isEmpty);
    });

    test(
      'returns nothing and does not fail when the folder is missing',
      () async {
        final result = await queue().recoverAll(retainAudio: false);

        expect(result.saved, 0);
        expect(saveCalls, 0);
      },
    );
  });

  group('cap', () {
    test('evicts the oldest parked dictations beyond maxEntries', () async {
      final oldest = input(id: '1-0001');
      final middle = RecordingInput(
        transcript: 'zwei',
        audioDuration: Duration.zero,
        modelId: 'm',
        isLocal: true,
        languageCode: 'de',
        applyTextReplacements: false,
        historyMaxEntries: 0,
        wordCount: 1,
        processingDurationSec: 0,
        entryId: '2-0002',
        createdAt: _capturedAt.add(const Duration(minutes: 1)),
      );
      final newest = RecordingInput(
        transcript: 'drei',
        audioDuration: Duration.zero,
        modelId: 'm',
        isLocal: true,
        languageCode: 'de',
        applyTextReplacements: false,
        historyMaxEntries: 0,
        wordCount: 1,
        processingDurationSec: 0,
        entryId: '3-0003',
        createdAt: _capturedAt.add(const Duration(minutes: 2)),
      );
      // Parked in arbitrary order; eviction follows the capture time.
      final q = queue(maxEntries: 2);
      await q.park(captureWav('a.wav'), newest);
      await q.park(captureWav('b.wav'), oldest);
      await q.park(captureWav('c.wav'), middle);

      expect(pendingFiles(), [
        '2-0002.json',
        '2-0002.wav',
        '3-0003.json',
        '3-0003.wav',
      ]);
    });
  });

  group('restart', () {
    test('a new queue instance recovers what an earlier one parked', () async {
      await queue().park(captureWav('whispaste_13.wav'), input());
      failSaves = true;
      await queue().recoverAll(retainAudio: false);

      failSaves = false;
      final result = await queue().recoverAll(retainAudio: false);

      expect(result.saved, 1);
      expect(await db.allEntries(limit: 100, offset: 0), hasLength(1));
    });
  });

  group('factory reset scope', () {
    test('the pending-audio folder is among the user audio directories', () {
      paths.appDataDirOverride = tmp.path;
      addTearDown(() => paths.appDataDirOverride = null);

      expect(paths.pendingAudioDir(), p.join(tmp.path, 'pending-audio'));
      expect(paths.userAudioDirectories(), contains(paths.pendingAudioDir()));
    });
  });

  group('retry of a failed transcription (UIA-FLW-01)', () {
    late DateTime now;

    setUp(() => now = _capturedAt);

    PendingAudioQueue retryQueue({
      Future<void> Function(String entryId, String wavPath)? retain,
    }) => PendingAudioQueue(
      directory: () => pendingDir,
      save: (input) async {
        saveCalls++;
        if (failSaves) throw StateError('history write failed');
        return store.save(input);
      },
      entryExists: (id) async => (await db.getEntry(id)) != null,
      retainAudio: retain,
      clock: () => now,
    );

    Future<void> parkRetry(
      PendingAudioQueue q, {
      String id = 'r1',
      String code = 'stt_server_failed',
      Duration maxAge = const Duration(hours: 24),
    }) => q.parkForRetry(
      captureWav('$id.wav'),
      entryId: id,
      capturedAt: _capturedAt,
      audioDuration: const Duration(seconds: 7),
      errorCode: code,
      expiresAt: now.add(maxAge),
    );

    RecordingInput retried(String text, {String id = 'r1'}) => RecordingInput(
      transcript: text,
      audioDuration: const Duration(seconds: 7),
      modelId: 'parakeet-tdt',
      isLocal: true,
      languageCode: 'de',
      applyTextReplacements: false,
      historyMaxEntries: 0,
      wordCount: 1,
      processingDurationSec: 1,
      entryId: id,
      createdAt: _capturedAt,
    );

    test(
      'keeps the audio with its error and lists it for the retry UI',
      () async {
        final q = retryQueue();

        await parkRetry(q);

        final entries = await q.retryEntries();
        expect(entries.map((e) => e.entryId), ['r1']);
        expect(entries.single.errorCode, 'stt_server_failed');
        expect(pendingFiles(), ['r1.json', 'r1.wav']);
      },
    );

    test('retry entries are listed oldest first, so the last one is the newest '
        '(UIA-FLW-01)', () async {
      final q = retryQueue();
      // Names sort the other way round than the capture times.
      await q.parkForRetry(
        captureWav('aa-new.wav'),
        entryId: 'aa-new',
        capturedAt: _capturedAt,
        audioDuration: const Duration(seconds: 3),
        errorCode: 'stt_server_failed',
        expiresAt: now.add(const Duration(hours: 24)),
      );
      await q.parkForRetry(
        captureWav('zz-old.wav'),
        entryId: 'zz-old',
        capturedAt: _capturedAt.subtract(const Duration(hours: 1)),
        audioDuration: const Duration(seconds: 3),
        errorCode: 'stt_server_failed',
        expiresAt: now.add(const Duration(hours: 24)),
      );

      final entries = await q.retryEntries();

      expect(entries.map((e) => e.entryId), ['zz-old', 'aa-new']);
    });

    test('an entry is deleted once its 24 h are over (fake clock)', () async {
      final q = retryQueue();
      await parkRetry(q);

      now = _capturedAt.add(const Duration(hours: 23, minutes: 59));
      expect(await q.purgeExpired(), 0);
      expect(pendingFiles(), isNotEmpty);

      now = _capturedAt.add(const Duration(hours: 24, minutes: 1));
      expect(await q.purgeExpired(), 1);
      expect(pendingFiles(), isEmpty);
    });

    test('startup purges retries that expired while the app was closed, and '
        'never saves them as history entries', () async {
      final q = retryQueue();
      await parkRetry(q);

      now = _capturedAt.add(const Duration(hours: 25));
      final result = await q.recoverAll(retainAudio: false);

      expect(saveCalls, 0);
      expect(result.saved, 0);
      expect(pendingFiles(), isEmpty);
    });

    test('startup keeps a retry that is still within its 24 h', () async {
      final q = retryQueue();
      await parkRetry(q);

      await q.recoverAll(retainAudio: false);

      expect(saveCalls, 0);
      expect(await q.retryEntries(), hasLength(1));
    });

    test(
      'a successful retry saves the text and deletes audio and record',
      () async {
        final q = retryQueue();
        await parkRetry(q);

        final outcome = await q.retry(
          'r1',
          transcribe: (wav) async => 'Gerettet',
          buildInput: (text, _) => retried(text),
          retainAudio: false,
        );

        expect(outcome, PendingRetryOutcome.saved);
        expect(saveCalls, 1);
        expect((await db.getEntry('r1'))?.content, 'Gerettet');
        expect(pendingFiles(), isEmpty);
      },
    );

    test('with audio retention on, a successful retry hands the audio to '
        'retention instead of deleting it', () async {
      final retained = <String>[];
      final q = retryQueue(
        retain: (id, wavPath) async {
          retained.add('$id|$wavPath');
          File(wavPath).renameSync(p.join(captureDir, 'kept-$id.wav'));
        },
      );
      await parkRetry(q);

      await q.retry(
        'r1',
        transcribe: (wav) async => 'Gerettet',
        buildInput: (text, _) => retried(text),
        retainAudio: true,
      );

      expect(retained, hasLength(1));
      expect(retained.single, startsWith('r1|'));
      expect(pendingFiles(), isEmpty);
    });

    test('a failed retry keeps audio and record for another try', () async {
      final q = retryQueue();
      await parkRetry(q);

      final outcome = await q.retry(
        'r1',
        transcribe: (wav) async => throw StateError('server still down'),
        buildInput: (text, _) => retried(text),
        retainAudio: false,
      );

      expect(outcome, PendingRetryOutcome.failed);
      expect(saveCalls, 0);
      expect(pendingFiles(), ['r1.json', 'r1.wav']);
    });

    test('a retry whose history save fails keeps the audio', () async {
      final q = retryQueue();
      await parkRetry(q);
      failSaves = true;

      final outcome = await q.retry(
        'r1',
        transcribe: (wav) async => 'Gerettet',
        buildInput: (text, _) => retried(text),
        retainAudio: false,
      );

      expect(outcome, PendingRetryOutcome.failed);
      expect(pendingFiles(), ['r1.json', 'r1.wav']);
    });

    test(
      'an empty transcript deletes the audio: silence is not worth keeping',
      () async {
        final q = retryQueue();
        await parkRetry(q);

        final outcome = await q.retry(
          'r1',
          transcribe: (wav) async => '',
          buildInput: (text, _) => retried(text),
          retainAudio: false,
        );

        expect(outcome, PendingRetryOutcome.empty);
        expect(saveCalls, 0);
        expect(pendingFiles(), isEmpty);
      },
    );

    test('a retry for an entry without audio drops the record', () async {
      final q = retryQueue();
      await parkRetry(q);
      File(p.join(pendingDir, 'r1.wav')).deleteSync();

      final outcome = await q.retry(
        'r1',
        transcribe: (wav) async => 'x',
        buildInput: (text, _) => retried(text),
        retainAudio: false,
      );

      expect(outcome, PendingRetryOutcome.missing);
      expect(pendingFiles(), isEmpty);
    });

    test('discard removes audio and record', () async {
      final q = retryQueue();
      await parkRetry(q);

      await q.discard('r1');

      expect(pendingFiles(), isEmpty);
      expect(await q.retryEntries(), isEmpty);
    });

    test('a repeatable error is retried, a non-repeatable one is not', () {
      for (final code in [
        'stt_server_failed',
        'stt_cuda_oom',
        'transcription_timeout',
        'stt_server_connection_lost',
        'cloud_network_error',
        'cloud_timeout',
      ]) {
        expect(isRepeatableTranscriptionError(code), isTrue, reason: code);
      }
      for (final code in [
        'transcription_empty',
        'cloud_auth_error',
        'cloud_quota_exceeded',
        'stt_model_file_missing',
        'stt.reject.invalid_wav',
      ]) {
        expect(isRepeatableTranscriptionError(code), isFalse, reason: code);
      }
    });
  });
}

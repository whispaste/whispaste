import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/dictation_text_steps.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';
import 'package:whispaste/services/recording_store.dart';
import 'package:whispaste/services/text_transforms.dart';

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
    applyReplacements: store.applyReplacements,
    directory: () => pendingDir,
    save: (input) async {
      saveCalls++;
      if (failSaves) throw StateError('history write failed: $_transcript');
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

    for (final (label, value) in [('missing', null), ('corrupted', 'yes')]) {
      test('a record whose replacements flag is $label is saved as final '
          'text, without replacements', () async {
        await db.upsertReplacementWithTriggers(
          id: 'r1',
          triggers: const ['Diktat'],
          replacement: 'DIKTAT',
          createdAt: _capturedAt,
        );
        await queue().park(captureWav('whispaste_legacy.wav'), input());
        final record = File(p.join(pendingDir, '1781775015000-0042.json'));
        final json =
            jsonDecode(record.readAsStringSync()) as Map<String, dynamic>
              ..remove('applyTextReplacements');
        if (value != null) json['applyTextReplacements'] = value;
        record.writeAsStringSync(jsonEncode(json));

        final result = await queue().recoverAll(retainAudio: false);

        expect(result.saved, 1);
        expect((await db.getEntry('1781775015000-0042'))!.content, _transcript);
      });
    }

    test('a raw transcript gets its stored text steps on recovery, with '
        'the cleaned transcript kept as the original', () async {
      await db.upsertReplacementWithTriggers(
        id: 'r1',
        triggers: const ['Diktat'],
        replacement: 'DIKTAT',
        createdAt: _capturedAt,
      );
      const raw = 'äh ein  Diktat Komma\nneue Zeile weiter';
      final rawInput = RecordingInput(
        transcript: raw,
        audioDuration: const Duration(seconds: 3),
        modelId: 'parakeet-tdt',
        isLocal: true,
        languageCode: 'de',
        applyTextReplacements: false,
        historyMaxEntries: 0,
        wordCount: 7,
        processingDurationSec: 1,
        entryId: '1781775015000-0043',
        createdAt: _capturedAt,
      );
      const steps = DictationTextSteps(
        removeFillerWords: true,
        spokenPunctuation: true,
        voiceLineBreaks: true,
        textReplacements: true,
      );

      await queue().park(
        captureWav('whispaste_raw.wav'),
        rawInput,
        rawTextSteps: steps,
      );
      await queue().recoverAll(retainAudio: false);

      final cleaned = collapseTranscriptWhitespace(raw);
      final expected = await steps.apply(
        cleaned,
        languageCode: 'de',
        applyReplacements: store.applyReplacements,
      );
      final entry = await db.getEntry('1781775015000-0043');
      expect(entry!.content, expected);
      expect(entry.content, contains('DIKTAT'));
      expect(entry.content, isNot(contains('äh')));
      expect(entry.originalTranscript, cleaned);
    });

    for (final (label, value) in [
      ('a corrupted', 'nonsense'),
      ('a broken', <String, Object?>{'textReplacements': 'yes'}),
    ]) {
      test('$label text-steps value never fails the record', () async {
        await queue().park(captureWav('whispaste_bad.wav'), input());
        final record = File(p.join(pendingDir, '1781775015000-0042.json'));
        final json =
            jsonDecode(record.readAsStringSync()) as Map<String, dynamic>;
        json['rawTextSteps'] = value;
        record.writeAsStringSync(jsonEncode(json));

        final result = await queue().recoverAll(retainAudio: false);

        expect(result.saved, 1);
        expect((await db.getEntry('1781775015000-0042'))!.content, _transcript);
      });
    }

    test('a record from a build that stored only the replacements flag gets '
        'just the replacements', () async {
      await db.upsertReplacementWithTriggers(
        id: 'r1',
        triggers: const ['Diktat'],
        replacement: 'DIKTAT',
        createdAt: _capturedAt,
      );
      await queue().park(captureWav('whispaste_flag.wav'), input());
      final record = File(p.join(pendingDir, '1781775015000-0042.json'));
      final json = jsonDecode(record.readAsStringSync()) as Map<String, dynamic>
        ..remove('rawTextSteps')
        ..['applyTextReplacements'] = true;
      record.writeAsStringSync(jsonEncode(json));

      await queue().recoverAll(retainAudio: false);

      expect(
        (await db.getEntry('1781775015000-0042'))!.content,
        _transcript.replaceAll('Diktat', 'DIKTAT'),
      );
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

    test('a failed save does not log the error text', () async {
      await queue().park(captureWav('whispaste_7.wav'), input());
      failSaves = true;
      final records = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(sub.cancel);

      await queue().recoverAll(retainAudio: false);

      final logged = records.map((r) => '${r.message} ${r.error}').join('\n');
      expect(logged, contains('StateError'));
      expect(logged, isNot(contains(_transcript)));
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

      await queue().park(
        captureWav('whispaste_12.wav'),
        input(id: '1781775015004-0004'),
      );
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

  group('never throws', () {
    test('a failed retry whose record cannot be rewritten does not escape '
        'recoverAll', () async {
      final wav = captureWav('whispaste_nt1.wav');
      await queue().park(wav, input());
      failSaves = true;
      // A directory where the temp record must go makes the rewrite fail.
      Directory('$pendingDir/1781775015000-0042.json.tmp').createSync();

      final result = await queue().recoverAll(retainAudio: false);

      expect(result.failed, 1);
      expect(
        File(p.join(pendingDir, '1781775015000-0042.wav')).existsSync(),
        isTrue,
      );
    });

    test('removes orphaned temp records and WAVs without a record that are '
        'older than an hour, and keeps young ones', () async {
      Directory(pendingDir).createSync(recursive: true);
      final oldTmp = File(p.join(pendingDir, '1781775017000-0001.json.tmp'))
        ..writeAsStringSync('{');
      final oldWav = File(p.join(pendingDir, '1781775018000-0002.wav'))
        ..writeAsBytesSync([1, 2, 3]);
      final youngWav = File(p.join(pendingDir, '1781775019000-0003.wav'))
        ..writeAsBytesSync([1, 2, 3]);
      final old = DateTime.now().subtract(const Duration(hours: 2));
      oldTmp.setLastModifiedSync(old);
      oldWav.setLastModifiedSync(old);

      await queue().recoverAll(retainAudio: false);

      expect(oldTmp.existsSync(), isFalse);
      expect(oldWav.existsSync(), isFalse);
      expect(youngWav.existsSync(), isTrue);
    });
  });

  group('entry ID validation', () {
    test('park rejects an entry ID that is not a recording ID and moves no '
        'audio', () async {
      final wav = captureWav('whispaste_id1.wav');

      await expectLater(
        queue().park(wav, input(id: '../escape')),
        throwsA(isA<ArgumentError>()),
      );
      expect(File(wav).existsSync(), isTrue);
      expect(pendingFiles(), isEmpty);
    });

    test('discard never touches a path outside the folder', () async {
      final outside = File(p.join(tmp.path, 'outside.wav'))
        ..writeAsBytesSync([1]);
      Directory(pendingDir).createSync(recursive: true);

      await queue().discard('../outside');

      expect(outside.existsSync(), isTrue);
    });

    test('a record with an invalid entry ID is skipped, never saved or '
        'deleted outside the folder', () async {
      Directory(pendingDir).createSync(recursive: true);
      final outside = File(p.join(tmp.path, 'victim.wav'))
        ..writeAsBytesSync([1]);
      File(p.join(pendingDir, 'bad.json')).writeAsStringSync(
        '{"entryId":"../victim","createdAt":"2026-10-18T09:30:15.000",'
        '"transcript":"x","audioDurationMs":1,"modelId":"m","isLocal":true,'
        '"languageCode":"de","historyMaxEntries":0,"wordCount":1,'
        '"processingDurationSec":0,"attempts":0}',
      );

      final result = await queue().recoverAll(retainAudio: false);

      expect(saveCalls, 0);
      expect(result.saved, 0);
      expect(outside.existsSync(), isTrue);
      expect(File(p.join(pendingDir, 'bad.json')).existsSync(), isTrue);
    });
  });

  group('expiry', () {
    test('removes a parked dictation older than 7 days when retention is '
        'off, and keeps a younger one', () async {
      final wav = captureWav('whispaste_exp1.wav');
      await queue().park(wav, input());

      await queue().sweepExpired(
        retainAudio: false,
        now: _capturedAt.add(const Duration(days: 6)),
      );
      expect(pendingFiles(), isNotEmpty);

      await queue().sweepExpired(
        retainAudio: false,
        now: _capturedAt.add(const Duration(days: 8)),
      );
      expect(pendingFiles(), isEmpty);
    });

    test('uses the audio retention window when retention is on', () async {
      final wav = captureWav('whispaste_exp2.wav');
      await queue().park(wav, input());

      await queue().sweepExpired(
        retainAudio: true,
        now: _capturedAt.add(const Duration(days: 8)),
      );
      expect(pendingFiles(), isNotEmpty);

      await queue().sweepExpired(
        retainAudio: true,
        now: _capturedAt.add(const Duration(days: 31)),
      );
      expect(pendingFiles(), isEmpty);
    });

    test('recoverAll drops an expired record instead of saving it', () async {
      final wav = captureWav('whispaste_exp3.wav');
      await queue().park(wav, input());

      final result = await queue().recoverAll(
        retainAudio: false,
        now: _capturedAt.add(const Duration(days: 8)),
      );

      expect(saveCalls, 0);
      expect(result.saved, 0);
      expect(pendingFiles(), isEmpty);
    });
  });

  group('file mode', () {
    test('the parked WAV and record are readable by the owner only', () async {
      if (Platform.isWindows) return;
      final wav = captureWav('whispaste_mode.wav');
      expect(File(wav).statSync().mode & 0x1ff, isNot(0x180));

      await queue().park(wav, input());

      for (final name in pendingFiles()) {
        final mode = File(p.join(pendingDir, name)).statSync().mode & 0x1ff;
        expect(mode, 0x180, reason: 'mode of $name');
      }
    });
  });

  group('discard', () {
    test(
      'removes the parked copy of one entry and leaves the others',
      () async {
        final wavA = captureWav('whispaste_dA.wav');
        final wavB = captureWav('whispaste_dB.wav');
        await queue().park(wavA, input());
        await queue().park(wavB, input(id: '1781775016000-0043'));

        await queue().discard('1781775015000-0042');

        expect(pendingFiles(), [
          '1781775016000-0043.json',
          '1781775016000-0043.wav',
        ]);
      },
    );

    test('is a no-op for an entry without a parked copy', () async {
      await queue().discard('1781775099000-0099');
      expect(pendingFiles(), isEmpty);
    });
  });

  group('cap', () {
    test('evicts the oldest parked dictations beyond maxEntries', () async {
      final oldest = input(id: '1781775015001-0001');
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
        entryId: '1781775015002-0002',
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
        entryId: '1781775015003-0003',
        createdAt: _capturedAt.add(const Duration(minutes: 2)),
      );
      // Parked in arbitrary order; eviction follows the capture time.
      final q = queue(maxEntries: 2);
      await q.park(captureWav('a.wav'), newest);
      await q.park(captureWav('b.wav'), oldest);
      await q.park(captureWav('c.wav'), middle);

      expect(pendingFiles(), [
        '1781775015002-0002.json',
        '1781775015002-0002.wav',
        '1781775015003-0003.json',
        '1781775015003-0003.wav',
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
      String id = '1781775015020-0020',
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

    RecordingInput retried(String text, {String id = '1781775015020-0020'}) =>
        RecordingInput(
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
        expect(entries.map((e) => e.entryId), ['1781775015020-0020']);
        expect(entries.single.errorCode, 'stt_server_failed');
        expect(pendingFiles(), [
          '1781775015020-0020.json',
          '1781775015020-0020.wav',
        ]);
      },
    );

    test('retry entries are listed oldest first, so the last one is the newest '
        '(UIA-FLW-01)', () async {
      final q = retryQueue();
      // Names sort the other way round than the capture times.
      await q.parkForRetry(
        captureWav('1781775015010-0010.wav'),
        entryId: '1781775015010-0010',
        capturedAt: _capturedAt,
        audioDuration: const Duration(seconds: 3),
        errorCode: 'stt_server_failed',
        expiresAt: now.add(const Duration(hours: 24)),
      );
      await q.parkForRetry(
        captureWav('1781775015011-0011.wav'),
        entryId: '1781775015011-0011',
        capturedAt: _capturedAt.subtract(const Duration(hours: 1)),
        audioDuration: const Duration(seconds: 3),
        errorCode: 'stt_server_failed',
        expiresAt: now.add(const Duration(hours: 24)),
      );

      final entries = await q.retryEntries();

      expect(entries.map((e) => e.entryId), [
        '1781775015011-0011',
        '1781775015010-0010',
      ]);
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
          '1781775015020-0020',
          transcribe: (wav) async => 'Gerettet',
          buildInput: (text, _) => retried(text),
          retainAudio: false,
        );

        expect(outcome, PendingRetryOutcome.saved);
        expect(saveCalls, 1);
        expect((await db.getEntry('1781775015020-0020'))?.content, 'Gerettet');
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
        '1781775015020-0020',
        transcribe: (wav) async => 'Gerettet',
        buildInput: (text, _) => retried(text),
        retainAudio: true,
      );

      expect(retained, hasLength(1));
      expect(retained.single, startsWith('1781775015020-0020|'));
      expect(pendingFiles(), isEmpty);
    });

    test('a failed retry keeps audio and record for another try', () async {
      final q = retryQueue();
      await parkRetry(q);

      final outcome = await q.retry(
        '1781775015020-0020',
        transcribe: (wav) async => throw StateError('server still down'),
        buildInput: (text, _) => retried(text),
        retainAudio: false,
      );

      expect(outcome, PendingRetryOutcome.failed);
      expect(saveCalls, 0);
      expect(pendingFiles(), [
        '1781775015020-0020.json',
        '1781775015020-0020.wav',
      ]);
    });

    test('a retry whose history save fails keeps the audio', () async {
      final q = retryQueue();
      await parkRetry(q);
      failSaves = true;

      final outcome = await q.retry(
        '1781775015020-0020',
        transcribe: (wav) async => 'Gerettet',
        buildInput: (text, _) => retried(text),
        retainAudio: false,
      );

      expect(outcome, PendingRetryOutcome.failed);
      expect(pendingFiles(), [
        '1781775015020-0020.json',
        '1781775015020-0020.wav',
      ]);
    });

    test(
      'an empty transcript deletes the audio: silence is not worth keeping',
      () async {
        final q = retryQueue();
        await parkRetry(q);

        final outcome = await q.retry(
          '1781775015020-0020',
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
      File(p.join(pendingDir, '1781775015020-0020.wav')).deleteSync();

      final outcome = await q.retry(
        '1781775015020-0020',
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

      await q.discard('1781775015020-0020');

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

/// Crash-loop breaker of the startup recovery (#1783): a recording whose
/// transcription crashed the app is not transcribed automatically again in
/// that version and stays in the journal; a success or a catchable failure
/// removes the marker; a new version tries once more.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_journal_provider.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/services/audio/recovery/recovery_crash_guard.dart';
import 'package:whispaste/services/telemetry_service.dart';
import '../../../fixtures/telemetry_hits.dart';

void main() {
  late Directory tmp;
  late RecordingJournal journal;
  late String version;
  late List<Map<String, String>> sent;
  final startedAt = DateTime.utc(2026, 11, 17, 9);
  // Ten minutes after the interrupted recording started.
  final now = startedAt.add(const Duration(minutes: 10));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp1783-recovery-');
    journal = RecordingJournal('${tmp.path}/journal');
    version = '1.5.2';
    sent = [];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// A fresh guard is a fresh process: it reads what the last one left.
  RecoveryCrashGuard guard() => RecoveryCrashGuard(
    dir: () => '${tmp.path}/data',
    appVersion: () => version,
  );

  File attemptFile() => File('${tmp.path}/data/.recovery_attempt');

  InterruptedRecording interrupted(String id) {
    final wavPath = '${tmp.path}/$id.wav';
    File(wavPath).writeAsBytesSync(Uint8List(1000));
    final journalPath = '${journal.directory}/$id.json';
    File(journalPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': kRecordingJournalVersion,
          'id': id,
          'startedAt': startedAt.toIso8601String(),
          'wavPath': wavPath,
        }),
      );
    return InterruptedRecording(
      id: id,
      startedAt: startedAt,
      wavPath: wavPath,
      journalPath: journalPath,
    );
  }

  RecordingRecovery recoveryWith(
    RecoveryCrashGuard crashGuard,
    Future<RecoveryTranscription> Function(String) transcribe, {
    List<String>? parked,
  }) => RecordingRecovery(
    audioDir: tmp.path,
    crashGuard: crashGuard,
    transcribe: transcribe,
    park:
        ({
          required wavPath,
          required errorCode,
          required capturedAt,
          required audioDuration,
          required expiresAt,
        }) async => parked?.add(errorCode),
  );

  /// Simulates a process that died inside the transcription of [ids].
  void crashWhileTranscribing(List<String> ids) {
    final dying = guard();
    for (final id in ids) {
      dying.markAttempt(id);
    }
  }

  Future<void> startUp(
    RecordingRecovery recovery,
    List<InterruptedRecording> recordings,
  ) async {
    final container = ProviderContainer(
      overrides: [
        recordingJournalProvider.overrideWithValue(journal),
        recordingRecoveryProvider.overrideWithValue(recovery),
        interruptedRecordingsProvider.overrideWith(
          (ref) async =>
              RecordingJournalScan(recordings: recordings, skippedCorrupt: 0),
        ),
        telemetryProvider.overrideWithValue(
          TelemetryService(
            client: MockClient((request) async {
              sent.addAll(telemetryHits(request));
              return http.Response('', 204);
            }),
            endpointUrl: 'https://stats.example.invalid',
            siteId: 1,
            consentGranted: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await recoverInterruptedRecordings(container);
    await container.read(telemetryProvider).flush();
  }

  test('the marker is on disk while the transcription runs', () async {
    final recording = interrupted('rec-1');
    var markedDuring = false;
    final recovery = recoveryWith(guard(), (_) async {
      markedDuring = attemptFile().readAsLinesSync().contains('rec-1');
      return const RecoveryTranscription.ok();
    });

    expect(await recovery.recover(recording), RecoveryOutcome.recovered);
    expect(markedDuring, isTrue);
    expect(attemptFile().existsSync(), isFalse);
  });

  test(
    'a failure without a crash removes the marker and parks as before',
    () async {
      final recording = interrupted('rec-2');
      final parked = <String>[];
      final recovery = recoveryWith(
        guard(),
        (_) async => throw StateError('engine said no'),
        parked: parked,
      );

      expect(
        await withClock(Clock.fixed(now), () => recovery.recover(recording)),
        RecoveryOutcome.parked,
      );
      expect(parked, ['save_failed']);
      expect(attemptFile().existsSync(), isFalse);
    },
  );

  test('a recording that crashed the app is not transcribed at the next '
      'start, stays in the journal and is counted once', () async {
    final crashed = interrupted('rec-crash');
    final other = interrupted('rec-other');
    crashWhileTranscribing(['rec-crash']);

    final transcribed = <String>[];
    final nextStart = guard();
    final recovery = recoveryWith(nextStart, (path) async {
      transcribed.add(path);
      return const RecoveryTranscription.ok();
    });
    await startUp(recovery, [crashed, other]);

    // The other recording is recovered as usual.
    expect(transcribed, [other.wavPath]);
    expect(File(other.journalPath).existsSync(), isFalse);
    // The crashed one keeps its audio and journal entry for a manual recovery.
    expect(File(crashed.journalPath).existsSync(), isTrue);
    expect(File(crashed.wavPath!).existsSync(), isTrue);
    expect(nextStart.crashedBefore('rec-crash'), isTrue);
    expect(attemptFile().existsSync(), isFalse);
    // One counter, no id or content.
    expect(sent, hasLength(1));
    expect(sent.single['e_c'], 'recovery');
    expect(sent.single['e_a'], 'crash_skipped');
    expect(sent.single.values.join(), isNot(contains('rec-crash')));

    // And on the start after that: still skipped, not counted again.
    transcribed.clear();
    sent.clear();
    await startUp(
      recoveryWith(guard(), (path) async {
        transcribed.add(path);
        return const RecoveryTranscription.ok();
      }),
      [crashed],
    );
    expect(transcribed, isEmpty);
    expect(sent, isEmpty);
    expect(File(crashed.journalPath).existsSync(), isTrue);
  });

  test('a new app version tries once more, guarded again', () async {
    final crashed = interrupted('rec-v');
    crashWhileTranscribing(['rec-v']);
    // The start in 1.5.2 records the crash and skips the recording.
    await startUp(
      recoveryWith(guard(), (_) async => fail('must not run in 1.5.2')),
      [crashed],
    );

    version = '1.5.3';
    // The update tries again; it crashes once more. recover() checks the WAV
    // asynchronously first, so the test waits for the transcription to start.
    final retry = guard();
    expect(retry.skipsAutomatic('rec-v'), isFalse);
    final transcribing = Completer<bool>();
    final attempt = recoveryWith(retry, (_) {
      transcribing.complete(attemptFile().existsSync());
      return Completer<RecoveryTranscription>().future; // dies inside
    });
    unawaited(attempt.recover(crashed));
    expect(await transcribing.future, isTrue);

    // The next 1.5.3 start does not run it again.
    await startUp(
      recoveryWith(guard(), (_) async => fail('must not run twice in 1.5.3')),
      [crashed],
    );
    expect(File(crashed.journalPath).existsSync(), isTrue);
  });

  test('a manual recovery of a crashed recording runs and clears it', () async {
    final crashed = interrupted('rec-m');
    crashWhileTranscribing(['rec-m']);
    final nextStart = guard();
    await startUp(recoveryWith(nextStart, (_) async => fail('not automatic')), [
      crashed,
    ]);

    final outcome = await recoveryWith(
      nextStart,
      (_) async => const RecoveryTranscription.ok(),
    ).recover(crashed);
    expect(outcome, RecoveryOutcome.recovered);
    expect(attemptFile().existsSync(), isFalse);

    // Once it left the journal its crash record is dropped.
    nextStart.forgetAllExcept(const []);
    expect(guard().crashedBefore('rec-m'), isFalse);
  });

  test('an orderly quit during a recovery leaves no crash behind', () async {
    final running = guard()..markAttempt('rec-q');
    running.clearAllAttempts();

    expect(attemptFile().existsSync(), isFalse);
    expect(guard().takePreviousCrash(), isEmpty);
  });

  test('every recording in flight at the crash is recorded', () {
    crashWhileTranscribing(['a', 'b']);
    final next = guard();

    expect(next.takePreviousCrash(), ['a', 'b']);
    expect(next.takePreviousCrash(), isEmpty);
    expect(next.skipsAutomatic('a'), isTrue);
    expect(next.skipsAutomatic('b'), isTrue);
    expect(next.skipsAutomatic('c'), isFalse);
  });

  test('the startup recovery waits for the first frame and a pause', () {
    fakeAsync((async) {
      final frame = Completer<void>();
      var ran = false;
      runAfterFirstFrame(
        frame.future,
        () async => ran = true,
        timeout: const Duration(seconds: 5),
        delay: const Duration(seconds: 2),
      );
      async.elapse(const Duration(seconds: 3));
      expect(ran, isFalse);
      frame.complete();
      async.elapse(const Duration(seconds: 1));
      expect(ran, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(ran, isTrue);
    });
  });

  test('the startup recovery still runs when no frame comes', () {
    fakeAsync((async) {
      var ran = false;
      runAfterFirstFrame(
        Completer<void>().future,
        () async => ran = true,
        timeout: const Duration(seconds: 10),
        delay: const Duration(seconds: 2),
      );
      async.elapse(const Duration(seconds: 11));
      expect(ran, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(ran, isTrue);
    });
  });
}

/// Tests for [ProbeRunner] hang/crash/DLL detection.
///
/// All tests use fake processes and injected tiny durations —
/// no real wall-clock sleeps, no real executables.
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake process infrastructure
// ---------------------------------------------------------------------------

/// Minimal fake [Process] for use in [ProcessStartResult].
///
/// [_exitCompleter] is completed externally to simulate a process exiting.
/// [kill()] completes it with [exitOnKill] and records that it was killed.
class _FakeProcess implements Process {
  _FakeProcess({this.exitOnKill = -1});

  final int exitOnKill;
  bool wasKilled = false;

  final _exitCompleter = Completer<int>();

  /// Resolve the process exit from outside (simulates normal completion).
  void complete(int code) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
  }

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(exitOnKill);
    return true;
  }

  // The remaining Process members are unused — ProbeRunner only needs
  // exitCode and kill().
  @override
  int get pid => 0;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  Stream<List<int>> get stdout => throw UnimplementedError();
  @override
  Stream<List<int>> get stderr => throw UnimplementedError();
}

/// Builds a [ProcessStartResult] with empty-but-closeable streams.
ProcessStartResult _emptyStreams(_FakeProcess process) => ProcessStartResult(
  process: process,
  stdout: const Stream.empty(),
  stderr: const Stream.empty(),
);

// ---------------------------------------------------------------------------
// Tiny durations for deterministic hang tests
// ---------------------------------------------------------------------------

/// Startup deadline: 5 ms — expires almost immediately.
const _tinyDeadline = Duration(milliseconds: 5);

/// Heartbeat: 5 ms — same; watchdog fires after 5 ms.
const _tinyHeartbeat = Duration(milliseconds: 5);

// ---------------------------------------------------------------------------
// AC1 + AC3(a): Normal exit → no timeout flag
// ---------------------------------------------------------------------------

void main() {
  group('ProbeRunner — normal exit (AC1, AC3a)', () {
    test('process exits 0 → exitCode 0, timedOut false', () async {
      final fake = _FakeProcess();
      // Schedule a normal exit slightly after the runner starts.
      Future.delayed(const Duration(milliseconds: 1), () => fake.complete(0));

      final runner = ProbeRunner(
        launcher: (_, _, _) async => _emptyStreams(fake),
        // Use normal (long) durations — the process finishes before any tick.
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final result = await runner.run(
        executable: 'fake',
        arguments: [],
        workingDirectory: '/tmp',
      );

      expect(result.exitCode, equals(0));
      expect(result.timedOut, isFalse);
      expect(fake.wasKilled, isFalse);
    });

    test('process exits 0 → durationMs is non-negative', () async {
      final fake = _FakeProcess();
      fake.complete(0);

      final runner = ProbeRunner(
        launcher: (_, _, _) async => _emptyStreams(fake),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final result = await runner.run(
        executable: 'fake',
        arguments: [],
        workingDirectory: '/tmp',
      );

      expect(result.durationMs, greaterThanOrEqualTo(0));
    });
  });

  // ---------------------------------------------------------------------------
  // AC2 + AC3(b): Hang detection — no progress → kill + timedOut flag
  // ---------------------------------------------------------------------------

  group('ProbeRunner — hang detection (AC2, AC3b)', () {
    test(
      'no output until tiny deadline → process killed, timedOut true',
      () async {
        final fake = _FakeProcess(exitOnKill: -1);
        // The fake process never completes on its own — ProbeRunner must kill it.

        final runner = ProbeRunner(
          launcher: (_, _, _) async => _emptyStreams(fake),
          startupDeadline: _tinyDeadline,
          heartbeatTimeout: _tinyHeartbeat,
        );

        final result = await runner.run(
          executable: 'fake-hanging',
          arguments: [],
          workingDirectory: '/tmp',
        );

        expect(result.timedOut, isTrue, reason: 'must be flagged as timed out');
        expect(fake.wasKilled, isTrue, reason: 'process must be killed');
      },
    );

    test(
      'hung result classifies as Outcome.hung via classifyOutcome',
      () async {
        final fake = _FakeProcess(exitOnKill: -1);

        final runner = ProbeRunner(
          launcher: (_, _, _) async => _emptyStreams(fake),
          startupDeadline: _tinyDeadline,
          heartbeatTimeout: _tinyHeartbeat,
        );

        final result = await runner.run(
          executable: 'fake-hanging',
          arguments: [],
          workingDirectory: '/tmp',
        );

        final outcome = classifyOutcome(
          exitCode: result.exitCode,
          timedOut: result.timedOut,
          transcript: '',
          detectedLanguage: null,
          expectedLanguage: 'de',
          wer: null,
        );

        expect(outcome, equals(Outcome.hung));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC3(c): Abnormal exit → crashed
  // ---------------------------------------------------------------------------

  group('ProbeRunner — abnormal exit (AC3c)', () {
    test('exit code 1 → timedOut false, classifies as crashed', () async {
      final fake = _FakeProcess();
      fake.complete(1);

      final runner = ProbeRunner(
        launcher: (_, _, _) async => _emptyStreams(fake),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final result = await runner.run(
        executable: 'fake',
        arguments: [],
        workingDirectory: '/tmp',
      );

      expect(result.exitCode, equals(1));
      expect(result.timedOut, isFalse);

      final outcome = classifyOutcome(
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        transcript: '',
        detectedLanguage: null,
        expectedLanguage: 'de',
        wer: null,
      );
      expect(outcome, equals(Outcome.crashed));
    });
  });

  // ---------------------------------------------------------------------------
  // AC3(d): 0xC0000135 (STATUS_DLL_NOT_FOUND) → failedToStart
  // ---------------------------------------------------------------------------

  group('ProbeRunner — DLL-missing exit (AC3d)', () {
    test('0xC0000135 as signed int → classifies as failedToStart', () async {
      final fake = _FakeProcess();
      // STATUS_DLL_NOT_FOUND as signed 32-bit integer.
      fake.complete(-1073741515);

      final runner = ProbeRunner(
        launcher: (_, _, _) async => _emptyStreams(fake),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final result = await runner.run(
        executable: 'fake',
        arguments: [],
        workingDirectory: '/tmp',
      );

      expect(result.exitCode, equals(-1073741515));
      expect(result.timedOut, isFalse);

      final outcome = classifyOutcome(
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        transcript: '',
        detectedLanguage: null,
        expectedLanguage: 'de',
        wer: null,
      );
      expect(outcome, equals(Outcome.failedToStart));
    });

    test('0xC0000135 unsigned form → classifies as failedToStart', () async {
      final fake = _FakeProcess();
      fake.complete(0xC0000135); // unsigned: 3221225781
      // ignore: avoid_print
      // This value is > 2^31 so Dart stores it as a positive int.

      final runner = ProbeRunner(
        launcher: (_, _, _) async => _emptyStreams(fake),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final result = await runner.run(
        executable: 'fake',
        arguments: [],
        workingDirectory: '/tmp',
      );

      final outcome = classifyOutcome(
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        transcript: '',
        detectedLanguage: null,
        expectedLanguage: 'de',
        wer: null,
      );
      expect(outcome, equals(Outcome.failedToStart));
    });
  });

  // ---------------------------------------------------------------------------
  // AC3 — launcher throws → graceful failedToStart, not a crash
  // ---------------------------------------------------------------------------

  group('ProbeRunner — launcher failure', () {
    test('launcher throws → exitCode null, timedOut false', () async {
      final runner = ProbeRunner(
        launcher: (_, _, _) async => throw Exception('binary not found'),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final result = await runner.run(
        executable: 'nonexistent',
        arguments: [],
        workingDirectory: '/tmp',
      );

      expect(result.exitCode, isNull);
      expect(result.timedOut, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: Hanging candidate does NOT stop the orchestrator matrix
  // ---------------------------------------------------------------------------

  group('ProbeOrchestrator — hung candidate does not block matrix (AC4)', () {
    test(
      'one hanging candidate + one ok candidate: both run, ok result present',
      () async {
        // Hanging candidate: wraps ProbeRunner with tiny deadlines.
        final hangingRunner = ProbeRunner(
          launcher: (_, _, _) async {
            final fake = _FakeProcess(exitOnKill: -1);
            // Never completes on its own.
            return _emptyStreams(fake);
          },
          startupDeadline: _tinyDeadline,
          heartbeatTimeout: _tinyHeartbeat,
        );

        final hangingCandidate = _RunnerBackedCandidate(
          candidateId: 'hanging-candidate',
          runner: hangingRunner,
        );

        // Fast OK candidate that exits immediately.
        final okCandidate = _FakeOkCandidate();

        // Run both through the real orchestrator.
        final tempDir = Directory.systemTemp.createTempSync(
          'gpu_probe_hang_test_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final zipPath = await runProbeOrchestrator(
          candidates: [hangingCandidate, okCandidate],
          context: const ProbeContext(
            referenceWavPath: '/fake/ref.wav',
            modelPath: '/fake/model.bin',
            workDir: '/tmp',
            timeout: _tinyDeadline,
          ),
          outputDir: tempDir.path,
          version: '0.0.0-test',
        );

        // Both candidates must have been called.
        expect(hangingCandidate.runCount, equals(1));
        expect(okCandidate.runCount, equals(1));

        // The zip must exist — orchestrator completed fully.
        expect(File(zipPath).existsSync(), isTrue);

        // The hanging candidate should be classified as hung.
        expect(hangingCandidate.lastOutcome, equals(Outcome.hung));

        // The ok candidate result must be ok.
        expect(okCandidate.lastOutcome, equals(Outcome.ok));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC5: Named constants are present and have sensible defaults
  // ---------------------------------------------------------------------------

  group('Named constants (AC5)', () {
    test('kProbeStartupDeadline is positive', () {
      expect(kProbeStartupDeadline.inSeconds, greaterThan(0));
    });

    test('kProbeHeartbeatTimeout is positive', () {
      expect(kProbeHeartbeatTimeout.inSeconds, greaterThan(0));
    });

    test('kProbeHeartbeatTimeout is shorter than kProbeStartupDeadline', () {
      expect(
        kProbeHeartbeatTimeout.inMilliseconds,
        lessThan(kProbeStartupDeadline.inMilliseconds),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // stderr tail capture
  // ---------------------------------------------------------------------------

  group('ProbeRunner — stderr tail', () {
    test('stderr lines are captured in stderrTail', () async {
      final fake = _FakeProcess();

      // Emit two stderr lines then close the stream, then exit.
      final stderrCtrl = StreamController<String>();
      stderrCtrl.add('error line 1');
      stderrCtrl.add('error line 2');
      stderrCtrl.close();
      fake.complete(1);

      final runner = ProbeRunner(
        launcher: (_, _, _) async => ProcessStartResult(
          process: fake,
          stdout: const Stream.empty(),
          stderr: stderrCtrl.stream,
        ),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final result = await runner.run(
        executable: 'fake',
        arguments: [],
        workingDirectory: '/tmp',
      );

      expect(result.stderrTail, contains('error line 1'));
      expect(result.stderrTail, contains('error line 2'));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers used by AC4
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] backed by a real [ProbeRunner].
///
/// Feeds the runner output into [classifyOutcome] and records the outcome.
class _RunnerBackedCandidate implements ProbeCandidate {
  _RunnerBackedCandidate({required this.candidateId, required this.runner});

  final ProbeRunner runner;
  int runCount = 0;
  Outcome? lastOutcome;

  @override
  String get id => candidateId;
  final String candidateId;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    runCount++;
    final result = await runner.run(
      executable: 'fake-engine',
      arguments: [],
      workingDirectory: ctx.workDir,
    );

    final outcome = classifyOutcome(
      exitCode: result.exitCode,
      timedOut: result.timedOut,
      transcript: '',
      detectedLanguage: null,
      expectedLanguage: ctx.language,
      wer: null,
    );
    lastOutcome = outcome;

    return CandidateResult(
      candidateId: id,
      outcome: outcome,
      durationMs: result.durationMs,
      exitCode: result.exitCode,
      stderrTail: result.stderrTail,
      errorDetail: result.timedOut ? 'timed out' : null,
    );
  }
}

/// Simple always-ok fake candidate (mirrors orchestrator test).
class _FakeOkCandidate implements ProbeCandidate {
  int runCount = 0;
  Outcome lastOutcome = Outcome.ok;

  @override
  String get id => 'fake-ok';

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    runCount++;
    return const CandidateResult(
      candidateId: 'fake-ok',
      outcome: Outcome.ok,
      durationMs: 1,
      transcribedText: 'hallo welt',
    );
  }
}

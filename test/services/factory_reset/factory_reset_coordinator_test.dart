/// Unit tests for [FactoryResetCoordinator].
///
/// Covers the four cases enumerated in
/// `.scratch/reliability-sprint/issues/06-feat-factory-reset-coordinator.md`:
///   1. Happy path — exact phase sequence, all configured directories
///      empty afterwards.
///   2. Subprocess exits cleanly within 500 ms of `kill()` — no
///      `forceKill` (SIGKILL / taskkill /F) fires.
///   3. Subprocess hangs past the configured stop-timeout — `forceKill`
///      fires and the stream advances to `deletingModels`.
///   4. A delete phase throws — stream emits `failed`, the
///      `CrashReporter.captureError` sink is invoked with the
///      `factory-reset-failed` fingerprint.
///
/// Test seam recap (mirrors the PRD design):
/// - In-memory filesystem via `package:file` MemoryFileSystem so the
///   model + logs directories can be populated, deleted, and inspected
///   without touching the host disk.
/// - Hand-driven `_FakeSubprocessController` that lets each scenario
///   decide when `waitForExit` returns true vs false — no real process
///   is spawned. This is the same seam pattern used by the existing
///   `sqlite_write_coordinator_test.dart` for the crash-capture sink.
/// - The directory deleter is overridden to a synchronous in-memory
///   delete so phase advancement is deterministic. `Isolate.run` cannot
///   be used in the `flutter_test` runner because it cannot route
///   service-binding messages — this is the same reason
///   `http_stall_detector_test.dart` injects its own timing.
library;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/services/factory_reset/factory_reset_coordinator.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Hand-driven [SubprocessController]. Each scenario configures
/// [waitForExitResults] (or [waitForExitFn]) to model whether the
/// subprocess exited within the budget.
class _FakeSubprocessController implements SubprocessController {
  _FakeSubprocessController({
    this.waitForExitResults = const <bool>[true],
    this.waitForExitFn,
  });

  /// Successive boolean outcomes returned by [waitForExit]. Consumed in
  /// order; if exhausted, the last value repeats. The default is `[true]`
  /// (clean exit on first poll). Ignored when [waitForExitFn] is set.
  final List<bool> waitForExitResults;

  /// Optional override — if provided, [waitForExit] delegates to this
  /// function instead of consuming from [waitForExitResults]. Useful for
  /// scenarios that need to assert on the [timeout] argument.
  final Future<bool> Function(Duration timeout)? waitForExitFn;

  int killCallCount = 0;
  int forceKillCallCount = 0;
  final List<Duration> waitForExitTimeouts = <Duration>[];
  int _waitForExitIndex = 0;

  @override
  Future<void> kill() async {
    killCallCount++;
  }

  @override
  Future<bool> waitForExit({required Duration timeout}) async {
    waitForExitTimeouts.add(timeout);
    if (waitForExitFn != null) {
      return waitForExitFn!(timeout);
    }
    if (waitForExitResults.isEmpty) return true;
    final i = _waitForExitIndex < waitForExitResults.length
        ? _waitForExitIndex
        : waitForExitResults.length - 1;
    _waitForExitIndex++;
    return waitForExitResults[i];
  }

  @override
  Future<void> forceKill() async {
    forceKillCallCount++;
  }
}

/// Records every [CrashCaptureSink] invocation.
class _RecordingCaptureSink {
  final List<_CapturedEvent> events = <_CapturedEvent>[];

  void call({
    required String message,
    required List<String> fingerprint,
    Object? error,
    StackTrace? stackTrace,
  }) {
    events.add(
      _CapturedEvent(
        message: message,
        fingerprint: List<String>.unmodifiable(fingerprint),
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

class _CapturedEvent {
  _CapturedEvent({
    required this.message,
    required this.fingerprint,
    required this.error,
    required this.stackTrace,
  });
  final String message;
  final List<String> fingerprint;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Builds a directory deleter that runs `deleteSync(recursive: true)`
/// against [fs]. The production deleter uses `Isolate.run`, which is
/// not viable in `flutter_test` — see file header.
Future<void> Function(String path) _memoryDeleter(FileSystem fs) {
  return (path) async {
    final dir = fs.directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  };
}

/// Convenience: pre-populate [fs] with a couple of model/log files so
/// the post-condition assertions on "directory is gone" are meaningful.
Future<void> _seedDirectories(
  FileSystem fs, {
  required String modelDir,
  required String logsDir,
}) async {
  final m = fs.directory(modelDir);
  await m.create(recursive: true);
  await fs.file('$modelDir/ggml-small-q5_1.bin').writeAsString('fake-model');
  await fs.file('$modelDir/whisper-server').writeAsString('fake-binary');
  final l = fs.directory(logsDir);
  await l.create(recursive: true);
  await fs.file('$logsDir/app.log').writeAsString('log line\n');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MemoryFileSystem fs;
  const modelDir = '/app/models/stt';
  const logsDir = '/app/logs';

  setUp(() {
    fs = MemoryFileSystem.test();
  });

  group('FactoryResetCoordinator — happy path', () {
    test(
      'emits the full phase sequence and clears the configured dirs',
      () async {
        await _seedDirectories(fs, modelDir: modelDir, logsDir: logsDir);

        final subprocess = _FakeSubprocessController(
          waitForExitResults: const <bool>[true],
        );
        var dbErased = false;
        var secureErased = false;
        var settingsReset = false;
        final coordinator = FactoryResetCoordinator(
          subprocess: subprocess,
          modelDirPath: modelDir,
          logsDirPath: logsDir,
          fileSystem: fs,
          directoryDeleter: _memoryDeleter(fs),
          eraseDatabase: () async {
            dbErased = true;
          },
          eraseSecureStore: () async {
            secureErased = true;
          },
          resetSettings: () async {
            settingsReset = true;
          },
        );

        final phases = <ResetPhase>[];
        await for (final phase in coordinator.run()) {
          phases.add(phase);
        }

        expect(phases, <ResetPhase>[
          ResetPhase.stoppingSubprocess,
          ResetPhase.deletingModels,
          ResetPhase.deletingDatabase,
          ResetPhase.resettingSecureStore,
          ResetPhase.resettingSettings,
          ResetPhase.done,
        ], reason: 'exact PRD-specified phase sequence');

        // Directories actually went away (not just the contents).
        expect(
          await fs.directory(modelDir).exists(),
          isFalse,
          reason: 'model dir must be removed',
        );
        expect(
          await fs.directory(logsDir).exists(),
          isFalse,
          reason: 'logs dir must be removed',
        );

        // Each non-FS collaborator was invoked exactly once.
        expect(subprocess.killCallCount, 1);
        expect(
          subprocess.forceKillCallCount,
          0,
          reason: 'no force-kill on clean exit',
        );
        expect(dbErased, isTrue);
        expect(secureErased, isTrue);
        expect(settingsReset, isTrue);
      },
    );
  });

  group('FactoryResetCoordinator — subprocess stop', () {
    test('clean exit within 500 ms does not invoke forceKill', () async {
      // Simulate a quick exit: waitForExit returns true on first call.
      final subprocess = _FakeSubprocessController(
        waitForExitFn: (timeout) async {
          // Pretend the subprocess exited 200 ms in — way under the
          // 500 ms scenario budget and the default 10 s stop timeout.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return true;
        },
      );
      await _seedDirectories(fs, modelDir: modelDir, logsDir: logsDir);

      final coordinator = FactoryResetCoordinator(
        subprocess: subprocess,
        modelDirPath: modelDir,
        logsDirPath: logsDir,
        fileSystem: fs,
        directoryDeleter: _memoryDeleter(fs),
        eraseDatabase: () async {},
        eraseSecureStore: () async {},
        resetSettings: () async {},
        // Tight stop-timeout to keep the test fast — production uses 10 s.
        stopSubprocessTimeout: const Duration(milliseconds: 500),
      );

      final phases = await coordinator.run().toList();

      expect(phases.last, ResetPhase.done);
      expect(subprocess.killCallCount, 1);
      expect(
        subprocess.forceKillCallCount,
        0,
        reason: 'clean exit must not trigger SIGKILL / taskkill /F',
      );
    });

    test('hang past stop-timeout triggers forceKill and stream continues '
        'into deletingModels', () async {
      // Subprocess never exits — every waitForExit poll returns false.
      final subprocess = _FakeSubprocessController(
        waitForExitFn: (timeout) async => false,
      );
      await _seedDirectories(fs, modelDir: modelDir, logsDir: logsDir);

      final coordinator = FactoryResetCoordinator(
        subprocess: subprocess,
        modelDirPath: modelDir,
        logsDirPath: logsDir,
        fileSystem: fs,
        directoryDeleter: _memoryDeleter(fs),
        eraseDatabase: () async {},
        eraseSecureStore: () async {},
        resetSettings: () async {},
        // 50 ms timeout so the hang-path test runs quickly. The PRD
        // production value is 10 s but the *behaviour* under timeout is
        // what is being asserted here, not the exact duration.
        stopSubprocessTimeout: const Duration(milliseconds: 50),
      );

      final phases = await coordinator.run().toList();

      expect(subprocess.killCallCount, 1);
      expect(
        subprocess.forceKillCallCount,
        1,
        reason:
            'after waitForExit reports the subprocess hangs, the coordinator '
            'must invoke the platform-specific hard kill (SIGKILL on Unix, '
            '`taskkill /F` on Windows) before advancing.',
      );
      // The stop-timeout argument forwarded to the fake is the configured
      // one — encodes the contract that the coordinator does not silently
      // alter the budget.
      expect(
        subprocess.waitForExitTimeouts.single,
        const Duration(milliseconds: 50),
      );
      // Stream advanced past the subprocess phase — the failed-path is
      // not entered just because the cooperative stop was insufficient.
      expect(phases, contains(ResetPhase.deletingModels));
      expect(phases.last, ResetPhase.done);
    });
  });

  group('FactoryResetCoordinator — failure path', () {
    test('a throwing delete phase emits failed and captures via the '
        'factory-reset-failed fingerprint', () async {
      await _seedDirectories(fs, modelDir: modelDir, logsDir: logsDir);

      final subprocess = _FakeSubprocessController(
        waitForExitResults: const <bool>[true],
      );
      final capture = _RecordingCaptureSink();
      final coordinator = FactoryResetCoordinator(
        subprocess: subprocess,
        modelDirPath: modelDir,
        logsDirPath: logsDir,
        fileSystem: fs,
        // Simulate the OS denying us the delete (permission denied,
        // file-locked, etc.). The deleter for the *model dir* throws;
        // every subsequent phase must be skipped.
        directoryDeleter: (path) async {
          if (path == modelDir) {
            throw const FileSystemException('permission denied', modelDir);
          }
          // Fallback for other paths (logs) — not reached because the
          // model-dir delete is attempted first.
          await fs.directory(path).delete(recursive: true);
        },
        eraseDatabase: () async {
          fail('eraseDatabase must not run after a deletingModels failure');
        },
        eraseSecureStore: () async {
          fail('eraseSecureStore must not run after a deletingModels failure');
        },
        resetSettings: () async {
          fail('resetSettings must not run after a deletingModels failure');
        },
        captureSink: capture.call,
      );

      final phases = await coordinator.run().toList();

      // The stream must terminate on `failed` and not on `done`.
      expect(phases.last, ResetPhase.failed);
      expect(phases, isNot(contains(ResetPhase.done)));
      // The phases up to (and including) the failing step are emitted.
      expect(phases, contains(ResetPhase.stoppingSubprocess));
      expect(phases, contains(ResetPhase.deletingModels));

      // Exactly one capture event, with the PRD-pinned fingerprint.
      expect(capture.events, hasLength(1));
      expect(capture.events.single.fingerprint, <String>[factoryResetFailed]);
      expect(capture.events.single.error, isA<FileSystemException>());
    });
  });
}

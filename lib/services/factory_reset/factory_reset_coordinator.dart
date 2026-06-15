/// Factory-reset coordinator — orchestrates the destructive cleanup that
/// the user triggers from the advanced settings section.
///
/// Why this module exists:
/// Before this coordinator, the factory-reset path in
/// `cloud_advanced_section.dart` performed a synchronous, blocking
/// sequence on the UI isolate:
///   1. Stopped the whisper-server subprocess.
///   2. Slept a fixed 800 ms — hoping the OS had released file handles.
///   3. Recursively `Directory.deleteSync(recursive: true)` of a model
///      directory that on a populated install easily reaches 1.5 GB.
///
/// On slower disks (the user "Idmir Junio" cluster), the freeze stretched
/// well past the OS responsiveness threshold, the user assumed the app
/// had crashed, force-quit it, and posted a 1★ store rating. See
/// `.scratch/reliability-sprint/prd.md` — Modul 4 for the full PRD and
/// fingerprint inventory.
///
/// Design contract:
/// - The coordinator is purely a `Stream<ResetPhase>` orchestrator. It
///   owns no Riverpod state, no UI dependencies, no global singletons.
/// - All side-effecting collaborators are injected via the constructor —
///   the production constructor wires the real defaults, tests inject
///   fakes (in-memory filesystem, hand-controlled subprocess, no-op
///   secure store, etc.).
/// - The stream emits **before** each phase's work begins. That way the
///   UI dialog renders the phase label first, and the user sees forward
///   progress instead of guessing whether the app is alive.
/// - If any phase throws, the coordinator emits [ResetPhase.failed],
///   captures one Sentry event under the [factoryResetFailed]
///   fingerprint, and closes the stream. The caller is responsible for
///   surfacing an actionable toast.
///
/// Subprocess-stop contract:
/// - The injected [SubprocessController.kill] is called first.
/// - The coordinator then polls [SubprocessController.waitForExit] until
///   either confirmed exit or [stopSubprocessTimeout] elapses. On
///   timeout, [SubprocessController.forceKill] is invoked as the
///   emergency brake (SIGKILL on Unix, `taskkill /F` on Windows).
/// - Only after a confirmed (or force-killed) exit does the coordinator
///   advance to [ResetPhase.deletingModels].
///
/// Directory-delete contract:
/// - Each large directory delete (STT model dir, logs dir) is dispatched
///   through the injected [DirectoryDeleter]. The production deleter
///   spawns the work into an `Isolate.run(...)` block so the UI isolate
///   stays responsive for animation frames during the multi-GB delete.
/// - In tests, the deleter runs synchronously against the injected
///   [FileSystem] (typically `MemoryFileSystem`) — `Isolate.run` is a
///   no-go in a `flutter_test` runner anyway because it cannot route
///   service-binding messages.
library;

import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../core/logging/crash_reporter.dart';

final _log = AppLogger('FactoryResetCoordinator');

// ---------------------------------------------------------------------------
// Public phase enum — order matches the PRD-specified happy-path sequence.
// ---------------------------------------------------------------------------

/// Lifecycle phases emitted by [FactoryResetCoordinator.run].
///
/// Order is meaningful: the happy path emits the first five values in
/// declaration order, then [done]. [failed] is mutually exclusive with
/// [done] — the coordinator emits exactly one terminal value.
enum ResetPhase {
  stoppingSubprocess,
  deletingModels,
  deletingDatabase,
  resettingSecureStore,
  resettingSettings,
  done,
  failed,
}

// ---------------------------------------------------------------------------
// Injection seams
// ---------------------------------------------------------------------------

/// Abstraction over the whisper-server subprocess lifecycle, narrowed to
/// the four operations the coordinator needs.
///
/// The production implementation wraps the [SubprocessGuardController] and
/// reads the `.whisper-server.pid` file. Tests inject a hand-driven fake
/// (see `test/services/factory_reset/factory_reset_coordinator_test.dart`)
/// that lets each scenario decide when the subprocess exits — so the
/// SIGKILL fallback path is exercised without spawning a real process.
abstract class SubprocessController {
  /// Send the cooperative stop signal (graceful shutdown on the server).
  Future<void> kill();

  /// Returns `true` if the subprocess has exited within [timeout],
  /// `false` otherwise. The coordinator polls this method during
  /// [ResetPhase.stoppingSubprocess].
  ///
  /// Implementations should poll on a short tick (~100 ms) and resolve
  /// immediately upon observing exit. The poll budget is bounded by
  /// [timeout].
  Future<bool> waitForExit({required Duration timeout});

  /// Emergency brake — fired when [waitForExit] returns `false`.
  /// On Unix this is `Process.killPid(pid, ProcessSignal.sigkill)`; on
  /// Windows it is `taskkill /F /PID <pid>`.
  Future<void> forceKill();
}

/// Signature for the per-directory deleter. Production routes through an
/// `Isolate.run` so the UI isolate is not blocked by recursive
/// directory deletion. The injected variant in tests typically calls
/// `Directory.deleteSync(recursive: true)` against the in-memory FS.
typedef DirectoryDeleter = Future<void> Function(String path);

/// Signature for the database-deletion step. The production wiring
/// deletes the Drift database file plus its WAL/SHM siblings; tests
/// inject a no-op or a spy.
typedef DatabaseEraser = Future<void> Function();

/// Signature for the secure-store cleanup step. Production iterates
/// the API-key mapping and calls `deleteKey` for each entry.
typedef SecureStoreEraser = Future<void> Function();

/// Signature for the in-memory settings reset (final step). Production
/// invokes `settingsProvider.notifier.factoryResetInMemory()`-style
/// state-reset.
typedef SettingsReset = Future<void> Function();

/// Signature for the Sentry capture sink. Defaults to the live
/// `CrashReporter` singleton; tests pass a recorder.
///
/// Mirrors the [CrashCaptureSink] in `sqlite_write_coordinator.dart` —
/// kept as a local typedef rather than imported to keep the modules
/// independently testable.
typedef CrashCaptureSink =
    void Function({
      required String message,
      required List<String> fingerprint,
      Object? error,
      StackTrace? stackTrace,
    });

// ---------------------------------------------------------------------------
// Coordinator
// ---------------------------------------------------------------------------

/// Default subprocess-stop timeout: 10 s as specified by the PRD.
const Duration kDefaultStopSubprocessTimeout = Duration(seconds: 10);

/// Default poll interval used by the production [SubprocessController] —
/// re-exported as a constant so the production wrapper can share it.
const Duration kDefaultSubprocessPollInterval = Duration(milliseconds: 100);

/// Orchestrates the factory-reset lifecycle as a `Stream<ResetPhase>`.
///
/// Construct one instance per reset attempt. Re-running the same
/// instance twice is undefined behaviour — callers create a fresh
/// coordinator for each user trigger.
class FactoryResetCoordinator {
  /// Production constructor — wires the real filesystem, the real
  /// `Isolate.run`-backed deleter, and the live [CrashReporter].
  ///
  /// All other collaborators ([_subprocess], [_eraseDatabase],
  /// [_eraseSecureStore], [_resetSettings], and the directory paths) are
  /// required because they encode application-specific intent
  /// (which subprocess, which DB file, which secure-store provider,
  /// which settings notifier).
  FactoryResetCoordinator({
    required this._subprocess,
    required this.modelDirPath,
    required this.logsDirPath,
    required this._eraseDatabase,
    required this._eraseSecureStore,
    required this._resetSettings,
    this._stopSubprocessTimeout = kDefaultStopSubprocessTimeout,
    FileSystem? fileSystem,
    DirectoryDeleter? directoryDeleter,
    CrashCaptureSink? captureSink,
  }) : _fileSystem = fileSystem ?? const LocalFileSystem(),
       _directoryDeleter = directoryDeleter ?? _isolateDirectoryDeleter,
       _capture = captureSink ?? _defaultCaptureSink;

  // ---------------------------------------------------------------------------
  // Injected collaborators
  // ---------------------------------------------------------------------------

  final SubprocessController _subprocess;
  final Duration _stopSubprocessTimeout;
  final FileSystem _fileSystem;
  final DirectoryDeleter _directoryDeleter;
  final DatabaseEraser _eraseDatabase;
  final SecureStoreEraser _eraseSecureStore;
  final SettingsReset _resetSettings;
  final CrashCaptureSink _capture;

  // ---------------------------------------------------------------------------
  // Configured paths (public so tests can assert post-conditions)
  // ---------------------------------------------------------------------------

  /// Absolute path to the directory containing downloaded STT models and
  /// the whisper-server binary. Wiped during [ResetPhase.deletingModels].
  final String modelDirPath;

  /// Absolute path to the app logs directory. Wiped during
  /// [ResetPhase.deletingModels] alongside [modelDirPath].
  final String logsDirPath;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Runs the reset and returns a `Stream<ResetPhase>` that emits each
  /// phase as it begins.
  ///
  /// The stream is single-subscription. On the happy path it emits the
  /// six values `stoppingSubprocess → deletingModels → deletingDatabase
  /// → resettingSecureStore → resettingSettings → done` and closes.
  /// On any phase throwing, the stream emits [ResetPhase.failed] (one
  /// final value) and closes — the underlying exception is captured to
  /// Sentry under the [factoryResetFailed] fingerprint but is **not**
  /// rethrown into the stream, so the UI dialog can render the failed
  /// phase without needing a try/catch around the listener.
  Stream<ResetPhase> run() async* {
    try {
      // Phase 1 — stop subprocess, wait for actual exit.
      yield ResetPhase.stoppingSubprocess;
      await _stopSubprocessWithBackstop();

      // Phase 2 — wipe model directory + logs (the large I/O work).
      yield ResetPhase.deletingModels;
      await _deleteIfExists(modelDirPath);
      await _deleteIfExists(logsDirPath);

      // Phase 3 — drop the history database file.
      yield ResetPhase.deletingDatabase;
      await _eraseDatabase();

      // Phase 4 — clear secure-store credentials.
      yield ResetPhase.resettingSecureStore;
      await _eraseSecureStore();

      // Phase 5 — reset in-memory settings (triggers onboarding re-entry
      // via `onboardingCompleted = false`).
      yield ResetPhase.resettingSettings;
      await _resetSettings();

      // Terminal — done.
      yield ResetPhase.done;
    } catch (error, stackTrace) {
      _capture(
        message: 'Factory reset failed',
        fingerprint: const <String>[factoryResetFailed],
        error: error,
        stackTrace: stackTrace,
      );
      yield ResetPhase.failed;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _stopSubprocessWithBackstop() async {
    await _subprocess.kill();
    final exitedCleanly = await _subprocess.waitForExit(
      timeout: _stopSubprocessTimeout,
    );
    if (!exitedCleanly) {
      // Emergency brake — the subprocess did not honour the cooperative
      // kill within the budget. Fire the platform-specific hard kill.
      await _subprocess.forceKill();
    }
  }

  Future<void> _deleteIfExists(String path) async {
    final dir = _fileSystem.directory(path);
    if (!await dir.exists()) return;
    await _directoryDeleter(path);
  }
}

// ---------------------------------------------------------------------------
// Production default — isolate-backed directory deleter.
// ---------------------------------------------------------------------------

/// Default [DirectoryDeleter] used in production: runs the recursive
/// delete in a fresh isolate so the UI thread is not blocked for the
/// hundreds of milliseconds to seconds the recursive walk can take on a
/// populated STT directory.
///
/// We intentionally use `dart:io.Directory` here (not the injected
/// `package:file` filesystem) because `Isolate.run` cannot capture the
/// `_LocalFileSystem` instance across the isolate boundary cleanly and
/// the production path only ever needs the real filesystem.
Future<void> _isolateDirectoryDeleter(String path) {
  return Isolate.run<void>(() {
    final dir = io.Directory(path);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
}

// ---------------------------------------------------------------------------
// Production default — Sentry capture sink.
// ---------------------------------------------------------------------------

/// Forwards to the live [CrashReporter] singleton. Safe no-op when
/// `CrashReporter.instance` is null (e.g. unit-test bootstrap without
/// `CrashReporter.init()`). Mirrors the analogous sink in
/// `sqlite_write_coordinator.dart`.
void _defaultCaptureSink({
  required String message,
  required List<String> fingerprint,
  Object? error,
  StackTrace? stackTrace,
}) {
  CrashReporter.instance?.captureError(
    message: message,
    fingerprint: fingerprint,
    error: error,
    stackTrace: stackTrace,
  );
}

// ---------------------------------------------------------------------------
// Production factory — wires the real whisper-server subprocess.
// ---------------------------------------------------------------------------

/// Builds the production [SubprocessController] that talks to the
/// real whisper-server via:
/// - a cooperative `stopFn` (typically the existing
///   `localSttBundleProvider.notifier.stop()` hook) for [kill],
/// - PID-file polling of `<appDataDir>/.whisper-server.pid` for
///   [waitForExit], and
/// - `Process.killPid(pid, ProcessSignal.sigkill)` (Unix) /
///   `taskkill /F /PID <pid>` (Windows) for [forceKill].
///
/// The PID file is written by `SubprocessGuard.writePid` (see
/// `lib/services/subprocess_guard.dart`) when the whisper-server is
/// spawned, and deleted by `SubprocessGuard.deletePid` on graceful stop.
/// The presence/absence of the file is therefore an accurate proxy for
/// "is the subprocess still running" — exactly the signal we need.
class WhisperServerSubprocessController implements SubprocessController {
  WhisperServerSubprocessController({
    required this.pidFilePath,
    required this._cooperativeStop,
    this._pollInterval = kDefaultSubprocessPollInterval,
  });

  /// Absolute path to `.whisper-server.pid` (under the app data dir).
  final String pidFilePath;

  final Future<void> Function() _cooperativeStop;
  final Duration _pollInterval;

  /// PID captured from the file at the time of [kill] so that
  /// [forceKill] knows which process to target even after the file
  /// has been cleaned up.
  int? _capturedPid;

  @override
  Future<void> kill() async {
    _capturedPid = _readPid();
    await _cooperativeStop();
  }

  @override
  Future<bool> waitForExit({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_pidFileExists()) return true;
      await Future<void>.delayed(_pollInterval);
    }
    return !_pidFileExists();
  }

  @override
  Future<void> forceKill() async {
    final pid = _capturedPid;
    if (pid == null || pid <= 0) return;
    try {
      if (io.Platform.isWindows) {
        await io.Process.run('taskkill', ['/F', '/PID', '$pid']);
      } else {
        io.Process.killPid(pid, io.ProcessSignal.sigkill);
      }
    } catch (e, st) {
      // Best-effort — the goal is to free the file handles, and if
      // the OS reports "no such process" the goal is already met.
      _log.debug('forceKill failed (process may have already exited)', e, st);
    }
  }

  bool _pidFileExists() {
    try {
      return io.File(pidFilePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  int? _readPid() {
    try {
      final file = io.File(pidFilePath);
      if (!file.existsSync()) return null;
      return int.tryParse(file.readAsStringSync().trim());
    } catch (_) {
      return null;
    }
  }
}

/// Convenience builder for the production model/logs paths.
///
/// Centralises the "where do the deleted directories live" decision so
/// the wiring code in `cloud_advanced_section.dart` does not duplicate
/// the path layout. The caller passes `appDataDir()` and `sttDir()`
/// from `lib/services/path_service.dart`.
String defaultLogsDirPath(String appDataDir) => p.join(appDataDir, 'logs');

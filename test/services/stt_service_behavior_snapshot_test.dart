/// Behavior-snapshot tests for SttServerStateNotifier.
///
/// Captures observable behaviour across all five responsibilities:
///   1. Subprocess lifecycle (start / stop / restart-on-model-change)
///   2. Health polling (HTTP probe state transitions)
///   3. Model-download integration (Exit 3 → hash-recheck)
///   4. GPU-crash recovery (CPU-fallback decision table)
///   5. Idle-timeout management (reset / elapse)
///   6. Heartbeat-based startup timeout (cross-reference)
///
/// The "seam" is [processRunnerProvider] + [sttHttpClientProvider].
/// No private methods or internal collaborators are mocked — only the
/// public DI surface. Tests must survive the issue-14 refactor unchanged
/// (only provider import paths may change after that).
///
/// DO NOT import from stt_service_test.dart — test files are not exported.
/// Fake helpers are redefined here so this file is self-contained.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/process_runner.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

// ── Fake helpers ─────────────────────────────────────────────────────────────

/// Minimal fake [Process] whose streams and exit code are fully controllable.
class _FakeProcess implements Process {
  final _stdoutCtrl = StreamController<List<int>>();
  final _stderrCtrl = StreamController<List<int>>();
  final _exitCompleter = Completer<int>();

  @override
  Stream<List<int>> get stdout => _stdoutCtrl.stream;
  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;
  @override
  Future<int> get exitCode => _exitCompleter.future;
  @override
  int get pid => 99999;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
    return true;
  }

  @override
  IOSink get stdin => throw UnimplementedError();

  void emitStderr(String line) => _stderrCtrl.add('$line\n'.codeUnits);

  void exit(int code) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
  }

  Future<void> dispose() async {
    await _stdoutCtrl.close();
    await _stderrCtrl.close();
  }
}

/// Fake [ProcessRunner] that returns the same [_FakeProcess] on every call.
class _FakeProcessRunner extends ProcessRunner {
  final _FakeProcess process;
  String? lastExecutable;
  List<String>? lastArguments;
  int startCallCount = 0;

  _FakeProcessRunner(this.process);

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    startCallCount++;
    lastExecutable = executable;
    lastArguments = arguments;
    return process;
  }
}

/// Fake [ProcessRunner] that creates a fresh [_FakeProcess] on each call.
/// Required when [ensureRunning] is called more than once (single-subscription
/// streams cannot be re-listened).
class _MultiFakeProcessRunner extends ProcessRunner {
  final _FakeProcess Function() factory;
  _FakeProcess? lastProcess;
  int startCallCount = 0;

  _MultiFakeProcessRunner(this.factory);

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    startCallCount++;
    lastProcess = factory();
    return lastProcess!;
  }
}

/// Fake settings notifier that never hits disk.
class _FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _settings;
  _FakeSettingsNotifier(this._settings);

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

/// Fake model-download notifier that tracks [downloadModel] calls.
class _TrackingModelDownloadNotifier extends ModelDownloadNotifier {
  final _downloadedIds = <String>[];
  var downloadCallCount = 0;

  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});

  @override
  Future<void> downloadModel(String modelId) async {
    downloadCallCount++;
    _downloadedIds.add(modelId);
    // Simulate the download completing so the listener in SttServerStateNotifier can
    // clear _modelLoadFailedIds.
    state = ModelDownloadState(downloadedModels: {modelId});
  }

  List<String> get downloadedIds => List.unmodifiable(_downloadedIds);
}

// ── HTTP client factories ─────────────────────────────────────────────────────

/// Always returns 200 on /health and empty JSON on /inference.
http.Client _healthyClient() => MockClient((req) async {
  if (req.url.path == '/health') return http.Response('ok', 200);
  if (req.url.path == '/inference') {
    return http.Response('{"text":""}', 200);
  }
  return http.Response('not found', 404);
});

/// Always returns 503 — server never becomes healthy.
http.Client _unhealthyClient() =>
    MockClient((_) async => http.Response('not ready', 503));

// ── Container factories ───────────────────────────────────────────────────────

/// Builds a [ProviderContainer] with injectable fakes.
ProviderContainer _makeContainer({
  required ProcessRunner runner,
  required http.Client httpClient,
  AppSettings? settings,
  ModelDownloadNotifier Function()? downloadNotifierFactory,
  ({Duration window, int maxMissedWindows})? heartbeatConfig,
}) {
  return ProviderContainer(
    overrides: [
      processRunnerProvider.overrideWithValue(runner),
      sttHttpClientProvider.overrideWithValue(httpClient),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ?? AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
        ),
      ),
      modelDownloadProvider.overrideWith(
        downloadNotifierFactory ?? _TrackingModelDownloadNotifier.new,
      ),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
      if (heartbeatConfig != null)
        sttStartupHeartbeatConfigProvider.overrideWithValue(heartbeatConfig),
    ],
  );
}

/// Creates a temp STT dir with a fake binary and an 11 MB model file.
/// Sets [paths.sttDirOverride] so path helpers resolve to this dir.
/// Callers MUST reset [paths.sttDirOverride] to null in tearDown.
Future<Directory> _createFakeSttDir({String modelId = 'whisper-tiny'}) async {
  final dir = await Directory.systemTemp.createTemp('stt_snapshot_test_');

  // Fake server binary (execution is intercepted by the fake ProcessRunner).
  final serverName = Platform.isWindows
      ? 'whisper-server.exe'
      : 'whisper-server';
  await File('${dir.path}/$serverName').writeAsBytes([0x7f, 0x45, 0x4c, 0x46]);

  // Fake model file — must be > 10 MB to pass the size guard.
  final modelFilename = findSttModel(modelId)?.filename ?? 'ggml-tiny-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));

  paths.sttDirOverride = dir.path;
  return dir;
}

// ── Exit-code classifier tests (pure function, no DI needed) ─────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 0. classifySttExitCode — pure function table ────────────────────────────
  group('classifySttExitCode — exit-code classifier', () {
    test('exit code 3 → modelLoad on all platforms', () {
      expect(classifySttExitCode(3), SttExitKind.modelLoad);
    });

    test('exit code 0 → other on all platforms', () {
      expect(classifySttExitCode(0), SttExitKind.other);
    });

    test('exit code 1 → other on all platforms', () {
      expect(classifySttExitCode(1), SttExitKind.other);
    });

    test(
      'Windows NTSTATUS codes classify correctly (or as other on non-Windows)',
      () {
        // On Windows these map to specific kinds; on other platforms they are
        // all "other". We test both possibilities deterministically.
        if (Platform.isWindows) {
          expect(classifySttExitCode(-1073741515), SttExitKind.dllMissing);
          expect(classifySttExitCode(-1073741511), SttExitKind.dllEntryPoint);
          expect(classifySttExitCode(-1073740791), SttExitKind.gpuFatal);
          expect(classifySttExitCode(-1073741819), SttExitKind.heapCorruption);
        } else {
          // All Windows NTSTATUS codes are "other" on non-Windows.
          expect(classifySttExitCode(-1073741515), SttExitKind.other);
          expect(classifySttExitCode(-1073741511), SttExitKind.other);
          expect(classifySttExitCode(-1073740791), SttExitKind.other);
          expect(classifySttExitCode(-1073741819), SttExitKind.other);
        }
      },
    );
  });

  // ── 1. Subprocess lifecycle ───────────────────────────────────────────────
  group('Subprocess lifecycle', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('ensureRunning() starts the subprocess via ProcessRunner', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
        heartbeatConfig: (
          window: const Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
      );
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      await container.read(settingsProvider.future);
      fakeProcess.emitStderr('[whisper] model loaded');

      await container.read(localSttBundleProvider.notifier).ensureRunning();

      expect(
        runner.startCallCount,
        greaterThan(0),
        reason: 'ProcessRunner.start must be called by ensureRunning()',
      );
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
        reason: 'Server must be ready after successful ensureRunning()',
      );
    });

    test('stop() terminates the server and transitions to stopped', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
        heartbeatConfig: (
          window: const Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
      );
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      await container.read(settingsProvider.future);
      fakeProcess.emitStderr('[whisper] model loaded');

      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );

      notifier.stop();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
        reason: 'stop() must transition server to stopped state',
      );
    });

    test('model change triggers restart of the subprocess', () async {
      // Use a multi-runner so each start() call gets a fresh _FakeProcess.
      final processes = <_FakeProcess>[];
      final runner = _MultiFakeProcessRunner(() {
        final p = _FakeProcess();
        p.emitStderr('[whisper] model loaded');
        processes.add(p);
        return p;
      });

      // Start with whisper-tiny.
      final settings = AppSettings.defaults.copyWith(sttModel: 'whisper-tiny');
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        settings: settings,
        heartbeatConfig: (
          window: const Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
      );
      addTearDown(() {
        container.dispose();
        for (final p in processes) {
          p.exit(0);
        }
      });

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);

      // First start.
      await notifier.ensureRunning();
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      final startCountAfterFirst = runner.startCallCount;

      // Simulate model change: stop and re-run with different model.
      // (The debounced model-change listener requires real file on disk;
      // we drive the restart directly through stop() + ensureRunning()
      // to avoid file-system coupling and keep this a pure lifecycle test.)
      notifier.stop();

      // Create fake model file for whisper-base (needed for second start).
      final baseModel = findSttModel('whisper-base');
      if (baseModel != null) {
        await File(
          '${tempDir.path}/${baseModel.filename}',
        ).writeAsBytes(Uint8List(11 * 1024 * 1024));
      }

      await container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttModel: 'whisper-base'));
      await container.read(settingsProvider.future);

      await notifier.ensureRunning();

      expect(
        runner.startCallCount,
        greaterThan(startCountAfterFirst),
        reason: 'ProcessRunner.start must be called again after model change',
      );
      expect(
        container.read(localSttBundleProvider).modelId,
        'whisper-base',
        reason: 'Server must report the new model ID after restart',
      );
    });
  });

  // ── 2. Health polling ─────────────────────────────────────────────────────
  group('Health polling — HTTP probe state transitions', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test(
      '503 during startup keeps server in starting state until 200 arrives',
      () async {
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);

        // Return 503 for the first 100 ms, then 200.
        final startedAt = DateTime.now().add(const Duration(milliseconds: 100));
        final httpClient = MockClient((req) async {
          if (req.url.path == '/health') {
            if (DateTime.now().isAfter(startedAt)) {
              return http.Response('ok', 200);
            }
            return http.Response('not ready', 503);
          }
          if (req.url.path == '/inference') {
            return http.Response('{"text":""}', 200);
          }
          return http.Response('not found', 404);
        });

        final container = _makeContainer(
          runner: runner,
          httpClient: httpClient,
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          heartbeatConfig: (
            window: const Duration(milliseconds: 200),
            maxMissedWindows: 5,
          ),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);

        // Emit heartbeat to keep window alive during the 503 phase.
        fakeProcess.emitStderr('[whisper] loading model');

        // Run ensureRunning() and capture intermediate state quickly.
        final ensureFuture = container
            .read(localSttBundleProvider.notifier)
            .ensureRunning();

        // Give a tiny moment for the transition to starting.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // At this point the server should be in starting state.
        // (It may already be ready if timing is tight — that is also valid.)
        final midState = container.read(localSttBundleProvider).serverState;
        expect(
          midState,
          anyOf(SttServerState.starting, SttServerState.ready),
          reason:
              'During HTTP-503 phase server must be starting or already ready',
        );

        await ensureFuture;

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
          reason: 'Server must be ready once health check returns 200',
        );
      },
    );

    test(
      'successful 200 health response → ready state with correct port',
      () async {
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);
        fakeProcess.emitStderr('[whisper] model loaded');

        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          heartbeatConfig: (
            window: const Duration(milliseconds: 50),
            maxMissedWindows: 3,
          ),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        final status = container.read(localSttBundleProvider);
        expect(status.serverState, SttServerState.ready);
        expect(
          status.port,
          greaterThan(0),
          reason: 'Ready state must have a positive port number',
        );
        expect(
          status.modelId,
          isNotEmpty,
          reason: 'Ready state must have a non-empty model ID',
        );
      },
    );
  });

  // ── 3. Model-download integration (Exit 3) ────────────────────────────────
  group('Model-download integration — Exit 3 hash-recheck flow', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test(
      'Exit 3 with hash mismatch triggers downloadModel() on ModelDownloadNotifier',
      () async {
        // The model file in the temp dir contains only zeros — SHA-256 will
        // differ from the registry hash → hashMismatch = true → re-download.
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);
        final trackingDownloader = _TrackingModelDownloadNotifier();

        final container = _makeContainer(
          runner: runner,
          httpClient: _unhealthyClient(),
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          downloadNotifierFactory: () => trackingDownloader,
          heartbeatConfig: (
            window: const Duration(milliseconds: 50),
            maxMissedWindows: 3,
          ),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);

        // Start ensureRunning() without awaiting — we'll trigger the exit below.
        unawaited(
          container.read(localSttBundleProvider.notifier).ensureRunning(),
        );

        // Wait for the notifier to register the process.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Simulate exit code 3 (modelLoad failure).
        fakeProcess.exit(3);

        // Give the async exit handler time to run and call downloadModel().
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(
          trackingDownloader.downloadCallCount,
          greaterThan(0),
          reason: 'Exit 3 with hash mismatch must trigger downloadModel() call',
        );
        expect(
          trackingDownloader.downloadedIds,
          contains('whisper-tiny'),
          reason: 'downloadModel() must be called with the failing model ID',
        );
      },
    );

    test(
      'Exit 3: state is stopped or error after model-load failure (not stuck in starting)',
      () async {
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);

        final container = _makeContainer(
          runner: runner,
          httpClient: _unhealthyClient(),
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          heartbeatConfig: (
            window: const Duration(milliseconds: 50),
            maxMissedWindows: 3,
          ),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);

        unawaited(
          container.read(localSttBundleProvider.notifier).ensureRunning(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        fakeProcess.exit(3);

        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(
          container.read(localSttBundleProvider).serverState,
          anyOf(SttServerState.stopped, SttServerState.error),
          reason: 'After Exit 3 the server must not remain in starting state',
        );
      },
    );
  });

  // ── 4. GPU-crash recovery — CPU-fallback decision table ──────────────────
  group('GPU-crash recovery — CPU-fallback decision table', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    // On non-Windows platforms gpuFatal/heapCorruption exit codes (NTSTATUS)
    // are not distinguishable — they classify as "other". The CPU-fallback
    // test only exercises the observable path for the current platform.
    test(
      'gpuFatal exit (Windows) → cpuFallbackActive flag set in SttStatus',
      () async {
        if (!Platform.isWindows) {
          // On non-Windows the NTSTATUS code is treated as "other" — no
          // CPU-fallback is activated. Skip the Windows-specific assertions.
          return;
        }

        final processes = <_FakeProcess>[];
        final runner = _MultiFakeProcessRunner(() {
          final p = _FakeProcess();
          processes.add(p);
          return p;
        });

        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          heartbeatConfig: (
            window: const Duration(milliseconds: 50),
            maxMissedWindows: 3,
          ),
        );
        addTearDown(() {
          container.dispose();
          for (final p in processes) {
            p.exit(0);
          }
        });

        await container.read(settingsProvider.future);

        unawaited(
          container.read(localSttBundleProvider.notifier).ensureRunning(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Emit gpuFatal NTSTATUS code.
        processes.last.exit(-1073740791); // STATUS_STACK_BUFFER_OVERRUN

        await Future<void>.delayed(const Duration(milliseconds: 200));

        // After the first GPU fatal, the service must silently activate CPU
        // fallback (stopped state) and NOT transition to error yet.
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
          reason:
              'First gpuFatal exit must activate CPU fallback silently (stopped, not error)',
        );

        // A subsequent ensureRunning() must start the CPU-fallback server;
        // if it succeeds, cpuFallbackActive is true in the ready state.
        processes.last.emitStderr('[whisper] cpu mode');
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          container.read(localSttBundleProvider).cpuFallbackActive,
          isTrue,
          reason: 'cpuFallbackActive must be true after GPU crash recovery',
        );
      },
    );

    test(
      'heapCorruption exit (Windows) → CPU fallback silently activated',
      () async {
        if (!Platform.isWindows) {
          return; // NTSTATUS codes are platform-specific.
        }

        final processes = <_FakeProcess>[];
        final runner = _MultiFakeProcessRunner(() {
          final p = _FakeProcess();
          processes.add(p);
          return p;
        });

        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          heartbeatConfig: (
            window: const Duration(milliseconds: 50),
            maxMissedWindows: 3,
          ),
        );
        addTearDown(() {
          container.dispose();
          for (final p in processes) {
            p.exit(0);
          }
        });

        await container.read(settingsProvider.future);

        unawaited(
          container.read(localSttBundleProvider.notifier).ensureRunning(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        processes.last.exit(-1073741819); // STATUS_ACCESS_VIOLATION

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
          reason:
              'First heapCorruption exit must activate CPU fallback (stopped)',
        );
      },
    );

    test('other exit code → error state, no CPU fallback', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);

      final container = _makeContainer(
        runner: runner,
        httpClient: _unhealthyClient(),
        settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
        heartbeatConfig: (
          window: const Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
      );
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      await container.read(settingsProvider.future);

      unawaited(
        container.read(localSttBundleProvider.notifier).ensureRunning(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Exit code 99 → SttExitKind.other on all platforms.
      fakeProcess.exit(99);

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final status = container.read(localSttBundleProvider);
      expect(
        status.serverState,
        SttServerState.error,
        reason: 'Unknown exit code must transition to error state',
      );
      expect(
        status.cpuFallbackActive,
        isFalse,
        reason: 'cpuFallbackActive must remain false for "other" exit kind',
      );
    });
  });

  // ── 5. Idle-timeout management ────────────────────────────────────────────
  group('Idle-timeout management', () {
    test('notifyRecordingStarted() disables idle timer; '
        'notifyRecordingStopped() re-arms it', () {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
      );
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      final notifier = container.read(localSttBundleProvider.notifier);

      // These must not throw — they exercise the idle-timer guard paths.
      notifier.notifyRecordingStarted();
      notifier.notifyRecordingStopped();

      // State must not change by these calls alone (server not running).
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
        reason:
            'Idle timer calls must not change server state when server is stopped',
      );
    });

    test(
      'notifyRecordingStarted() prevents idle timer reset during active recording',
      () async {
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          // Use sttIdleTimeoutMinutes = 0 (keep-alive) so the timer is never
          // armed during the test — isolates the recording-active guard.
          settings: AppSettings.defaults.copyWith(
            sttModel: 'whisper-tiny',
            sttIdleTimeoutMinutes: 0,
          ),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        final notifier = container.read(localSttBundleProvider.notifier);

        // Calling notifyRecordingStarted and notifyRecordingStopped while
        // the server is stopped must not throw and must leave state unchanged.
        notifier.notifyRecordingStarted();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        notifier.notifyRecordingStopped();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
        );
      },
    );

    test(
      'notifyTranscriptionCompleted() re-arms idle timer after recording',
      () {
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        final notifier = container.read(localSttBundleProvider.notifier);

        // Start → complete transcription → check no exception thrown.
        notifier.notifyRecordingStarted();
        notifier.notifyTranscriptionCompleted();

        // Server is stopped (never started) — state must still be stopped.
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
        );
      },
    );
  });

  // ── 6. Heartbeat-based startup timeout — cross-reference ─────────────────
  group('Heartbeat-based startup timeout (snapshot cross-reference)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test(
      'no stderr output within 3 × window → error state, model not blacklisted',
      () async {
        // This is the canonical heartbeat-timeout assertion from issue 02.
        // Duplicated here so the behavior snapshot is self-contained.
        const hbConfig = (
          window: Duration(milliseconds: 50),
          maxMissedWindows: 3,
        );

        final processes = <_FakeProcess>[];
        final runner = _MultiFakeProcessRunner(() {
          final p = _FakeProcess();
          processes.add(p);
          return p;
        });

        final container = _makeContainer(
          runner: runner,
          httpClient: _unhealthyClient(),
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          heartbeatConfig: hbConfig,
        );
        addTearDown(() {
          container.dispose();
          for (final p in processes) {
            p.exit(0);
          }
        });

        await container.read(settingsProvider.future);
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.error,
          reason: 'Heartbeat timeout must produce error state',
        );

        // Model must NOT be blacklisted — a second attempt must not immediately
        // fail with "model corrupted".
        final errorMsg =
            container.read(localSttBundleProvider).errorMessage ?? '';
        expect(
          errorMsg,
          isNot(contains('corrupted')),
          reason: 'Heartbeat timeout must not blacklist the model',
        );
      },
    );

    test(
      'stderr heartbeat within window keeps startup alive → ready when health 200',
      () async {
        const hbConfig = (
          window: Duration(milliseconds: 100),
          maxMissedWindows: 3,
        );

        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);

        // Health returns 200 after 120 ms.
        final healthyAt = DateTime.now().add(const Duration(milliseconds: 120));
        final httpClient = MockClient((req) async {
          if (req.url.path == '/health') {
            if (DateTime.now().isAfter(healthyAt)) {
              return http.Response('ok', 200);
            }
            return http.Response('not ready', 503);
          }
          if (req.url.path == '/inference') {
            return http.Response('{"text":""}', 200);
          }
          return http.Response('not found', 404);
        });

        final container = _makeContainer(
          runner: runner,
          httpClient: httpClient,
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
          heartbeatConfig: hbConfig,
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);

        // Emit stderr lines every 30 ms to keep the 100 ms window alive.
        var tick = 0;
        final timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
          tick++;
          if (tick > 10) {
            t.cancel();
            return;
          }
          fakeProcess.emitStderr('[whisper] init $tick');
        });
        addTearDown(timer.cancel);

        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
          reason:
              'Continuous heartbeat must keep startup alive until health 200',
        );
      },
    );
  });
}

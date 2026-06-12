/// Unit tests for SttServerStateNotifier (new modular notifier).
///
/// Uses the same DI seam as the snapshot tests: [processRunnerProvider] and
/// [sttHttpClientProvider]. Provider imports come from [stt_bundle.dart].
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

// ---------------------------------------------------------------------------
// Fake helpers (self-contained; do not import from other test files)
// ---------------------------------------------------------------------------

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
  int get pid => 99998;

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

class _FakeProcessRunner extends ProcessRunner {
  final _FakeProcess process;
  int startCallCount = 0;
  String? lastWorkingDirectory;
  String? lastExecutable;

  _FakeProcessRunner(this.process);

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    startCallCount++;
    lastExecutable = executable;
    lastWorkingDirectory = workingDirectory;
    return process;
  }
}

/// Returns a different [_FakeProcess] from a pre-seeded queue on every
/// `start()` call. Used by the recovery integration test where the
/// notifier must spawn a second whisper-server after the auto-recovery.
class _MultiStageRunner extends ProcessRunner {
  _MultiStageRunner(List<_FakeProcess> processes) : _queue = List.of(processes);

  final List<_FakeProcess> _queue;
  int startCallCount = 0;

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    startCallCount += 1;
    if (_queue.isEmpty) {
      throw StateError(
        'MultiStageRunner exhausted: ${startCallCount}th start() with no '
        'pre-seeded fake process left',
      );
    }
    return _queue.removeAt(0);
  }
}

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

http.Client _healthyClient() => MockClient((req) async {
  if (req.url.path == '/health') return http.Response('ok', 200);
  if (req.url.path == '/inference') return http.Response('{"text":""}', 200);
  return http.Response('not found', 404);
});

http.Client _unhealthyClient() =>
    MockClient((_) async => http.Response('not ready', 503));

ProviderContainer _makeContainer({
  required ProcessRunner runner,
  required http.Client httpClient,
  AppSettings? settings,
  SttStartupHeartbeatConfig? heartbeatConfig,
  ServerBinaryRecovery? recoveryOverride,
  hw.GpuInfo? gpu,
}) {
  return ProviderContainer(
    overrides: [
      processRunnerProvider.overrideWithValue(runner),
      // Make the Windows pre-launch loader gate inert and host-OS-independent.
      // Replaces the old fragile workaround of writing a real vulkan-1.dll into
      // the temp server dir — that only satisfied the Vulkan loader and still
      // tripped on the Windows runner for CUDA-routed GPUs.
      backendLoaderGateProvider.overrideWithValue((_) => null),
      sttHttpClientProvider.overrideWithValue(httpClient),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ?? AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            gpu ??
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
      if (heartbeatConfig != null)
        sttStartupHeartbeatConfigProvider.overrideWithValue(heartbeatConfig),
      if (recoveryOverride != null)
        serverBinaryRecoveryProvider.overrideWithValue(recoveryOverride),
    ],
  );
}

/// Recovery double that returns a scripted outcome and records calls.
/// Avoids hitting the real WhisperServerDownloader / disk.
///
/// Optional [onRecover] callback lets the test re-stage the fake STT dir
/// (e.g. re-create the model file that the crash-trigger deleted) before
/// the notifier kicks off its post-recovery restart.
class _RecordingRecovery implements ServerBinaryRecovery {
  _RecordingRecovery(this.result, {this.onRecover});

  RecoveryResult result;
  int recoverCalls = 0;
  final Future<void> Function()? onRecover;

  @override
  Future<RecoveryResult> recover({
    required RecoveryReason reason,
    required hw.GpuInfo gpu,
    required String sttDirPath,
    required String? activeModelId,
  }) async {
    recoverCalls += 1;
    if (onRecover != null) await onRecover!();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  int invalidateCalls = 0;
  int downloadModelCalls = 0;
  String? lastDownloadedModelId;

  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});

  @override
  Future<void> downloadModel(String modelId) async {
    downloadModelCalls += 1;
    lastDownloadedModelId = modelId;
    state = ModelDownloadState(downloadedModels: {modelId});
  }

  @override
  Future<void> invalidateServerBinary() async {
    // Record the self-heal hand-off without touching disk or the real
    // download pipeline.
    invalidateCalls += 1;
  }
}

Future<Directory> _createFakeSttDir({String modelId = 'whisper-small'}) async {
  final dir = await Directory.systemTemp.createTemp('stt_notifier_test_');

  final serverName = Platform.isWindows
      ? 'whisper-server.exe'
      : 'whisper-server';
  await File('${dir.path}/$serverName').writeAsBytes([0x7f, 0x45, 0x4c, 0x46]);

  final modelFilename =
      findSttModel(modelId)?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));

  paths.sttDirOverride = dir.path;
  return dir;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SttServerStateNotifier — basic lifecycle', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('initial state is stopped', () {
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

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.stopped);
    });

    test('recovery-downgraded Vulkan build on a cuda-optimal NVIDIA machine '
        'starts instead of triggering the self-heal re-download '
        '(FLUTTER_WHISPASTE-A0)', () async {
      // ServerBinaryRecovery installed the Vulkan build and recorded
      // backend=vulkan. Pre-fix, _start()'s proactive compatibility check
      // flagged vulkan != cuda as incompatible, parked the server in
      // `stopped` and handed off to invalidateServerBinary() — which
      // deleted the working build and re-pulled the failing cuda one
      // (the cuda↔vulkan ping-pong that exhausted recovery in the field).
      await File(
        '${tempDir.path}/.server-info.json',
      ).writeAsString('{"backend":"vulkan"}');
      // Satisfy the Windows-only pre-launch loader gate.
      await File('${tempDir.path}/vulkan-1.dll').writeAsBytes(const [0]);

      const rtx = hw.GpuInfo(
        vendor: hw.GpuVendor.nvidia,
        name: 'NVIDIA GeForce RTX 5060 Laptop GPU',
        cudaAvailable: true,
        vulkanAvailable: true,
      );

      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        gpu: rtx,
        heartbeatConfig: const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
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
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
        reason: 'the intentional downgrade must launch, not bail into stopped',
      );
      final download =
          container.read(modelDownloadProvider.notifier)
              as _FakeModelDownloadNotifier;
      expect(
        download.invalidateCalls,
        0,
        reason:
            'the proactive check must NOT hand a runnable downgrade to the '
            'self-heal delete/re-download path',
      );
    });

    test('ensureRunning() transitions to ready on healthy server', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        heartbeatConfig: const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
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

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.ready);
      expect(status.port, greaterThan(0));
    });

    test('whisper-server is launched with workingDirectory = its own dir '
        '(DLL search path fix, FLUTTER_WHISPASTE-A0)', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        heartbeatConfig: const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
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

      // The server binary lives in the (overridden) stt dir; its working
      // directory must be that same folder so whisper-server resolves its
      // sibling ggml/BLAS/VC++ DLLs at runtime instead of inheriting the
      // app's cwd (System32 under MSIX → STATUS_DLL_NOT_FOUND).
      expect(runner.lastWorkingDirectory, isNotNull);
      expect(
        runner.lastWorkingDirectory,
        File(runner.lastExecutable!).parent.path,
      );
      expect(runner.lastWorkingDirectory, tempDir.path);
    });

    test('stop() transitions to stopped', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        heartbeatConfig: const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
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
      );
    });

    test(
      'incompatible binary → silent self-heal, no user-facing error',
      () async {
        // Stored metadata says the binary was fetched for a CUDA backend
        // (the variant an older WhisPaste build picked for this card), but
        // the current GPU — a Kepler GeForce GTX 650 — now needs the Vulkan
        // build. The proactive compatibility check must hand off to the
        // download notifier's self-heal instead of surfacing an
        // "Incompatible whisper-server" error to the user. Regression guard
        // for FLUTTER_WHISPASTE-80.
        await hw.writeServerBinaryInfo(
          tempDir.path,
          const hw.GpuInfo(
            vendor: hw.GpuVendor.nvidia,
            name: 'NVIDIA GeForce RTX 3060',
            cudaAvailable: true,
          ),
        );

        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          gpu: const hw.GpuInfo(
            vendor: hw.GpuVendor.nvidia,
            name: 'NVIDIA GeForce GTX 650',
            cudaAvailable: true,
          ),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        final status = container.read(localSttBundleProvider);
        // No hard error, no "go re-download in Settings" dead-end.
        expect(status.serverState, isNot(SttServerState.error));
        expect(status.errorMessage ?? '', isNot(contains('Incompatible')));
        // The process was never started — we bailed at the proactive check.
        expect(runner.startCallCount, 0);
        // The self-heal re-download was kicked off.
        final download =
            container.read(modelDownloadProvider.notifier)
                as _FakeModelDownloadNotifier;
        expect(download.invalidateCalls, 1);
      },
    );

    test('heartbeat timeout → error state, model not blacklisted', () async {
      const hbConfig = SttStartupHeartbeatConfig(
        window: Duration(milliseconds: 50),
        maxMissedWindows: 3,
      );

      final fakeProcess = _FakeProcess();
      addTearDown(() => fakeProcess.exit(0));
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _unhealthyClient(),
        heartbeatConfig: hbConfig,
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.error);
      expect(status.errorMessage, isNot(contains('corrupted')));
    });

    test(
      'exit code 99 (other) → error state, cpuFallbackActive remains false',
      () async {
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          httpClient: _unhealthyClient(),
          heartbeatConfig: const SttStartupHeartbeatConfig(
            window: Duration(milliseconds: 50),
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

        fakeProcess.exit(99);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final status = container.read(localSttBundleProvider);
        expect(status.serverState, SttServerState.error);
        expect(status.cpuFallbackActive, isFalse);
      },
    );

    test('abnormal exit code -1 on GPU launch → CPU fallback armed (stopped, '
        'not error)', () async {
      // FLUTTER_WHISPASTE-6X / -39: a GPU build aborts with code -1 and an
      // empty stderr when the runtime cannot initialise the GPU. A negative
      // exit code is an abnormal termination, so — unlike the deliberate
      // positive exit 99 above — it must arm the one-shot CPU fallback instead
      // of dead-ending in `error`.
      // Use a modern NVIDIA GPU (shouldUseGpu==true) so the proactive
      // capability gate does not pre-empt the reactive fallback path under
      // test.
      const modernGpu = hw.GpuInfo(
        vendor: hw.GpuVendor.nvidia,
        name: 'NVIDIA GeForce RTX 4090',
        cudaAvailable: true,
        vulkanAvailable: true,
      );
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _unhealthyClient(),
        heartbeatConfig: const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
        gpu: modernGpu,
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

      fakeProcess.exit(-1);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Server is parked in `stopped` with the fallback armed: the next
      // `ensureRunning()` relaunches in CPU mode. It must NOT be `error`,
      // which is the pre-fix dead-end this guards against.
      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.stopped);
    });

    test(
      'heartbeat timeout on a GPU launch → CPU fallback + auto-restart to ready',
      () async {
        // FLUTTER_WHISPASTE-9W: a GPU build initialises fully then makes no
        // progress — a hang, not an exit. The exit-code-only fallback never
        // fires for a hang, so the stall path must arm the one-shot CPU
        // fallback and restart in CPU mode.
        // Use a modern GPU (shouldUseGpu==true) so the proactive capability
        // gate does not pre-empt the reactive stall path under test.
        const hbConfig = SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 30),
          maxMissedWindows: 3,
        );

        const modernGpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce RTX 4090',
          cudaAvailable: true,
          vulkanAvailable: true,
        );

        // Present the installed binary as a healthy, correctly-provisioned
        // CUDA build: matching `.server-info.json` metadata so
        // `isServerBinaryCompatible` does not flag the dir as needing a
        // re-download before the heartbeat path is reached.
        await hw.writeServerBinaryInfo(tempDir.path, modernGpu);
        await File('${tempDir.path}/vulkan-1.dll').writeAsBytes(const [0]);

        final hungProc = _FakeProcess();
        final cpuProc = _FakeProcess();
        final runner = _MultiStageRunner([hungProc, cpuProc]);

        // `/health` is 503 for the first (hung GPU) launch and 200 once the
        // CPU restart spawns the second process — keyed off the start count
        // so we don't have to predict the random ports.
        final client = MockClient((req) async {
          if (req.url.path == '/health') {
            return runner.startCallCount >= 2
                ? http.Response('ok', 200)
                : http.Response('not ready', 503);
          }
          if (req.url.path == '/inference') {
            return http.Response('{"text":""}', 200);
          }
          return http.Response('not found', 404);
        });

        final container = _makeContainer(
          runner: runner,
          httpClient: client,
          heartbeatConfig: hbConfig,
          gpu: modernGpu,
        );
        addTearDown(() {
          container.dispose();
          hungProc.exit(0);
          cpuProc.exit(0);
        });

        await container.read(settingsProvider.future);
        // The hung process never emits stderr → heartbeat windows accumulate
        // → _HeartbeatTimeoutException → CPU fallback → restart on cpuProc.
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        final status = container.read(localSttBundleProvider);
        expect(
          status.serverState,
          SttServerState.ready,
          reason: 'CPU restart after the GPU hang must reach ready',
        );
        expect(
          status.cpuFallbackActive,
          isTrue,
          reason: 'the surfaced status must flag the active CPU fallback',
        );
        expect(
          runner.startCallCount,
          2,
          reason: 'the CPU fallback must spawn whisper-server a second time',
        );
      },
    );

    test(
      'heartbeat timeout on a CPU-only host → error (no pointless fallback)',
      () async {
        // The flip side of the GPU-stall fallback: with no real GPU there is
        // nothing to fall back *from*, so a stall stays an error rather than
        // burning a restart on an identical CPU launch. Guards the
        // `gpu.hasGpu` gate in [_tryStallCpuFallback].
        const hbConfig = SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 30),
          maxMissedWindows: 3,
        );

        final hungProc = _FakeProcess();
        addTearDown(() => hungProc.exit(0));
        final runner = _FakeProcessRunner(hungProc);
        final container = _makeContainer(
          runner: runner,
          httpClient: _unhealthyClient(),
          heartbeatConfig: hbConfig,
          // Default GPU is `none` — but pin it explicitly for intent.
          gpu: const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        final status = container.read(localSttBundleProvider);
        expect(status.serverState, SttServerState.error);
        expect(status.cpuFallbackActive, isFalse);
        expect(
          runner.startCallCount,
          1,
          reason: 'a CPU-only host must not burn a second start on fallback',
        );
      },
    );
  });

  group('SttServerStateNotifier — recovery hook', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test(
      'modelLoad exit + missing model file → ServerBinaryRecovery is '
      'invoked and notifier auto-restarts to ready (RecoveryRetried)',
      () async {
        // Two-stage subprocess runner: first start = crashing process,
        // second start = healthy process for the post-recovery restart.
        final crashedProc = _FakeProcess();
        final healthyProc = _FakeProcess();
        final runner = _MultiStageRunner([crashedProc, healthyProc]);

        // The fake recovery re-creates the model file so the post-
        // recovery `ensureRunning()` restart finds the binary + model
        // intact and reaches `ready` — that is the entire point of the
        // "next recording works without further interaction" AC.
        final modelFilename = findSttModel('whisper-small')!.filename;
        final modelFile = File('${tempDir.path}/$modelFilename');
        final recovery = _RecordingRecovery(
          const RecoveryRetried('vulkan'),
          onRecover: () async {
            await modelFile.writeAsBytes(Uint8List(11 * 1024 * 1024));
          },
        );

        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          heartbeatConfig: const SttStartupHeartbeatConfig(
            window: Duration(milliseconds: 50),
            maxMissedWindows: 3,
          ),
          recoveryOverride: recovery,
        );
        addTearDown(() {
          container.dispose();
          crashedProc.exit(0);
          healthyProc.exit(0);
        });

        await container.read(settingsProvider.future);

        // Kick off ensureRunning but do not await — we need to drive the
        // crash and recovery before the future completes.
        final notifier = container.read(localSttBundleProvider.notifier);
        unawaited(notifier.ensureRunning());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Drop the model file so _handleModelLoadFailure cannot run the
        // SHA check → hashMismatch stays false → recovery is invoked
        // (rather than silent re-download).
        if (await modelFile.exists()) await modelFile.delete();

        // Trigger modelLoad exit (code 3).
        crashedProc.exit(3);

        // Allow recovery + restart to run.
        // Recovery override resolves immediately, then _restartAfterRecovery
        // calls ensureRunning which spawns the healthy process. The healthy
        // process needs a stderr line so the heartbeat resets.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        healthyProc.emitStderr('[whisper] model loaded');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          recovery.recoverCalls,
          1,
          reason: 'recovery hook must be invoked exactly once',
        );
        expect(
          runner.startCallCount,
          2,
          reason:
              'post-recovery restart must spawn whisper-server a second time',
        );

        final status = container.read(localSttBundleProvider);
        expect(
          status.serverState,
          SttServerState.ready,
          reason: 'auto-restart must transition the notifier to ready',
        );
      },
    );

    test(
      'modelLoad exit + RecoveryExhausted → notifier surfaces PRD message',
      () async {
        final crashedProc = _FakeProcess();
        final runner = _FakeProcessRunner(crashedProc);

        final recovery = _RecordingRecovery(
          const RecoveryExhausted(
            'Sprachdienst kann nicht starten. '
            'Bitte App neu starten oder Sprachmodell neu laden.',
          ),
        );

        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          heartbeatConfig: const SttStartupHeartbeatConfig(
            window: Duration(milliseconds: 50),
            maxMissedWindows: 3,
          ),
          recoveryOverride: recovery,
        );
        addTearDown(() {
          container.dispose();
          crashedProc.exit(0);
        });

        await container.read(settingsProvider.future);

        final notifier = container.read(localSttBundleProvider.notifier);
        unawaited(notifier.ensureRunning());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Drop the model file so the recovery path runs.
        final modelFile = File(
          '${tempDir.path}/${findSttModel('whisper-small')!.filename}',
        );
        if (await modelFile.exists()) await modelFile.delete();

        crashedProc.exit(3);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(recovery.recoverCalls, 1);

        final status = container.read(localSttBundleProvider);
        expect(status.serverState, SttServerState.error);
        expect(
          status.errorMessage,
          contains('Sprachdienst kann nicht starten'),
          reason: 'PRD-spec German user message must reach the surface state',
        );
        expect(status.errorMessage, contains('Sprachmodell'));
      },
    );

    test('modelLoad exit with "failed to open" stderr → file-unreadable error, '
        'NO binary recovery (FLUTTER_WHISPASTE-A0)', () async {
      // Field repro: the GTX 650 Kepler box exits 3 because the server
      // process cannot open the (present, SHA-intact) model file. That is a
      // path/launch-context fault, not an ABI mismatch — the notifier must
      // surface an honest error and must NOT hand the crash to
      // ServerBinaryRecovery (a different binary variant cannot fix it).
      final crashedProc = _FakeProcess();
      final runner = _FakeProcessRunner(crashedProc);

      // Recovery override that fails the test if it is ever invoked.
      final recovery = _RecordingRecovery(
        const RecoveryExhausted('should not be reached'),
      );

      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
        heartbeatConfig: const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
        recoveryOverride: recovery,
      );
      addTearDown(() {
        container.dispose();
        crashedProc.exit(0);
      });

      await container.read(settingsProvider.future);

      final notifier = container.read(localSttBundleProvider.notifier);
      unawaited(notifier.ensureRunning());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // whisper.cpp's real file-open failure line, then exit code 3.
      crashedProc.emitStderr(
        'whisper_init_from_file_with_params_no_state: failed to open '
        "'C:\\Users\\maikg\\AppData\\Roaming\\WhisPaste\\models\\stt\\"
        "ggml-small-q5_1.bin'",
      );
      crashedProc.emitStderr('error: failed to initialize whisper context');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      crashedProc.exit(3);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        recovery.recoverCalls,
        0,
        reason: 'a file-open fault must NOT trigger binary recovery',
      );

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.error);
      expect(status.errorMessage, contains('nicht öffnen'));
      expect(status.errorMessage, contains('Debug-Informationen'));
    });
  });

  group('SttServerStateNotifier — notify methods', () {
    test(
      'notifyRecordingStarted/Stopped do not throw when server is stopped',
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
        notifier.notifyRecordingStarted();
        notifier.notifyRecordingStopped();
        notifier.notifyTranscriptionCompleted();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Pure decision function — isSttModelFileTooSmall (AC3)
  // ---------------------------------------------------------------------------

  group('isSttModelFileTooSmall — pure decision function', () {
    // Table-driven: each entry is (fileSizeBytes, expected)
    const cases = <(int, bool)>[
      (0, true), // empty file
      (1024, true), // 1 KB — clearly truncated
      (9 * 1024 * 1024, true), // 9 MiB — just below threshold
      (10 * 1024 * 1024 - 1, true), // one byte below threshold
      (10 * 1024 * 1024, false), // exactly at threshold — not corrupt
      (11 * 1024 * 1024, false), // 11 MiB — healthy model
      (200 * 1024 * 1024, false), // 200 MiB — large model, healthy
    ];

    for (final (size, expected) in cases) {
      test('${size ~/ 1024} KB → isTooSmall=$expected', () {
        expect(isSttModelFileTooSmall(size), equals(expected));
      });
    }

    test('custom minModelBytes threshold is respected', () {
      // 5 MiB min — a 6 MiB file should pass.
      expect(
        isSttModelFileTooSmall(6 * 1024 * 1024, minModelBytes: 5 * 1024 * 1024),
        isFalse,
      );
      // Same 6 MiB file fails against the default 10 MiB threshold.
      expect(isSttModelFileTooSmall(6 * 1024 * 1024), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Corrupt/too-small model → silent re-download (AC1, AC2)
  // ---------------------------------------------------------------------------

  group('SttServerStateNotifier — corrupt model auto-reload', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('too-small model file triggers silent re-download via '
        'modelDownloadProvider (AC1, AC2)', () async {
      // Overwrite the 11 MiB model that _createFakeSttDir wrote with a
      // truncated 1 KiB stub — simulating an interrupted download.
      final modelFilename =
          findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
      final modelFile = File('${tempDir.path}/$modelFilename');
      await modelFile.writeAsBytes(Uint8List(1024)); // 1 KB — below 10 MiB

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

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      // The notifier must park in `stopped` (mirroring the SHA-mismatch
      // self-heal path) and hand off to modelDownloadProvider.downloadModel.
      final status = container.read(localSttBundleProvider);
      expect(
        status.serverState,
        SttServerState.stopped,
        reason:
            'corrupt model path must park in stopped, not error '
            '(consistent with SHA-mismatch self-heal — AC2)',
      );

      final download =
          container.read(modelDownloadProvider.notifier)
              as _FakeModelDownloadNotifier;
      expect(
        download.downloadModelCalls,
        1,
        reason: 'silent re-download must be triggered exactly once (AC1)',
      );
      expect(
        download.lastDownloadedModelId,
        'whisper-small',
        reason: 're-download must request the active model id',
      );
      // Whisper-server must NOT have been spawned for a corrupt model.
      expect(
        runner.startCallCount,
        0,
        reason: 'no server process must be started for a corrupt model file',
      );
    });

    test(
      'healthy 11 MiB model file does NOT trigger re-download (regression guard)',
      () async {
        // _createFakeSttDir already writes an 11 MiB file — no override needed.
        final fakeProcess = _FakeProcess();
        final runner = _FakeProcessRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          httpClient: _healthyClient(),
          heartbeatConfig: const SttStartupHeartbeatConfig(
            window: Duration(milliseconds: 50),
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

        final download =
            container.read(modelDownloadProvider.notifier)
                as _FakeModelDownloadNotifier;
        expect(
          download.downloadModelCalls,
          0,
          reason: 'a healthy model must never trigger a silent re-download',
        );
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
        );
      },
    );
  });
}

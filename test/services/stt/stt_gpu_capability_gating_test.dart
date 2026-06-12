/// Tests for proactive GPU capability gating (issue 09).
///
/// Verifies:
/// 1. `shouldUseGpu`-predicate wiring in `_start`: Kepler/old-GCN GPU →
///    CPU route (--no-gpu in args), no Sentry error emitted.
/// 2. Bidirectional flash-attn gating in `_serverArgs`:
///    - GPU mode + `supportsFlashAttn == false` → `--no-flash-attn`
///    - GPU mode + `supportsFlashAttn == true`  → `--flash-attn`
///    - GPU disabled                             → neither flag
/// 3. Modern GPU retains GPU acceleration (not routed to CPU by predicate).
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
// Fakes
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
  int get pid => 12399;

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

/// Captures start arguments for inspection.
class _ArgCapturingRunner extends ProcessRunner {
  final _FakeProcess process;
  List<String>? capturedArgs;

  _ArgCapturingRunner(this.process);

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    capturedArgs = List.unmodifiable(arguments);
    return process;
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

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
}

http.Client _healthyClient() => MockClient((req) async {
  if (req.url.path == '/health') return http.Response('ok', 200);
  if (req.url.path == '/inference') return http.Response('{"text":""}', 200);
  return http.Response('not found', 404);
});

ProviderContainer _makeContainer({
  required ProcessRunner runner,
  required hw.GpuInfo gpu,
  String gpuAcceleration = 'auto',
}) {
  return ProviderContainer(
    overrides: [
      processRunnerProvider.overrideWithValue(runner),
      // Make the Windows pre-launch loader gate inert and host-OS-independent:
      // these tests exercise the proactive shouldUseGpu/--no-gpu path, not the
      // DLL gate. Without this the real probe sees an empty server dir on the
      // Windows runner and short-circuits `_start` before the args are built.
      backendLoaderGateProvider.overrideWithValue((_) => null),
      // Same rationale: the bare fake binary staged here has no backend DLLs,
      // so the real compatibility probe would flag it incompatible on the
      // Windows runner and self-heal before the args are built. Force compatible
      // — these tests assert the shouldUseGpu/--no-gpu wiring, not binary compat.
      serverBinaryCompatibilityProvider.overrideWithValue((_, _) => true),
      sttHttpClientProvider.overrideWithValue(_healthyClient()),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          AppSettings.defaults.copyWith(
            sttModel: 'whisper-small',
            gpuAcceleration: gpuAcceleration,
          ),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith((_) async => gpu),
      sttStartupHeartbeatConfigProvider.overrideWithValue(
        const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
      ),
    ],
  );
}

Future<Directory> _createFakeSttDir() async {
  final dir = await Directory.systemTemp.createTemp('stt_gpu_gate_test_');
  final serverName = Platform.isWindows
      ? 'whisper-server.exe'
      : 'whisper-server';
  await File('${dir.path}/$serverName').writeAsBytes([0x7f, 0x45, 0x4c, 0x46]);
  await File(
    '${dir.path}/ggml-small-q5_1.bin',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));
  paths.sttDirOverride = dir.path;
  return dir;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await _createFakeSttDir();
  });

  tearDown(() async {
    paths.sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  // ── AC2: bidirectional flash-attn gating ─────────────────────────────────

  group('bidirectional flash-attn gating in _serverArgs', () {
    test(
      'GPU mode active + supportsFlashAttn==false → --no-flash-attn in args',
      () async {
        // NVIDIA GTX 980 (Maxwell): supportsCuda12=true but supportsFlashAttn=false
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce GTX 980',
          cudaAvailable: true,
          vulkanAvailable: true,
        );
        // supportsFlashAttn==false: GTX 980 is Maxwell, not RTX/GTX 16xx
        assert(!gpu.supportsFlashAttn, 'fixture must not support flash-attn');

        final fakeProcess = _FakeProcess();
        final runner = _ArgCapturingRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          gpu: gpu,
          gpuAcceleration: 'auto',
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        fakeProcess.emitStderr('[whisper] loading model');
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          runner.capturedArgs,
          contains('--no-flash-attn'),
          reason: 'Must disable flash-attn on GPU that does not support it',
        );
        expect(
          runner.capturedArgs,
          isNot(contains('--flash-attn')),
          reason: 'Must not add --flash-attn when not supported',
        );
        expect(
          runner.capturedArgs,
          isNot(contains('--no-gpu')),
          reason: 'GTX 980 (Maxwell) passes shouldUseGpu, must stay on GPU',
        );
      },
    );

    test(
      'GPU mode active + supportsFlashAttn==true → --flash-attn in args, no --no-flash-attn',
      () async {
        // RTX 4090: supports flash-attn
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce RTX 4090',
          cudaAvailable: true,
          vulkanAvailable: true,
        );
        assert(gpu.supportsFlashAttn, 'fixture must support flash-attn');

        final fakeProcess = _FakeProcess();
        final runner = _ArgCapturingRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          gpu: gpu,
          gpuAcceleration: 'auto',
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        fakeProcess.emitStderr('[whisper] loading model');
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          runner.capturedArgs,
          contains('--flash-attn'),
          reason: 'RTX 4090 supports flash-attn, must enable it',
        );
        expect(
          runner.capturedArgs,
          isNot(contains('--no-flash-attn')),
          reason: 'Must not add --no-flash-attn when flash-attn is supported',
        );
      },
    );

    test(
      'GPU disabled → neither --flash-attn nor --no-flash-attn, but --no-gpu',
      () async {
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce RTX 4090',
          cudaAvailable: true,
          vulkanAvailable: true,
        );

        final fakeProcess = _FakeProcess();
        final runner = _ArgCapturingRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          gpu: gpu,
          gpuAcceleration: 'disabled',
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        fakeProcess.emitStderr('[whisper] loading model');
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          runner.capturedArgs,
          isNot(contains('--flash-attn')),
          reason: 'CPU mode: must not add --flash-attn',
        );
        expect(
          runner.capturedArgs,
          isNot(contains('--no-flash-attn')),
          reason: 'CPU mode: must not add --no-flash-attn (already --no-gpu)',
        );
        expect(
          runner.capturedArgs,
          contains('--no-gpu'),
          reason: 'CPU mode must add --no-gpu',
        );
      },
    );
  });

  // ── AC3: shouldUseGpu wiring in _start ───────────────────────────────────

  group('shouldUseGpu wiring in _start — proactive CPU route', () {
    test(
      'Kepler GTX 650 + auto mode → --no-gpu (proactive CPU route, no GPU crash)',
      () async {
        // Kepler: shouldUseGpu==false, so _start must use CPU even in auto mode
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce GTX 650',
          cudaAvailable: true,
          vulkanAvailable: true,
        );
        // Confirm fixture
        assert(
          !hw.shouldUseGpu(gpu),
          'Kepler must not pass shouldUseGpu check',
        );

        final fakeProcess = _FakeProcess();
        final runner = _ArgCapturingRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          gpu: gpu,
          gpuAcceleration: 'auto',
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        fakeProcess.emitStderr('[whisper] loading model');
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          runner.capturedArgs,
          contains('--no-gpu'),
          reason: 'Kepler GPU must be proactively routed to CPU via --no-gpu',
        );
      },
    );

    test(
      'modern RTX 4090 + auto mode → no --no-gpu (retains GPU acceleration)',
      () async {
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce RTX 4090',
          cudaAvailable: true,
          vulkanAvailable: true,
        );
        assert(hw.shouldUseGpu(gpu), 'RTX 4090 must pass shouldUseGpu');

        final fakeProcess = _FakeProcess();
        final runner = _ArgCapturingRunner(fakeProcess);
        final container = _makeContainer(
          runner: runner,
          gpu: gpu,
          gpuAcceleration: 'auto',
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        fakeProcess.emitStderr('[whisper] loading model');
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          runner.capturedArgs,
          isNot(contains('--no-gpu')),
          reason: 'RTX 4090 must retain GPU acceleration',
        );
      },
    );

    test(
      'Kepler + user override enabled → GPU used despite shouldUseGpu==false '
      '(user override takes precedence)',
      () async {
        const gpu = hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NVIDIA GeForce GTX 650',
          cudaAvailable: true,
          vulkanAvailable: true,
        );

        final fakeProcess = _FakeProcess();
        final runner = _ArgCapturingRunner(fakeProcess);
        // User explicitly forces GPU on — override beats shouldUseGpu
        final container = _makeContainer(
          runner: runner,
          gpu: gpu,
          gpuAcceleration: 'enabled',
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        await container.read(settingsProvider.future);
        fakeProcess.emitStderr('[whisper] loading model');
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          runner.capturedArgs,
          isNot(contains('--no-gpu')),
          reason:
              'User-enabled override must take precedence over shouldUseGpu',
        );
      },
    );
  });
}

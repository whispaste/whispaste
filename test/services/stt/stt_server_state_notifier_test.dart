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

  _FakeProcessRunner(this.process);

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    startCallCount++;
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
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
      if (heartbeatConfig != null)
        sttStartupHeartbeatConfigProvider.overrideWithValue(heartbeatConfig),
    ],
  );
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});

  @override
  Future<void> downloadModel(String modelId) async {
    state = ModelDownloadState(downloadedModels: {modelId});
  }
}

Future<Directory> _createFakeSttDir({String modelId = 'whisper-tiny'}) async {
  final dir = await Directory.systemTemp.createTemp('stt_notifier_test_');

  final serverName = Platform.isWindows
      ? 'whisper-server.exe'
      : 'whisper-server';
  await File('${dir.path}/$serverName').writeAsBytes([0x7f, 0x45, 0x4c, 0x46]);

  final modelFilename = findSttModel(modelId)?.filename ?? 'ggml-tiny-q5_1.bin';
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

    test('ensureRunning() transitions to ready on healthy server', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
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

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.ready);
      expect(status.port, greaterThan(0));
    });

    test('stop() transitions to stopped', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final container = _makeContainer(
        runner: runner,
        httpClient: _healthyClient(),
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
      );
    });

    test('heartbeat timeout → error state, model not blacklisted', () async {
      const hbConfig = (
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

        fakeProcess.exit(99);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final status = container.read(localSttBundleProvider);
        expect(status.serverState, SttServerState.error);
        expect(status.cpuFallbackActive, isFalse);
      },
    );
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
}

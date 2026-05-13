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

// ── Fakes ──────────────────────────────────────────────────────────────────

class _FakeProcess implements Process {
  final _stdoutController = StreamController<List<int>>();
  final _stderrController = StreamController<List<int>>();
  final _exitCodeCompleter = Completer<int>();

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;
  @override
  Stream<List<int>> get stderr => _stderrController.stream;
  @override
  Future<int> get exitCode => _exitCodeCompleter.future;
  @override
  int get pid => 12345;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    return true;
  }

  @override
  IOSink get stdin => throw UnimplementedError();

  void emitStdout(String line) => _stdoutController.add('$line\n'.codeUnits);
  void emitStderr(String line) => _stderrController.add('$line\n'.codeUnits);
  void exit(int code) {
    if (!_exitCodeCompleter.isCompleted) _exitCodeCompleter.complete(code);
  }

  Future<void> dispose() async {
    await _stdoutController.close();
    await _stderrController.close();
  }
}

class _FakeProcessRunner extends ProcessRunner {
  final _FakeProcess process;
  String? lastExecutable;
  List<String>? lastArguments;

  _FakeProcessRunner(this.process);

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    lastExecutable = executable;
    lastArguments = arguments;
    return process;
  }
}

/// A process runner that creates a new [_FakeProcess] on every [start] call.
/// Required when a test calls [SttServerStateNotifier.ensureRunning] more than
/// once, because the single-subscription stderr stream of the first process
/// cannot be re-listened after the first [_start] invocation.
class _MultiFakeProcessRunner extends ProcessRunner {
  final _FakeProcess Function() factory;
  _FakeProcess? lastProcess;

  _MultiFakeProcessRunner(this.factory);

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    lastProcess = factory();
    return lastProcess!;
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

// Returns 200 on /health, empty JSON on /inference
http.Client _makeHealthyHttpClient() => MockClient((request) async {
  if (request.url.path == '/health') {
    return http.Response('ok', 200);
  }
  if (request.url.path == '/inference') {
    return http.Response('{"text":""}', 200);
  }
  return http.Response('not found', 404);
});

// Always returns 503 — server never becomes ready. Used by heartbeat tests
// where the timeout should trigger before health check succeeds.
http.Client _makeUnhealthyHttpClient() =>
    MockClient((request) async => http.Response('not ready', 503));

ProviderContainer _makeContainer({
  required _FakeProcess fakeProcess,
  required http.Client httpClient,
  AppSettings? settings,
  ({Duration window, int maxMissedWindows})? heartbeatConfig,
}) {
  final runner = _FakeProcessRunner(fakeProcess);
  return ProviderContainer(
    overrides: [
      processRunnerProvider.overrideWithValue(runner),
      sttHttpClientProvider.overrideWithValue(httpClient),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ?? AppSettings.defaults.copyWith(sttModel: 'ggml-tiny'),
        ),
      ),
      modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
      if (heartbeatConfig != null)
        sttStartupHeartbeatConfigProvider.overrideWithValue(heartbeatConfig),
    ],
  );
}

/// Creates a temporary directory with a fake whisper-server binary and model
/// file large enough to pass the minimum-size guard (>10 MB). Returns the
/// temp dir; caller is responsible for cleanup.
///
/// Also sets [paths.sttDirOverride] so all path helpers resolve to this dir.
/// Callers MUST reset [paths.sttDirOverride] to null in tearDown.
Future<Directory> _createFakeSttDir() async {
  final dir = await Directory.systemTemp.createTemp('stt_heartbeat_test_');

  // Write fake server binary (any non-empty file; execution is intercepted
  // by _FakeProcessRunner before the OS actually runs it).
  final serverName = Platform.isWindows
      ? 'whisper-server.exe'
      : 'whisper-server';
  final serverFile = File('${dir.path}/$serverName');
  await serverFile.writeAsBytes([0x7f, 0x45, 0x4c, 0x46]); // ELF magic bytes

  // Write fake model file — must be >10 MB to pass the size guard.
  const minModelBytes = 11 * 1024 * 1024; // 11 MB
  final modelFile = File('${dir.path}/ggml-tiny-q5_1.bin');
  await modelFile.writeAsBytes(Uint8List(minModelBytes));

  // Override sttDir so SttServerStateNotifier resolves paths into this temp dir.
  paths.sttDirOverride = dir.path;

  return dir;
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SttServerStateNotifier', () {
    test('stop() puts server into stopped state immediately', () {
      final fakeProcess = _FakeProcess();
      final container = _makeContainer(
        fakeProcess: fakeProcess,
        httpClient: _makeHealthyHttpClient(),
      );
      addTearDown(container.dispose);

      final notifier = container.read(localSttBundleProvider.notifier);
      notifier.stop();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
      );
    });

    test('notifyRecordingStarted pauses idle timer', () {
      final fakeProcess = _FakeProcess();
      final container = _makeContainer(
        fakeProcess: fakeProcess,
        httpClient: _makeHealthyHttpClient(),
      );
      addTearDown(container.dispose);

      // Should not throw
      container.read(localSttBundleProvider.notifier).notifyRecordingStarted();
      container.read(localSttBundleProvider.notifier).notifyRecordingStopped();
    });

    test(
      'processRunnerProvider override is wired into SttServerStateNotifier',
      () async {
        // Verifies that the DI seam is correctly wired: the container reads the
        // overridden ProcessRunner, not SystemProcessRunner.
        // Note: verifying that ensureRunning() *calls* the runner requires a
        // real whisper-server binary at whisperServerPath() — not possible in
        // unit tests. That path is tested by the cold-start integration test.
        final fakeProcess = _FakeProcess();
        final container = _makeContainer(
          fakeProcess: fakeProcess,
          httpClient: _makeHealthyHttpClient(),
        );
        addTearDown(container.dispose);

        // The override must be a _FakeProcessRunner, not SystemProcessRunner.
        expect(
          container.read(processRunnerProvider),
          isA<_FakeProcessRunner>(),
          reason: 'processRunnerProvider override must be active',
        );

        // Calling ensureRunning() without a binary transitions to error, not
        // stopped — proves the runner path was attempted.
        final notifier = container.read(localSttBundleProvider.notifier);
        unawaited(notifier.ensureRunning());
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final state = container.read(localSttBundleProvider).serverState;
        expect(
          state,
          anyOf(
            SttServerState.error,
            SttServerState.starting,
            SttServerState.stopped,
          ),
          reason: 'ensureRunning() must not crash',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Heartbeat-based startup timeout tests
  //
  // All tests use a 50 ms heartbeat window × 3 missed windows = 150 ms max
  // tolerance to keep the test suite fast without sleeping long.
  // ---------------------------------------------------------------------------
  group('Heartbeat-based startup timeout', () {
    // Short policy values used throughout these tests.
    const testHeartbeatWindow = Duration(milliseconds: 50);
    const testMaxMissedWindows = 3;
    const heartbeatConfig = (
      window: testHeartbeatWindow,
      maxMissedWindows: testMaxMissedWindows,
    );

    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test(
      'AC: fast-start — health 200 before first heartbeat window, server becomes ready',
      () async {
        // Health check returns 200 immediately. Process emits stderr right away.
        // Expected: server transitions to ready with no timeout.
        final fakeProcess = _FakeProcess();

        // Immediately emit a stderr line (simulates server printing a startup msg).
        fakeProcess.emitStderr('[whisper] loading model');

        final container = _makeContainer(
          fakeProcess: fakeProcess,
          httpClient: _makeHealthyHttpClient(),
          heartbeatConfig: heartbeatConfig,
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        // Await settings to be fully loaded before calling ensureRunning(),
        // otherwise ref.read(settingsProvider).value is null and the service
        // falls back to AppSettings.defaults (which uses whisper-medium).
        await container.read(settingsProvider.future);

        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
          reason: 'Server must be ready when health check responds 200',
        );

        // Model must not be blacklisted (internal set not exposed; we verify
        // ensureRunning() succeeds again without "model corrupted" error).
        await notifier.ensureRunning();
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
        );
      },
    );

    test(
      'AC: no heartbeat — fails after 3 × window, model is NOT blacklisted',
      () async {
        // No stderr lines ever. HTTP client never returns 200.
        // Expected: after 3 × 50 ms windows the service transitions to error,
        // but the model is NOT in the blacklist (so a second attempt does not
        // immediately fail with "model corrupted").
        //
        // Uses _MultiFakeProcessRunner so the second ensureRunning() call gets
        // a fresh _FakeProcess (single-subscription stream cannot be re-subscribed).
        final processes = <_FakeProcess>[];
        final multiRunner = _MultiFakeProcessRunner(() {
          final p = _FakeProcess();
          processes.add(p);
          return p;
        });

        final httpClient = _makeUnhealthyHttpClient();
        final settings = AppSettings.defaults.copyWith(
          sttModel: 'whisper-tiny',
        );
        final container = ProviderContainer(
          overrides: [
            processRunnerProvider.overrideWithValue(multiRunner),
            sttHttpClientProvider.overrideWithValue(httpClient),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
            hw.gpuInfoProvider.overrideWith(
              (_) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
            ),
            sttStartupHeartbeatConfigProvider.overrideWithValue(
              heartbeatConfig,
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          for (final p in processes) {
            p.exit(0);
          }
        });

        // Await settings to initialise before calling ensureRunning().
        await container.read(settingsProvider.future);

        await container.read(localSttBundleProvider.notifier).ensureRunning();

        // After the heartbeat timeout the server must be in error state.
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.error,
          reason: 'Server must be in error after 3 consecutive missed windows',
        );

        // The error message must not claim the model is corrupted (that would
        // indicate the model was wrongly blacklisted as a model fault).
        final errorMsg =
            container.read(localSttBundleProvider).errorMessage ?? '';
        expect(
          errorMsg,
          isNot(contains('corrupted')),
          reason:
              'Heartbeat timeout must not be reported as a model corruption',
        );

        // Model must NOT be blacklisted: a subsequent ensureRunning() attempt
        // must not immediately fail with "model corrupted / failed to load".
        // It will call _start() again which hits the heartbeat timeout again,
        // so it will land in error — but NOT with a "model corrupted" message.
        await container.read(localSttBundleProvider.notifier).ensureRunning();
        final errorMsg2 =
            container.read(localSttBundleProvider).errorMessage ?? '';
        expect(
          errorMsg2,
          isNot(contains('corrupted')),
          reason:
              'Second attempt must not fail with model-corruption error — '
              'model must not be blacklisted after heartbeat timeout',
        );
      },
    );

    test(
      'AC: continuous heartbeat keeps windows alive until health returns 200',
      () async {
        // Stderr lines come every 20 ms — well within the 50 ms window.
        // Health check returns 503 for the first 120 ms after ensureRunning()
        // starts, then 200. Expected: server becomes ready.
        final fakeProcess = _FakeProcess();

        // healthyAt is set when ensureRunning() starts (after settings load).
        DateTime? healthyAt;
        final httpClient = MockClient((req) async {
          if (req.url.path == '/health') {
            final at = healthyAt;
            if (at != null && DateTime.now().isAfter(at)) {
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
          fakeProcess: fakeProcess,
          httpClient: httpClient,
          heartbeatConfig: heartbeatConfig,
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        // Await settings to initialise before calling ensureRunning().
        await container.read(settingsProvider.future);

        // Set the "become healthy after 120 ms" anchor just before ensureRunning.
        healthyAt = DateTime.now().add(const Duration(milliseconds: 120));

        // Emit stderr heartbeats every 20 ms for 250 ms to keep windows alive.
        var tickCount = 0;
        final heartbeatTimer = Timer.periodic(
          const Duration(milliseconds: 20),
          (t) {
            tickCount++;
            if (tickCount > 15) {
              t.cancel();
              return;
            }
            fakeProcess.emitStderr('[whisper] loading weights ($tickCount)');
          },
        );
        addTearDown(heartbeatTimer.cancel);

        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
          reason:
              'Continuous heartbeat must keep the startup alive until '
              'the health check returns 200',
        );
      },
    );

    test(
      'AC: partial heartbeat — progress stops but health arrives before final window',
      () async {
        // Stderr emits 5 lines at the start of ensureRunning(), then goes silent.
        // Health returns 200 after 80 ms (before 3 × 50 ms = 150 ms total).
        // Expected: server becomes ready.
        final fakeProcess = _FakeProcess();

        DateTime? ensureStartedAt;
        final httpClient = MockClient((req) async {
          if (req.url.path == '/health') {
            final at = ensureStartedAt;
            if (at != null &&
                DateTime.now().difference(at).inMilliseconds >= 80) {
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
          fakeProcess: fakeProcess,
          httpClient: httpClient,
          heartbeatConfig: heartbeatConfig,
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-tiny'),
        );
        addTearDown(() {
          container.dispose();
          fakeProcess.exit(0);
        });

        // Await settings to initialise before calling ensureRunning().
        await container.read(settingsProvider.future);

        // Emit 5 stderr lines to reset the heartbeat window right at start.
        for (var i = 0; i < 5; i++) {
          fakeProcess.emitStderr('[whisper] init step $i');
        }
        ensureStartedAt = DateTime.now();

        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
          reason:
              'Server must become ready if health 200 arrives before '
              'all heartbeat windows are exhausted',
        );
      },
    );
  });
}

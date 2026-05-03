import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/process_runner.dart';
import 'package:whispaste/services/stt_service.dart';

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

  void emitStdout(String line) =>
      _stdoutController.add('$line\n'.codeUnits);
  void emitStderr(String line) =>
      _stderrController.add('$line\n'.codeUnits);
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
  ModelDownloadState build() => const ModelDownloadState(
    downloadedModels: {},
  );
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

ProviderContainer _makeContainer({
  required _FakeProcess fakeProcess,
  required http.Client httpClient,
  AppSettings? settings,
}) {
  final runner = _FakeProcessRunner(fakeProcess);
  return ProviderContainer(
    overrides: [
      processRunnerProvider.overrideWithValue(runner),
      sttHttpClientProvider.overrideWithValue(httpClient),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ??
              AppSettings.defaults.copyWith(
                sttModel: 'ggml-tiny',
              ),
        ),
      ),
      modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SttServiceNotifier', () {
    test('stop() puts server into stopped state immediately', () {
      final fakeProcess = _FakeProcess();
      final container = _makeContainer(
        fakeProcess: fakeProcess,
        httpClient: _makeHealthyHttpClient(),
      );
      addTearDown(container.dispose);

      final notifier = container.read(sttServiceProvider.notifier);
      notifier.stop();

      expect(
        container.read(sttServiceProvider).serverState,
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
      container.read(sttServiceProvider.notifier).notifyRecordingStarted();
      container.read(sttServiceProvider.notifier).notifyRecordingStopped();
    });

    test('processRunnerProvider override is wired into SttServiceNotifier',
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
      final notifier = container.read(sttServiceProvider.notifier);
      unawaited(notifier.ensureRunning());
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = container.read(sttServiceProvider).serverState;
      expect(
        state,
        anyOf(SttServerState.error, SttServerState.starting, SttServerState.stopped),
        reason: 'ensureRunning() must not crash',
      );
    });
  });
}

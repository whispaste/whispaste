/// Tests for the user-triggered benchmark run ("Benchmark erneut ausführen").
///
/// One run measures every installed quality tier (one model each), stores each
/// RTF as soon as it is measured (so the model-card hints update live), ends
/// with the user's own model loaded again, and reports its state through
/// [sttBenchmarkRunProvider] instead of a toast.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/app_info.dart' as app;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/benchmark_freshness.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

class _Engine implements WhisperEngine {
  bool _loaded = false;
  final List<String> loadedModels = [];
  final List<int> transcribeSizes = [];
  Duration transcribeDelay = Duration.zero;

  /// When non-null, the next [load] throws it once.
  Object? nextLoadError;

  /// When non-null, [transcribe] throws it on the 1-based call
  /// [transcribeErrorCall]. The native engine reports an unloaded engine as a
  /// StateError, which is an Error, not an Exception. Call 1 is the warm-up of
  /// the first load, so the measured inference is call 2.
  Object? transcribeError;
  int transcribeErrorCall = 0;

  /// Completes when the first transcribe has started.
  Completer<void> firstTranscribeStarted = Completer<void>();

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    final error = nextLoadError;
    if (error != null) {
      nextLoadError = null;
      throw error;
    }
    loadedModels.add(modelPath.split(Platform.pathSeparator).last);
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async {
    transcribeSizes.add(wavBytes.length);
    if (!firstTranscribeStarted.isCompleted) firstTranscribeStarted.complete();
    final error = transcribeError;
    if (error != null && transcribeSizes.length == transcribeErrorCall) {
      throw error;
    }
    if (transcribeDelay > Duration.zero) {
      await Future<void>.delayed(transcribeDelay);
    }
    return 'fake';
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

class _Settings extends SettingsNotifier {
  _Settings(this._s);
  final AppSettings _s;

  @override
  Future<AppSettings> build() async => _s;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _s));
  }
}

class _Downloads extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
}

Future<Directory> _dirWithModels(List<String> modelIds) async {
  final dir = await Directory.systemTemp.createTemp('stt_suite_');
  for (final id in modelIds) {
    final filename = findSttModel(id)!.filename;
    await File(
      '${dir.path}/$filename',
    ).writeAsBytes(Uint8List(11 * 1024 * 1024));
  }
  return dir;
}

ProviderContainer _container(
  _Engine engine, {
  String model = 'whisper-medium',
}) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(
        () => _Settings(AppSettings.defaults.copyWith(sttModel: model)),
      ),
      modelDownloadProvider.overrideWith(_Downloads.new),
      hw.gpuInfoProvider.overrideWith(
        (_) async => const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  tearDown(() async {
    paths.sttDirOverride = null;
    await dir.delete(recursive: true);
  });

  group('runBenchmark — measures every installed tier', () {
    test(
      'stores every tier RTF, ends done, reloads the user model last',
      () async {
        dir = await _dirWithModels(['whisper-small', 'whisper-medium']);
        paths.sttDirOverride = dir.path;
        final engine = _Engine();
        final c = _container(engine);
        addTearDown(c.dispose);
        await c.read(settingsProvider.future);

        await c.read(localSttBundleProvider.notifier).runBenchmark();

        final run = c.read(sttBenchmarkRunProvider);
        expect(run.phase, BenchmarkRunPhase.done);
        expect(run.cancelled, isFalse);

        final settings = c.read(settingsProvider).value!;
        expect(
          settings.tierBenchmarkRtf!.keys,
          containsAll([QualityTier.compact, QualityTier.balanced]),
        );
        expect(settings.benchmarkTimestamp, isNotNull);
        expect(
          settings.benchmarkHardwareId,
          benchmarkMachineKey(hardwareKey: 'cpu', appVersion: app.appVersion),
        );
        expect(settings.benchmark.benchmarkBackend, 'cpu');

        // Compact (small) is measured first; the user's model (medium) last,
        // so no extra reload is needed to restore it.
        expect(engine.loadedModels.last, endsWith('.bin'));
        expect(
          engine.loadedModels.last,
          findSttModel('whisper-medium')!.filename,
        );
        expect(c.read(localSttBundleProvider).modelId, 'whisper-medium');
        expect(c.read(localSttBundleProvider).isBenchmarking, isFalse);
      },
    );
  });

  group('runBenchmark — refusals and errors', () {
    test('refuses to start during a dictation and says why', () async {
      dir = await _dirWithModels(['whisper-medium']);
      paths.sttDirOverride = dir.path;
      final engine = _Engine();
      final c = _container(engine);
      addTearDown(c.dispose);
      await c.read(settingsProvider.future);

      c.read(localSttBundleProvider.notifier).notifyRecordingStarted();
      await c.read(localSttBundleProvider.notifier).runBenchmark();

      final run = c.read(sttBenchmarkRunProvider);
      expect(run.phase, BenchmarkRunPhase.failed);
      expect(run.error, BenchmarkRunError.busy);
      expect(engine.transcribeSizes, isEmpty);
    });

    test('no installed tier fails with noModel', () async {
      dir = await Directory.systemTemp.createTemp('stt_suite_empty_');
      paths.sttDirOverride = dir.path;
      final engine = _Engine();
      final c = _container(engine);
      addTearDown(c.dispose);
      await c.read(settingsProvider.future);

      await c.read(localSttBundleProvider.notifier).runBenchmark();

      final run = c.read(sttBenchmarkRunProvider);
      expect(run.phase, BenchmarkRunPhase.failed);
      expect(run.error, BenchmarkRunError.noModel);
    });

    test('a load failure is reported inline and a retry succeeds', () async {
      dir = await _dirWithModels(['whisper-small', 'whisper-medium']);
      paths.sttDirOverride = dir.path;
      final engine = _Engine()..nextLoadError = StateError('gpu died');
      final c = _container(engine);
      addTearDown(c.dispose);
      await c.read(settingsProvider.future);
      final notifier = c.read(localSttBundleProvider.notifier);

      await notifier.runBenchmark();
      expect(c.read(sttBenchmarkRunProvider).phase, BenchmarkRunPhase.failed);
      expect(c.read(sttBenchmarkRunProvider).error, BenchmarkRunError.failed);

      await notifier.runBenchmark();
      final run = c.read(sttBenchmarkRunProvider);
      expect(run.phase, BenchmarkRunPhase.done);
      expect(run.error, isNull);
      expect(
        c
            .read(settingsProvider)
            .value!
            .tierBenchmarkRtf!
            .containsKey(QualityTier.compact),
        isTrue,
      );
    });
  });

  group('runBenchmark — engine errors that are not Exceptions', () {
    test('an unloaded-engine StateError still ends the run', () async {
      dir = await _dirWithModels(['whisper-small', 'whisper-medium']);
      paths.sttDirOverride = dir.path;
      final engine = _Engine()
        ..transcribeError = StateError('whisper_engine_not_loaded')
        ..transcribeErrorCall = 2;
      final c = _container(engine);
      addTearDown(c.dispose);
      await c.read(settingsProvider.future);

      // Must complete normally; before the fix the StateError escaped and the
      // run stayed in the running phase for good.
      await c.read(localSttBundleProvider.notifier).runBenchmark();

      final run = c.read(sttBenchmarkRunProvider);
      expect(run.isRunning, isFalse);
      expect(run.phase, BenchmarkRunPhase.failed);
      expect(run.error, BenchmarkRunError.failed);
      // The user's model is loaded again, not the tier that failed.
      expect(c.read(localSttBundleProvider).modelId, 'whisper-medium');
    });
  });

  group('runBenchmark — cancel', () {
    test(
      'cancel stops after the current step and restores the user model',
      () async {
        dir = await _dirWithModels(['whisper-small', 'whisper-medium']);
        paths.sttDirOverride = dir.path;
        final engine = _Engine()
          ..transcribeDelay = const Duration(milliseconds: 150);
        final c = _container(engine);
        addTearDown(c.dispose);
        await c.read(settingsProvider.future);
        final notifier = c.read(localSttBundleProvider.notifier);

        final run = notifier.runBenchmark();
        await engine.firstTranscribeStarted.future;
        c.read(sttBenchmarkRunProvider.notifier).requestCancel();
        await run;

        final result = c.read(sttBenchmarkRunProvider);
        expect(result.phase, BenchmarkRunPhase.done);
        expect(result.cancelled, isTrue);

        final rtf = c.read(settingsProvider).value!.tierBenchmarkRtf!;
        expect(rtf.keys, [QualityTier.compact]);
        // The user's model is loaded again after the cancelled run.
        expect(c.read(localSttBundleProvider).modelId, 'whisper-medium');
      },
    );
  });
}

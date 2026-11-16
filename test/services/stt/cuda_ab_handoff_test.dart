/// Hand-off from the model load to the CUDA/Vulkan comparison (#1670): once
/// the model runs on the CUDA pack, the notifier measures it against a
/// temporary Vulkan engine, stores the winner for this setup, and frees the
/// temporary engine again. A stored result means no second run.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/app_info.dart' as app;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/stt/whisper/cuda_ab.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';

const _gpu = hw.GpuInfo(
  vendor: hw.GpuVendor.nvidia,
  name: 'NVIDIA GeForce GTX 1650',
  vramMB: 4096,
  cudaAvailable: true,
  driverVersion: '32.0.16.1088',
);

const _pack = CudaPackInfo(
  id: 'ggml-test-r1',
  url: 'https://example.invalid/pack.zip',
  archiveSizeBytes: 1024,
  archiveSha256: '',
  files: [],
);

const _model = 'whisper-small';

/// The engine whose transcription ran last; the scripted stopwatch reports
/// that engine's time.
String? _lastDevice;
Map<String, int> _msByDevice = {};

class _Engine implements WhisperEngine {
  _Engine(this.device);

  final String device;
  bool loaded = false;
  int transcribes = 0;
  int unloads = 0;

  @override
  WhisperEngineStatus get status => WhisperEngineStatus(
    isLoaded: loaded,
    backend: WhisperBackend.cuda,
    gpuDevice: device,
  );

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async {
    transcribes++;
    _lastDevice = device;
    return 'text';
  }

  @override
  Future<void> unload() async {
    unloads++;
    loaded = false;
  }
}

class _ScriptedStopwatch implements Stopwatch {
  @override
  int get elapsedMilliseconds => _msByDevice[_lastDevice] ?? 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(sttModel: _model);
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
}

class _InstalledPack extends CudaPackNotifier {
  @override
  CudaPackState build() => const CudaPackState(pack: _pack, installed: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late CudaAbStore store;
  late _Engine cuda;
  late _Engine vulkan;
  late int vulkanEnginesBuilt;

  final savedBenchDelay = SttServerStateNotifier.benchmarkIdleDelay;
  final savedAbDelay = SttServerStateNotifier.cudaAbIdleDelay;
  final savedStopwatch = SttServerStateNotifier.benchmarkStopwatch;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cuda_ab_handoff_');
    final filename = findSttModel(_model)!.filename;
    await File(
      p.join(dir.path, filename),
    ).writeAsBytes(Uint8List(11 * 1024 * 1024));
    paths.sttDirOverride = dir.path;
    store = CudaAbStore(File(p.join(dir.path, 'cuda_ab.json')));
    cuda = _Engine('CUDA0');
    vulkan = _Engine('Vulkan0');
    vulkanEnginesBuilt = 0;
    SttServerStateNotifier.benchmarkIdleDelay = const Duration(milliseconds: 1);
    SttServerStateNotifier.cudaAbIdleDelay = const Duration(milliseconds: 1);
    SttServerStateNotifier.benchmarkStopwatch = _ScriptedStopwatch.new;
  });

  tearDown(() async {
    SttServerStateNotifier.benchmarkIdleDelay = savedBenchDelay;
    SttServerStateNotifier.cudaAbIdleDelay = savedAbDelay;
    SttServerStateNotifier.benchmarkStopwatch = savedStopwatch;
    paths.sttDirOverride = null;
    _lastDevice = null;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        whisperEngineProvider.overrideWithValue(cuda),
        cudaAbVulkanEngineFactoryProvider.overrideWithValue((_) {
          vulkanEnginesBuilt++;
          return vulkan;
        }),
        activeCudaPackDirProvider.overrideWithValue('/pack'),
        cudaAbEnabledProvider.overrideWithValue(true),
        cudaAbStoreProvider.overrideWithValue(store),
        cudaPackProvider.overrideWith(_InstalledPack.new),
        settingsProvider.overrideWith(_FakeSettingsNotifier.new),
        modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
        hw.gpuInfoProvider.overrideWith((_) async => _gpu),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  String key() => cudaAbKey(
    gpu: _gpu,
    appVersion: app.appVersion,
    packId: _pack.id,
    modelId: _model,
  );

  /// Completes with the finished comparison once the notifier stored it,
  /// after the temporary engine was freed (the store write follows the
  /// shutdown). No real waiting: the provider update drives the hand-off.
  Future<CudaAbRecord> recordWritten(ProviderContainer c) {
    final done = Completer<CudaAbRecord>();
    final sub = c.listen<Map<String, CudaAbRecord>>(cudaAbProvider, (_, next) {
      final record = next[key()];
      if (record != null && !record.interrupted && !done.isCompleted) {
        done.complete(record);
      }
    });
    return done.future.whenComplete(sub.close);
  }

  test('a slower CUDA path is set aside after the load (GTX 1650)', () async {
    _msByDevice = {'CUDA0': 2490, 'Vulkan0': 1030};
    final c = container();
    await c.read(hw.gpuInfoProvider.future);
    await c.read(settingsProvider.future);

    final written = recordWritten(c);
    await c.read(localSttBundleProvider.notifier).ensureRunning();
    final record = await written;

    expect(record.winner, CudaAbWinner.vulkan);
    expect(record.cudaMedianMs, 2490);
    expect(record.vulkanMedianMs, 1030);
    expect(vulkan.unloads, 1, reason: 'temporary engine is freed');
    expect(vulkan.loaded, isFalse);
    expect(c.read(cudaAbRecordProvider)?.vulkanFaster, isTrue);
  });

  test('a faster CUDA path stays', () async {
    _msByDevice = {'CUDA0': 530, 'Vulkan0': 810};
    final c = container();
    await c.read(hw.gpuInfoProvider.future);
    await c.read(settingsProvider.future);

    final written = recordWritten(c);
    await c.read(localSttBundleProvider.notifier).ensureRunning();
    final record = await written;

    expect(record.winner, CudaAbWinner.cuda);
    expect(vulkan.loaded, isFalse);
  });

  test('a stored result for this setup means no second run', () async {
    store.write(
      key(),
      CudaAbRecord(winner: CudaAbWinner.cuda, measuredAt: DateTime.utc(2026)),
    );
    final c = container();
    await c.read(hw.gpuInfoProvider.future);
    await c.read(settingsProvider.future);

    final notifier = c.read(localSttBundleProvider.notifier);
    await notifier.ensureRunning();

    // The decision falls right after the load: nothing is queued, so no
    // timer can start a run later.
    expect(c.read(localSttBundleProvider).isReady, isTrue);
    expect(notifier.cudaAbQueued, isFalse);
    expect(vulkanEnginesBuilt, 0);
  });
}

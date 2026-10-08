/// [whisperEngineProvider] rebuilds when async GPU detection resolves or the
/// GPU setting changes, and its `onDispose` shuts the previous engine down.
/// The notifier used to keep the instance it read once in `build()`, so its
/// state stayed `ready` on a dead engine and the next dictation failed with
/// `whisper_engine_not_loaded` (Sentry 120963723). It must follow the
/// provider to the replacement engine instead.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

class _Engine implements WhisperEngine {
  bool loaded = false;
  int loads = 0;
  int transcribes = 0;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    loads++;
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
    if (!loaded) throw StateError('whisper_engine_not_loaded');
    transcribes++;
    return 'transcript';
  }

  @override
  Future<void> unload() async => loaded = false;
}

/// Stands in for the GPU-detection / GPU-setting inputs the real provider
/// watches.
class _EngineGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _generation = NotifierProvider<_EngineGeneration, int>(
  _EngineGeneration.new,
);

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(sttModel: 'whisper-small');
}

class _Downloads extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
}

Uint8List _wav() {
  // One second of 16 kHz mono silence behind a RIFF/WAVE header.
  final bytes = Uint8List(44 + 32000);
  bytes.setAll(0, 'RIFF'.codeUnits);
  bytes.setAll(8, 'WAVE'.codeUnits);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('stt_engine_swap_');
    await File(
      '${dir.path}/${findSttModel('whisper-small')!.filename}',
    ).writeAsBytes(Uint8List(11 * 1024 * 1024));
    paths.sttDirOverride = dir.path;
  });

  tearDown(() async {
    paths.sttDirOverride = null;
    await dir.delete(recursive: true);
  });

  test(
    'a replaced engine is followed, not kept as a dead "ready" engine',
    () async {
      final engines = <_Engine>[];
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWith((ref) {
            ref.watch(_generation);
            final engine = _Engine();
            engines.add(engine);
            // Mirrors the production provider's `onDispose(engine.shutdown)`.
            ref.onDispose(() => engine.loaded = false);
            return engine;
          }),
          settingsProvider.overrideWith(_Settings.new),
          modelDownloadProvider.overrideWith(_Downloads.new),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      // In the app the UI watches the STT status; Riverpod pauses the
      // subscriptions of an unwatched provider.
      container.listen(localSttBundleProvider, (_, _) {});
      final stt = container.read(localSttBundleProvider.notifier);

      await stt.ensureRunning();
      expect(container.read(localSttBundleProvider).isReady, isTrue);

      // GPU detection resolves → the provider builds a new engine and shuts
      // the old one down.
      container.read(_generation.notifier).bump();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(localSttBundleProvider).isReady,
        isFalse,
        reason: 'the loaded engine is gone — state must not claim ready',
      );

      await stt.ensureRunning();
      expect(await stt.transcribeBytes(_wav(), language: 'en'), 'transcript');
      expect(engines, hasLength(2));
      expect(engines.last.loads, 1);
      expect(engines.last.transcribes, greaterThan(0));
    },
  );
}

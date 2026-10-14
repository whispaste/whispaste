/// E2E for the GPU Parakeet engine inside the real app bundle: the real
/// download (network, size checks, SHA-256 of the GGUF), the real
/// libparakeet from `Frameworks/` (Metal on macOS, Vulkan/CUDA elsewhere),
/// the real sherpa-onnx fallback, and the edge inputs that crashed the
/// Windows benchmark (empty and sub-100 ms audio).
///
/// It downloads ~1.2 GB on the first run, so it is opt-in:
///   WP_PARAKEET_E2E=1 flutter test integration_test/parakeet_gpu_end_to_end_test.dart -d macos
/// The files land in `<system temp>/whispaste-parakeet-e2e/` (never the
/// user's model folder) and are reused by later runs.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_engine_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_policy.dart';

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

/// 16 kHz mono 16-bit PCM WAV around [pcm].
Uint8List _wav(Uint8List pcm) {
  final b = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add(_u32(36 + pcm.length))
    ..add('WAVEfmt '.codeUnits)
    ..add(_u32(16))
    ..add([1, 0, 1, 0])
    ..add(_u32(16000))
    ..add(_u32(32000))
    ..add([2, 0, 16, 0])
    ..add('data'.codeUnits)
    ..add(_u32(pcm.length))
    ..add(pcm);
  return b.toBytes();
}

List<int> _u32(int v) => [v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255];

ProviderContainer _container({required String gpuAcceleration}) {
  final settings = AppSettings.defaults.copyWithSections(
    behavior: AppSettings.defaults.behavior.copyWith(
      gpuAcceleration: gpuAcceleration,
    ),
  );
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _FixedSettingsNotifier(settings)),
    ],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final enabled =
      Platform.environment['WP_PARAKEET_E2E'] == '1' ||
      const bool.fromEnvironment('WP_PARAKEET_E2E');
  final skip = enabled
      ? null
      : 'opt-in: downloads ~1.2 GB (set WP_PARAKEET_E2E=1 or '
            '--dart-define=WP_PARAKEET_E2E=true)';

  final hello = File(p.join('test', 'fixtures', 'hotkey_happy_path_hello.wav'));

  setUpAll(() {
    final dir = Directory(
      p.join(Directory.systemTemp.path, 'whispaste-parakeet-e2e'),
    )..createSync(recursive: true);
    sttDirOverride = dir.path;
  });
  tearDownAll(() => sttDirOverride = null);

  testWidgets(
    'download → GPU engine → sherpa fallback → edge inputs',
    (tester) async {
      await tester.runAsync(() async {
        expect(
          File(parakeetGpuLibraryPath()).existsSync(),
          isTrue,
          reason: 'libparakeet must ship in the bundle',
        );

        // 1. The real download, as the settings button runs it.
        final gpu = _container(gpuAcceleration: 'auto');
        addTearDown(gpu.dispose);
        await gpu.read(settingsProvider.future);
        await gpu.read(parakeetDownloadProvider.notifier).downloadBundle();
        final download = gpu.read(parakeetDownloadProvider);
        expect(download.phase, ParakeetDownloadPhase.done, reason: '$download');
        expect(
          await verifyParakeetGguf(parakeetGgufPath(), parakeetGgufActive),
          ParakeetGgufCheck.ok,
        );

        // 2. GPU engine.
        final wav = await hello.readAsBytes();
        final engine = gpu.read(parakeetEngineProvider.notifier);
        await engine.ensureRunning();
        expect(gpu.read(parakeetEngineProvider).backend, ParakeetBackend.gpu);
        final gpuText = (await engine.transcribeWavBytes(wav)).toLowerCase();
        expect(gpuText, contains('hello'));

        // 3. Edge inputs that aborted sherpa-onnx natively on Windows.
        expect(await engine.transcribeWavBytes(_wav(Uint8List(0))), isEmpty);
        expect(await engine.transcribeWavBytes(_wav(Uint8List(200))), isEmpty);
        await engine.stop();

        // 4. CPU only (GPU acceleration disabled): the sherpa-onnx fallback.
        final cpu = _container(gpuAcceleration: 'disabled');
        addTearDown(cpu.dispose);
        await cpu.read(settingsProvider.future);
        final fallback = cpu.read(parakeetEngineProvider.notifier);
        await fallback.ensureRunning();
        expect(
          cpu.read(parakeetEngineProvider).backend,
          ParakeetBackend.sherpaCpu,
        );
        final cpuText = (await fallback.transcribeWavBytes(wav)).toLowerCase();
        expect(cpuText, contains('hello'));
        expect(await fallback.transcribeWavBytes(_wav(Uint8List(0))), isEmpty);
        expect(
          await fallback.transcribeWavBytes(_wav(Uint8List(200))),
          isEmpty,
        );
        await fallback.stop();
      });
    },
    skip: skip != null,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

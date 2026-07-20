/// Contract tests for the [WhisperEngine] seam: the handwritten
/// [_FakeWhisperEngine] must satisfy the same contract the real FFI engine
/// does, and [whisperEngineProvider] must be overrideable for injection.
///
/// Mirrors the repo's fake convention (`_FakeProcessRunner` /
/// `FakeSttService`) — a configurable, handwritten fake, no Mockito.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_isolate_engine.dart';

/// Mirrors the repo's `_FakeSettingsNotifier` convention (see
/// `stt_server_state_notifier_test.dart`) — avoids constructing the real
/// drift [HistoryDatabase] that [settingsProvider] otherwise pulls in, which
/// is unrelated to what these tests check and just adds noise/multiple-DB
/// warnings across the many isolated [ProviderContainer]s below.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeWhisperEngine implements WhisperEngine {
  _FakeWhisperEngine({
    this.transcript = 'fake transcript',
    this.throwOnTranscribe,
    this.transcribeDelay,
    this.backend = WhisperBackend.cpu,
  });

  /// Text returned by [transcribe] on success.
  String transcript;

  /// If set, [transcribe] throws this instead of returning [transcript].
  Object? throwOnTranscribe;

  /// If set, [transcribe] waits this long before completing (simulated work).
  Duration? transcribeDelay;

  final WhisperBackend backend;

  bool _loaded = false;
  String? _lastLanguage;
  String? _lastPrompt;
  int transcribeCallCount = 0;

  String? get lastLanguage => _lastLanguage;

  /// The `prompt` passed to the most recent [transcribe] call, or `null` if
  /// none was given.
  String? get lastPrompt => _lastPrompt;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: backend);

  @override
  Future<void> load({required String modelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
  }) async {
    transcribeCallCount++;
    _lastLanguage = language;
    _lastPrompt = prompt;
    if (transcribeDelay != null) {
      await Future<void>.delayed(transcribeDelay!);
    }
    final err = throwOnTranscribe;
    if (err != null) throw err;
    return transcript;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

void main() {
  group('_FakeWhisperEngine contract', () {
    test('returns configured transcript and records language', () async {
      final engine = _FakeWhisperEngine(transcript: 'hallo welt');

      await engine.load(modelPath: '/fake/model.bin');
      final text = await engine.transcribe(const [0, 1, 2], language: 'de');

      expect(text, 'hallo welt');
      expect(engine.lastLanguage, 'de');
      expect(engine.transcribeCallCount, 1);
    });

    test('records the prompt passed to transcribe (Issue 22)', () async {
      final engine = _FakeWhisperEngine(transcript: 'hallo welt');

      await engine.load(modelPath: '/fake/model.bin');
      expect(engine.lastPrompt, isNull);

      await engine.transcribe(
        const [0, 1, 2],
        language: 'de',
        prompt: 'Fachbegriff, Eigenname',
      );

      expect(engine.lastPrompt, 'Fachbegriff, Eigenname');
    });

    test('surfaces the configured error on failure', () async {
      final engine = _FakeWhisperEngine(throwOnTranscribe: StateError('boom'));

      await engine.load(modelPath: '/fake/model.bin');

      expect(
        () => engine.transcribe(const [0, 1, 2]),
        throwsA(isA<StateError>()),
      );
    });

    test('simulates a transcription delay', () async {
      final engine = _FakeWhisperEngine(
        transcribeDelay: const Duration(milliseconds: 120),
      );
      await engine.load(modelPath: '/fake/model.bin');

      final sw = Stopwatch()..start();
      await engine.transcribe(const [0, 1, 2]);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100));
    });

    test('reports load state and backend via status', () async {
      final engine = _FakeWhisperEngine(backend: WhisperBackend.metal);
      expect(engine.status.isLoaded, isFalse);

      await engine.load(modelPath: '/fake/model.bin');
      expect(engine.status.isLoaded, isTrue);
      expect(engine.status.backend, WhisperBackend.metal);

      await engine.unload();
      expect(engine.status.isLoaded, isFalse);
    });
  });

  group('whisperEngineProvider', () {
    test('defaults to a WhisperIsolateEngine wrapping the real FFI engine', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(whisperEngineProvider),
        isA<WhisperIsolateEngine>(),
      );
    });

    test('is overrideable with a fake', () async {
      final fake = _FakeWhisperEngine(transcript: 'injected');
      final container = ProviderContainer(
        overrides: [whisperEngineProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final engine = container.read(whisperEngineProvider);
      await engine.load(modelPath: '/fake/model.bin');

      expect(await engine.transcribe(const [0, 1, 2]), 'injected');
    });
  });

  group('whisperEngineProvider backend selection from gpuInfoProvider', () {
    Future<WhisperBackend> backendForGpu(
      GpuInfo gpu, {
      String gpuAcceleration = 'auto',
    }) async {
      final container = ProviderContainer(
        overrides: [
          gpuInfoProvider.overrideWith((_) async => gpu),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(gpuAcceleration: gpuAcceleration),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(gpuInfoProvider.future);
      await container.read(settingsProvider.future);
      return container.read(whisperEngineProvider).status.backend;
    }

    test('NVIDIA GPU with CUDA → CUDA backend', () async {
      final backend = await backendForGpu(
        const GpuInfo(
          vendor: GpuVendor.nvidia,
          name: 'NVIDIA RTX 4090',
          vramMB: 24576,
          cudaAvailable: true,
          vulkanAvailable: true,
        ),
      );
      expect(backend, WhisperBackend.cuda);
    });

    test('Apple GPU → Metal backend', () async {
      final backend = await backendForGpu(
        const GpuInfo(vendor: GpuVendor.apple, name: 'Apple M2 Pro'),
      );
      expect(backend, WhisperBackend.metal);
    });

    test('AMD GPU → Vulkan backend', () async {
      final backend = await backendForGpu(
        const GpuInfo(vendor: GpuVendor.amd, name: 'AMD Radeon RX 7900 XTX'),
      );
      expect(backend, WhisperBackend.vulkan);
    });

    test('Intel GPU → Vulkan backend', () async {
      final backend = await backendForGpu(
        const GpuInfo(vendor: GpuVendor.intel, name: 'Intel Arc A770'),
      );
      expect(backend, WhisperBackend.vulkan);
    });

    test('no/incompatible GPU → CPU backend', () async {
      final backend = await backendForGpu(
        const GpuInfo(vendor: GpuVendor.none, name: 'No GPU detected'),
      );
      expect(backend, WhisperBackend.cpu);
    });

    test(
      'gpuAcceleration=disabled ("Nur CPU") forces CPU even with a GPU present',
      () async {
        final backend = await backendForGpu(
          const GpuInfo(vendor: GpuVendor.nvidia, name: 'NVIDIA RTX 4090'),
          gpuAcceleration: 'disabled',
        );
        expect(backend, WhisperBackend.cpu);
      },
    );

    test(
      'gpuAcceleration=enabled ("GPU erzwingen") still uses the detected GPU backend',
      () async {
        final backend = await backendForGpu(
          const GpuInfo(vendor: GpuVendor.amd, name: 'AMD Radeon RX 7900 XTX'),
          gpuAcceleration: 'enabled',
        );
        expect(backend, WhisperBackend.vulkan);
      },
    );
  });
}

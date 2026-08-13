/// Regression tests for the post-load benchmark's queue priority.
///
/// The whisper worker processes one request at a time and knows no
/// priorities. Before this was fixed, `_start()` fired the benchmark
/// inference the moment the warmup returned — so a dictation the user had
/// already started landed *behind* 3 s of synthetic benchmark audio. In a
/// captured cold-start session that cost 16 s (hotkey at 14:19:05, transcript
/// only at 14:19:37), which reads as "the app stopped responding".
///
/// The seam under test is deliberately the notifier, not the engine: the bug
/// is one of ordering between two callers sharing a serial worker, so the
/// assertion is on the *sequence* of `transcribe` calls the engine sees.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

// ---------------------------------------------------------------------------
// Payload sizes — the discriminator between the three request kinds
// ---------------------------------------------------------------------------

/// `_generateSilentWav()`: 0.25 s of 16 kHz mono 16-bit silence + 44-byte
/// header.
const _warmupBytes = 44 + (16000 ~/ 4) * 2;

/// `SttBenchmark.generateBenchmarkWav()`: 3 s at the same format.
const _benchmarkBytes = 44 + 16000 * 3 * 2;

/// What [_validWav] below produces for the simulated real dictation.
const _dictationBytes = 44 + 16000;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Records the order in which requests reach the (serial) worker, and can
/// hold the first one open so a test can interleave a user action with an
/// inference that is still in flight.
class _QueueRecordingEngine implements WhisperEngine {
  bool _loaded = false;

  /// Byte length of every [transcribe] payload, in arrival order.
  final List<int> transcribedSizes = [];

  /// Completes once the first [transcribe] call has entered the engine.
  final firstTranscribeStarted = Completer<void>();

  /// When set, the first [transcribe] blocks on this until [releaseGate].
  Completer<void>? _gate;

  void gateFirstTranscribe() => _gate = Completer<void>();

  void releaseGate() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
  }) async {
    transcribedSizes.add(wavBytes.length);
    if (!firstTranscribeStarted.isCompleted) firstTranscribeStarted.complete();
    final gate = _gate;
    if (gate != null) await gate.future;
    return 'fake transcript';
  }

  @override
  Future<void> unload() async {
    _loaded = false;
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

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(WhisperEngine engine) => ProviderContainer(
  overrides: [
    whisperEngineProvider.overrideWithValue(engine),
    settingsProvider.overrideWith(
      () => _FakeSettingsNotifier(
        AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
      ),
    ),
    modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
    hw.gpuInfoProvider.overrideWith(
      (_) async => const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
    ),
  ],
);

Future<Directory> _createFakeSttDir() async {
  final dir = await Directory.systemTemp.createTemp('stt_bench_defer_');
  final modelFilename =
      findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));
  paths.sttDirOverride = dir.path;
  return dir;
}

Uint8List _validWav({int dataBytes = 16000}) {
  final buf = Uint8List(44 + dataBytes);
  buf[0] = 0x52; // R
  buf[1] = 0x49; // I
  buf[2] = 0x46; // F
  buf[3] = 0x46; // F
  buf[8] = 0x57; // W
  buf[9] = 0x41; // A
  buf[10] = 0x56; // V
  buf[11] = 0x45; // E
  return buf;
}

/// Polls [condition] on the event loop. Used instead of a fixed delay so the
/// tests stay deterministic rather than timing-dependent.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Duration savedIdleDelay;

  setUp(() async {
    tempDir = await _createFakeSttDir();
    savedIdleDelay = SttServerStateNotifier.benchmarkIdleDelay;
    SttServerStateNotifier.benchmarkIdleDelay = const Duration(milliseconds: 5);
  });

  tearDown(() async {
    SttServerStateNotifier.benchmarkIdleDelay = savedIdleDelay;
    paths.sttDirOverride = null;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('a dictation already in progress is not queued behind the post-load '
      'benchmark', () async {
    final engine = _QueueRecordingEngine()..gateFirstTranscribe();
    final container = _makeContainer(engine);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(localSttBundleProvider.notifier);

    // Hold the warmup inference open and start dictating while it runs —
    // the exact interleaving from the captured cold start.
    final running = notifier.ensureRunning();
    await engine.firstTranscribeStarted.future;
    notifier.notifyRecordingStarted();
    engine.releaseGate();
    await running;

    // The load path has completed. The benchmark must still be waiting:
    // grabbing the worker here is what buried the user's dictation.
    expect(engine.transcribedSizes, [_warmupBytes]);

    final text = await notifier.transcribeBytes(_validWav(), language: 'en');
    expect(text, 'fake transcript');
    expect(engine.transcribedSizes, [_warmupBytes, _dictationBytes]);

    // Once the dictation is done the benchmark is free to run — deferring
    // it must not mean dropping it.
    notifier.notifyTranscriptionCompleted();
    await _waitUntil(() => engine.transcribedSizes.length == 3);
    expect(engine.transcribedSizes.last, _benchmarkBytes);
  });

  test(
    'with an idle pipeline the benchmark still runs right after the load',
    () async {
      final engine = _QueueRecordingEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);

      await notifier.ensureRunning();

      await _waitUntil(() => engine.transcribedSizes.length == 2);
      expect(engine.transcribedSizes, [_warmupBytes, _benchmarkBytes]);
    },
  );

  test('stop() drops a still-deferred benchmark instead of leaking it into '
      'the next engine', () async {
    final engine = _QueueRecordingEngine()..gateFirstTranscribe();
    final container = _makeContainer(engine);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(localSttBundleProvider.notifier);

    final running = notifier.ensureRunning();
    await engine.firstTranscribeStarted.future;
    notifier.notifyRecordingStarted();
    engine.releaseGate();
    await running;
    expect(engine.transcribedSizes, [_warmupBytes]);

    await notifier.stop();
    notifier.notifyTranscriptionCompleted();

    // Well past benchmarkIdleDelay — a surviving timer would have fired.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(engine.transcribedSizes, [_warmupBytes]);
  });
}

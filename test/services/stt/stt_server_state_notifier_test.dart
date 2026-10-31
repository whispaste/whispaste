/// Unit tests for SttServerStateNotifier (new modular notifier).
///
/// Uses [whisperEngineProvider] as the DI seam — the notifier drives the
/// in-process [WhisperEngine] instead of a `whisper-server` subprocess +
/// HTTP transport (Issue 03 cutover). Provider imports come from
/// [stt_bundle.dart].
///
/// Scope note (Issue 03, Nachtrag 2): the pre-cutover version of this file
/// also covered GPU-DLL-gate/`ServerBinaryRecovery`/heartbeat-stall/exit-code
/// fallback behavior driven by subprocess-spawn/crash mechanics that have no
/// equivalent against an in-process engine. Those tests were retired here
/// (not adapted) — see this issue's Evidence block `remaining_risks` for the
/// consolidated coverage-gap note, closed by Issue 04 (backend selection) and
/// Issue 05 (resilience).
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
// Fake helpers (self-contained; do not import from other test files)
// ---------------------------------------------------------------------------

/// Minimal header that passes the RIFF/WAVE pre-flight validator (see
/// `inference_request_validator_test.dart`'s identical helper — kept
/// duplicated per this file's self-contained-fakes convention above).
Uint8List _validWavHeader({int totalLength = 44}) {
  final bytes = Uint8List(totalLength);
  bytes[0] = 0x52; // R
  bytes[1] = 0x49; // I
  bytes[2] = 0x46; // F
  bytes[3] = 0x46; // F
  bytes[8] = 0x57; // W
  bytes[9] = 0x41; // A
  bytes[10] = 0x56; // V
  bytes[11] = 0x45; // E
  return bytes;
}

/// A [Stopwatch] that reports a scripted elapsed time, for benchmark runs
/// whose measured runtime the test decides (see
/// `SttServerStateNotifier.benchmarkStopwatch`).
class _ScriptedStopwatch implements Stopwatch {
  _ScriptedStopwatch(this._elapsedMs);

  final int _elapsedMs;

  @override
  int get elapsedMilliseconds => _elapsedMs;

  @override
  int get elapsedMicroseconds =>
      _elapsedMs * Duration.microsecondsPerMillisecond;

  @override
  int get elapsedTicks => elapsedMicroseconds; // frequency is 1 MHz

  @override
  Duration get elapsed => Duration(milliseconds: _elapsedMs);

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => false;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void reset() {}
}

class _FakeWhisperEngine implements WhisperEngine {
  bool _loaded = false;
  String? lastModelPath;
  int loadCallCount = 0;

  /// The backend [status] reports once loaded — mutable so tests can prove
  /// [SttStatus.backend] actually reads this rather than assuming CPU.
  WhisperBackend backend = WhisperBackend.cpu;

  /// If set, [transcribe] waits this long before completing — simulates
  /// slower/faster hardware for benchmark-driven tier-selection tests.
  Duration? transcribeDelay;

  /// If set, [unload] waits on this completer instead of resolving
  /// immediately — lets a test prove a caller actually awaits [unload]
  /// rather than firing-and-forgetting it (FLUTTER_WHISPASTE-BC).
  Completer<void>? unloadGate;
  bool unloadCalled = false;

  /// Set when [unload] runs while a [transcribe] call has not returned yet.
  bool unloadedWhileDecoding = false;
  int _decodesRunning = 0;

  /// The `prompt` argument of the most recent [transcribe] call — lets
  /// tests assert on what [SttServerStateNotifier] actually resolved/
  /// truncated the effective prompt to, without needing to intercept the
  /// engine seam any deeper.
  String? lastPrompt;

  /// The raw text [transcribe] returns; tests override it to simulate what
  /// whisper.cpp emits on silence or noise.
  String responseText = 'fake transcript';

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: backend);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    loadCallCount++;
    lastModelPath = modelPath;
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
    lastPrompt = prompt;
    _decodesRunning++;
    try {
      final delay = transcribeDelay;
      if (delay != null) {
        await Future<void>.delayed(delay);
      }
      return responseText;
    } finally {
      _decodesRunning--;
    }
  }

  @override
  Future<void> unload() async {
    unloadCalled = true;
    if (_decodesRunning > 0) unloadedWhileDecoding = true;
    final gate = unloadGate;
    if (gate != null) await gate.future;
    _loaded = false;
  }
}

/// A [_FakeWhisperEngine] that also implements [PromptTokenCounter] with a
/// deterministic one-token-per-word tokenizer (see
/// `prompt_token_budget_test.dart`'s identical fake) — proves
/// [SttServerStateNotifier] actually probes for and uses the capability to
/// truncate an over-budget prompt (prompt-token-budget fix), rather than
/// only exercising the plain-[WhisperEngine] fallback path.
class _FakeWhisperEngineWithTokenCounter extends _FakeWhisperEngine
    implements PromptTokenCounter {
  @override
  Future<int> countPromptTokens(String text) async {
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
}

/// Like the native engine: a transcription that finds the model unloaded, or
/// loses it while running, fails with whisper_engine_not_loaded (Sentry
/// 120963723).
class _UnloadAwareEngine extends _FakeWhisperEngine {
  int _inFlight = 0;

  /// True when the engine was unloaded while a transcription was running on it.
  bool unloadedDuringTranscribe = false;

  @override
  Future<void> unload() {
    if (_inFlight > 0) unloadedDuringTranscribe = true;
    return super.unload();
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async {
    if (!status.isLoaded) throw StateError('whisper_engine_not_loaded');
    _inFlight++;
    try {
      final text = await super.transcribe(
        wavBytes,
        language: language,
        prompt: prompt,
        vadEnabled: vadEnabled,
        reducedThreads: reducedThreads,
      );
      if (!status.isLoaded) throw StateError('whisper_engine_not_loaded');
      return text;
    } finally {
      _inFlight--;
    }
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
  int downloadModelCalls = 0;
  String? lastDownloadedModelId;

  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});

  @override
  Future<void> downloadModel(String modelId) async {
    downloadModelCalls += 1;
    lastDownloadedModelId = modelId;
    state = ModelDownloadState(downloadedModels: {modelId});
  }
}

ProviderContainer _makeContainer({
  required WhisperEngine engine,
  AppSettings? settings,
}) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ?? AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

/// Creates a temporary directory with a fake GGML model file large enough to
/// pass the minimum-size guard (>10 MB). Returns the temp dir; caller is
/// responsible for cleanup. No whisper-server binary is written — the engine
/// seam has no subprocess to spawn.
Future<Directory> _createFakeSttDir({String modelId = 'whisper-small'}) async {
  final dir = await Directory.systemTemp.createTemp('stt_notifier_test_');

  final modelFilename =
      findSttModel(modelId)?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));

  paths.sttDirOverride = dir.path;
  return dir;
}

/// Writes a second fake model file for [modelId] into an existing
/// [dir] created by [_createFakeSttDir] — used by tests that switch the
/// active model between two quality tiers.
Future<void> _addFakeModelFile(Directory dir, String modelId) async {
  final modelFilename = findSttModel(modelId)?.filename ?? '$modelId.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));
}

/// Polls [settingsProvider] until a benchmark RTF has been stored for
/// [tier], or fails after [timeout]. The notifier fires `_runBenchmark`
/// un-awaited (fire-and-forget after `_start` returns), so tests must wait
/// for the background `engine.transcribe()` + settings write to land.
Future<void> _waitForBenchmarkStored(
  ProviderContainer container,
  QualityTier tier, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final rtfMap = container.read(settingsProvider).value?.tierBenchmarkRtf;
    if (rtfMap != null && rtfMap.containsKey(tier)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Benchmark result for $tier was not stored within $timeout');
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
      final container = _makeContainer(engine: _FakeWhisperEngine());
      addTearDown(container.dispose);

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.stopped);
    });

    test('ensureRunning() transitions to ready on healthy engine', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.ready);
      expect(engine.loadCallCount, 1);
      expect(engine.lastModelPath, isNotNull);
    });

    test('ensureRunning() surfaces the engine\'s actual backend in '
        'SttStatus.backend', () async {
      final engine = _FakeWhisperEngine()..backend = WhisperBackend.metal;
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      expect(
        container.read(localSttBundleProvider).backend,
        WhisperBackend.metal,
      );
    });

    test('stop() transitions to stopped', () async {
      final container = _makeContainer(engine: _FakeWhisperEngine());
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );

      await notifier.stop();
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
      );
    });

    test('stop() transitions state to stopped synchronously (before awaiting '
        'engine.unload()), but its own returned Future only completes once '
        'unload() actually finishes (FLUTTER_WHISPASTE-BC)', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      final gate = Completer<void>();
      engine.unloadGate = gate;

      var stopCompleted = false;
      final stopFuture = notifier.stop().then((_) => stopCompleted = true);

      // UI responsiveness: the state flips to stopped immediately, without
      // waiting for the engine to actually free its native resources.
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
        reason: 'state must transition before unload() resolves',
      );
      expect(engine.unloadCalled, isTrue);
      expect(
        stopCompleted,
        isFalse,
        reason:
            "stop()'s own Future must not complete until unload() does — "
            'otherwise a caller like app.dart\'s onWindowClose (app quit) '
            'proceeds to destroy the window/process while native GPU '
            'resources are still allocated, aborting the process '
            '(ggml_metal_rsets_free\'s teardown assertion).',
      );

      gate.complete();
      await stopFuture;
      expect(stopCompleted, isTrue);
    });

    test('stop() waits for an in-flight transcribeBytes() before unloading '
        'the engine, instead of racing it into '
        '"whisper_engine_not_loaded" (FLUTTER_WHISPASTE-6X)', () async {
      final engine = _FakeWhisperEngine()
        ..transcribeDelay = const Duration(milliseconds: 30);
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      // Started but not yet awaited: transcribeBytes() has already passed
      // its readiness check and incremented the in-flight counter by the
      // time this call returns control (no await before that point).
      final transcribeFuture = notifier.transcribeBytes(_validWavHeader());

      // A concurrent trigger (idle timer, model switch, OOM fallback) calls
      // stop() while the transcription above is still in flight.
      await notifier.stop();

      expect(
        await transcribeFuture,
        'fake transcript',
        reason:
            'the in-flight request must complete successfully — stop() must '
            'not have torn down the engine out from under it',
      );
      expect(engine.unloadCalled, isTrue);
    });

    test('stop() unloads only after an in-flight native decode has returned, '
        'never under it (FLUTTER_WHISPASTE-6X)', () async {
      final engine = _FakeWhisperEngine()
        ..transcribeDelay = const Duration(milliseconds: 300);
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      unawaited(notifier.transcribeBytes(_validWavHeader()));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await notifier.stop();

      expect(
        engine.unloadCalled,
        isTrue,
        reason: 'the engine is freed once the decode returned',
      );
      expect(
        engine.unloadedWhileDecoding,
        isFalse,
        reason:
            'unloading under a running native decode raced into '
            'whisper_engine_not_loaded',
      );
    });

    test('stopForQuit() does not wait for a running decode — app quit must '
        'not stall behind a still-running transcription', () async {
      final engine = _FakeWhisperEngine()
        ..transcribeDelay = const Duration(milliseconds: 400);
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      unawaited(notifier.transcribeBytes(_validWavHeader()));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await notifier.stopForQuit();

      expect(notifier.hasNativeCallRunning, isTrue);
      expect(engine.unloadCalled, isFalse);

      // The retired engine is released once its decode returns, never before.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(notifier.hasNativeCallRunning, isFalse);
      expect(engine.unloadCalled, isTrue);
      expect(engine.unloadedWhileDecoding, isFalse);
    });
  });

  group('SttServerStateNotifier — notify methods', () {
    test(
      'notifyRecordingStarted/Stopped do not throw when server is stopped',
      () {
        final container = _makeContainer(engine: _FakeWhisperEngine());
        addTearDown(container.dispose);

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

  // ---------------------------------------------------------------------------
  // Pure decision function — isSttModelFileTooSmall (AC3)
  // ---------------------------------------------------------------------------

  group('isSttModelFileTooSmall — pure decision function', () {
    // Table-driven: each entry is (fileSizeBytes, expected)
    const cases = <(int, bool)>[
      (0, true), // empty file
      (1024, true), // 1 KB — clearly truncated
      (9 * 1024 * 1024, true), // 9 MiB — just below threshold
      (10 * 1024 * 1024 - 1, true), // one byte below threshold
      (10 * 1024 * 1024, false), // exactly at threshold — not corrupt
      (11 * 1024 * 1024, false), // 11 MiB — healthy model
      (200 * 1024 * 1024, false), // 200 MiB — large model, healthy
    ];

    for (final (size, expected) in cases) {
      test('${size ~/ 1024} KB → isTooSmall=$expected', () {
        expect(isSttModelFileTooSmall(size), equals(expected));
      });
    }

    test('custom minModelBytes threshold is respected', () {
      // 5 MiB min — a 6 MiB file should pass.
      expect(
        isSttModelFileTooSmall(6 * 1024 * 1024, minModelBytes: 5 * 1024 * 1024),
        isFalse,
      );
      // Same 6 MiB file fails against the default 10 MiB threshold.
      expect(isSttModelFileTooSmall(6 * 1024 * 1024), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Corrupt/too-small model → silent re-download (AC1, AC2)
  // ---------------------------------------------------------------------------

  group('SttServerStateNotifier — corrupt model auto-reload', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('too-small model file triggers silent re-download via '
        'modelDownloadProvider (AC1, AC2)', () async {
      // Overwrite the 11 MiB model that _createFakeSttDir wrote with a
      // truncated 1 KiB stub — simulating an interrupted download.
      final modelFilename =
          findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
      final modelFile = File('${tempDir.path}/$modelFilename');
      await modelFile.writeAsBytes(Uint8List(1024)); // 1 KB — below 10 MiB

      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      // The notifier must park in `stopped` (mirroring the SHA-mismatch
      // self-heal path) and hand off to modelDownloadProvider.downloadModel.
      final status = container.read(localSttBundleProvider);
      expect(
        status.serverState,
        SttServerState.stopped,
        reason:
            'corrupt model path must park in stopped, not error '
            '(consistent with SHA-mismatch self-heal — AC2)',
      );

      final download =
          container.read(modelDownloadProvider.notifier)
              as _FakeModelDownloadNotifier;
      expect(
        download.downloadModelCalls,
        1,
        reason: 'silent re-download must be triggered exactly once (AC1)',
      );
      expect(
        download.lastDownloadedModelId,
        'whisper-small',
        reason: 're-download must request the active model id',
      );
      // The engine must NOT have been loaded for a corrupt model.
      expect(
        engine.loadCallCount,
        0,
        reason: 'no engine load must be attempted for a corrupt model file',
      );
    });

    test(
      'healthy 11 MiB model file does NOT trigger re-download (regression guard)',
      () async {
        // _createFakeSttDir already writes an 11 MiB file — no override needed.
        final container = _makeContainer(engine: _FakeWhisperEngine());
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        final download =
            container.read(modelDownloadProvider.notifier)
                as _FakeModelDownloadNotifier;
        expect(
          download.downloadModelCalls,
          0,
          reason: 'a healthy model must never trigger a silent re-download',
        );
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Benchmark via engine seam — Issue 15 (AC1, AC3)
  // ---------------------------------------------------------------------------

  group('SttServerStateNotifier — benchmark via engine seam', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('benchmark measures engine.transcribe and stores RTF for the active '
        "model's tier (AC1)", () async {
      final engine = _FakeWhisperEngine()
        ..transcribeDelay = const Duration(milliseconds: 60);
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      await _waitForBenchmarkStored(container, QualityTier.compact);

      final settings = container.read(settingsProvider).value!;
      final rtf = settings.tierBenchmarkRtf![QualityTier.compact]!;
      expect(rtf, greaterThanOrEqualTo(0.0));
      expect(
        rtf,
        lessThan(kFluentRtf),
        reason: 'a 60ms transcribe over the benchmark clip must read as fast',
      );
      // The machine key is the hardware plus the app build (see
      // benchmarkMachineKey); this test machine has no GPU.
      expect(settings.benchmarkHardwareId, startsWith('cpu|'));
      expect(settings.benchmarkTimestamp, isNotNull);
    });

    test('tier auto-selection reflects variable simulated engine runtimes: a '
        'slow compact tier is skipped in favor of a faster balanced tier '
        '(AC3)', () async {
      await _addFakeModelFile(tempDir, 'whisper-medium');

      // Measured runtimes are scripted per run, so the test needs no real
      // inference time: the slow compact run takes as long as the clip
      // (RTF 1.0), the fast balanced run 2 % of it.
      final clipMs = SttBenchmark.durationMs(await SttBenchmark.referenceWav());
      final runtimesMs = [clipMs, clipMs ~/ 50];
      SttServerStateNotifier.benchmarkStopwatch = () =>
          _ScriptedStopwatch(runtimesMs.removeAt(0));
      addTearDown(
        () => SttServerStateNotifier.benchmarkStopwatch = Stopwatch.new,
      );

      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);

      // Slow compact-tier model — simulates weak/old hardware.
      await notifier.ensureRunning();
      await _waitForBenchmarkStored(container, QualityTier.compact);

      // Switch the active model to the balanced tier with a fast
      // simulated runtime — simulates capable hardware.
      await container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttModel: 'whisper-medium'));
      await notifier.ensureRunning();
      await _waitForBenchmarkStored(container, QualityTier.balanced);

      final rtfMap = container.read(settingsProvider).value!.tierBenchmarkRtf!;
      expect(
        rtfMap[QualityTier.compact],
        greaterThanOrEqualTo(kFluentRtf),
        reason: 'a run as long as the benchmark clip must read as slow',
      );
      expect(
        rtfMap[QualityTier.balanced],
        lessThan(kFluentRtf),
        reason: 'a run at 2 % of the clip length must read as fast',
      );

      expect(
        recommendTierFromBenchmark(rtfMap),
        QualityTier.balanced,
        reason:
            'the slower compact tier must be skipped for the faster '
            'balanced tier the simulated hardware actually delivers',
      );
    });
  });

  group(
    'SttServerStateNotifier — prompt token budget (silent-truncation fix)',
    () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await _createFakeSttDir();
      });

      tearDown(() async {
        paths.sttDirOverride = null;
        await tempDir.delete(recursive: true);
      });

      test(
        'a short customVocabulary is forwarded to the engine unchanged',
        () async {
          final engine = _FakeWhisperEngineWithTokenCounter();
          final container = _makeContainer(
            engine: engine,
            settings: AppSettings.defaults.copyWith(
              sttModel: 'whisper-small',
              customVocabulary: 'WhisPaste Kubernetes',
            ),
          );
          addTearDown(container.dispose);

          await container.read(settingsProvider.future);
          final notifier = container.read(localSttBundleProvider.notifier);
          await notifier.ensureRunning();
          await notifier.transcribeBytes(_validWavHeader());

          expect(engine.lastPrompt, 'WhisPaste Kubernetes');
        },
      );

      test('a known whisper hallucination on silence is dropped to an empty '
          'transcript instead of being pasted', () async {
        final engine = _FakeWhisperEngine()
          ..responseText = 'Thanks for watching!';
        final container = _makeContainer(
          engine: engine,
          settings: AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();
        final text = await notifier.transcribeBytes(_validWavHeader());

        expect(text, isEmpty);
      });

      test('a customVocabulary over the real token budget is truncated to the '
          'budget instead of being silently dropped inside whisper.cpp with '
          'no signal anywhere in the app', () async {
        final engine = _FakeWhisperEngineWithTokenCounter();
        final words = List.generate(100, (i) => 'term$i');
        final container = _makeContainer(
          engine: engine,
          settings: AppSettings.defaults.copyWith(
            sttModel: 'whisper-small',
            customVocabulary: words.join(' '),
          ),
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();
        await notifier.transcribeBytes(_validWavHeader());

        expect(engine.lastPrompt, words.take(63).join(' '));
      });

      test(
        'without a PromptTokenCounter-capable engine, an over-budget '
        'customVocabulary is still forwarded unmodified (conservative '
        'fallback — no crash, no regression from pre-fix behaviour)',
        () async {
          final engine = _FakeWhisperEngine();
          final vocab = List.generate(100, (i) => 'term$i').join(' ');
          final container = _makeContainer(
            engine: engine,
            settings: AppSettings.defaults.copyWith(
              sttModel: 'whisper-small',
              customVocabulary: vocab,
            ),
          );
          addTearDown(container.dispose);

          await container.read(settingsProvider.future);
          final notifier = container.read(localSttBundleProvider.notifier);
          await notifier.ensureRunning();
          await notifier.transcribeBytes(_validWavHeader());

          expect(engine.lastPrompt, vocab);
        },
      );
    },
  );

  // SW-04: lifecycle stress. Interleaves ensureRunning, stop, transcribeBytes
  // and model switches (which fire the debounced prewarm) for 100 cycles. The
  // invariant: no unexpected StateError. A transcription that arrives while
  // the server is stopped gets the typed "not running" rejection and is not
  // counted.
  group('SttServerStateNotifier — lifecycle stress (SW-04)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
      await _addFakeModelFile(tempDir, 'whisper-medium');
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test(
      '100 cycles of parallel ensureRunning, stop, transcribeBytes and model '
      'switches raise no StateError or whisper_engine_not_loaded',
      () async {
        // Transcriptions run long enough for stop() and the model switch to
        // land while one is in flight.
        final engine = _UnloadAwareEngine()
          ..transcribeDelay = const Duration(milliseconds: 20);
        final container = _makeContainer(engine: engine);
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        final failures = <String>[];
        var transcribed = 0;

        Future<void> guarded(
          String label,
          Future<Object?> Function() call,
        ) async {
          try {
            final result = await call();
            if (label == 'transcribeBytes' && result is String) transcribed++;
          } catch (e) {
            final text = '$e';
            // A transcription that arrives while the server is stopped gets
            // the typed "not running" rejection up front. That is the
            // intended answer, not the race under test.
            if (text.contains('STT server is not running')) return;
            if (text.contains('whisper_engine_not_loaded') || e is StateError) {
              failures.add('$label: $text');
            }
          }
        }

        for (var cycle = 0; cycle < 100; cycle++) {
          final model = cycle.isEven ? 'whisper-medium' : 'whisper-small';
          // Phase 1: start and stop race each other.
          await Future.wait<void>([
            guarded('ensureRunning', () => notifier.ensureRunning()),
            guarded('stop', () => notifier.stop()),
          ]);
          // Phase 2: a transcription is in flight when stop() and the model
          // switch land on top of it.
          await guarded('ensureRunning', () => notifier.ensureRunning());
          final transcription = guarded(
            'transcribeBytes',
            () => notifier.transcribeBytes(_validWavHeader()),
          );
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await Future.wait<void>([
            transcription,
            guarded('stop', () => notifier.stop()),
            guarded(
              'modelSwitch',
              () => container
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(sttModel: model)),
            ),
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }

        // Let the last debounced prewarm (500 ms) run to completion.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await guarded('ensureRunning', () => notifier.ensureRunning());

        final byKind = <String, int>{};
        for (final f in failures) {
          byKind.update(f, (n) => n + 1, ifAbsent: () => 1);
        }
        expect(
          failures,
          isEmpty,
          reason: '${failures.length} StateErrors: $byKind',
        );
        // Guards against a vacuous pass: some transcriptions must have run.
        expect(transcribed, greaterThan(0));
      },
    );

    test('a model switch whose restart starts during a running transcription '
        'does not unload the engine under it (SW-04)', () async {
      final engine = _UnloadAwareEngine()
        ..transcribeDelay = const Duration(milliseconds: 2500);
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      final transcription = notifier.transcribeBytes(_validWavHeader());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttModel: 'whisper-medium'));

      // The restart runs while the 2.5 s transcription is still in flight,
      // past the 1 s stop drain window.
      await notifier.ensureRunning();
      expect(await transcription, 'fake transcript');
      expect(engine.unloadedDuringTranscribe, isFalse);
    });
  });
}

/// Resilience tests for [SttServerStateNotifier] against distinguishable FFI
/// failure signals (internal-notes §3.3): CPU-fallback on GPU crash, OOM-recovery
/// trigger, stuck-guard timeout, and transient retry.
///
/// The subprocess-era chain keyed on process exit codes; the in-process engine
/// signals a typed [WhisperEngineException] instead. These tests drive each
/// failure class through the public [SttServerStateNotifier.transcribeBytes]
/// surface via a fake engine, asserting only on public state
/// ([SttStatus]/[SttServerState]) and Sentry-capture behaviour.
///
/// The Sentry-capture assertions are the `stt_inference_capture_test.dart`
/// equivalent for FFI errors (AC6): surfaced failures capture exactly once,
/// recovered ones capture never.
library;

// test_bundles: own run (counts events of the process-wide CrashReporter, which other files
// in the same isolate also feed and dedupe).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:whispaste/core/app_info.dart' as app;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/file_verification_service.dart';
import 'package:whispaste/services/gpu_probe_process.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';
import 'package:whispaste/services/recording_orchestrator.dart'
    show unclassifiedTranscribeErrorCode;
import 'package:whispaste/services/stt/engine_load_triage.dart';
import 'package:whispaste/services/stt/recovery_toast_notifier.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/stt/whisper/gpu_probe.dart';

// ---------------------------------------------------------------------------
// Sentry spy
// ---------------------------------------------------------------------------

final _capturedEvents = <SentryEvent>[];

SentryEvent? _spyBeforeSend(SentryEvent event, Hint hint) {
  _capturedEvents.add(event);
  return null;
}

// ---------------------------------------------------------------------------
// Failure-simulating fake engine
// ---------------------------------------------------------------------------

/// A [WhisperEngine] fake that starts benign (so the notifier's startup warmup
/// + benchmark succeed) and can be *armed* after the notifier is ready to
/// simulate one failure class. [armedCallCount] counts only transcribe calls
/// made after the most recent `arm*` call — i.e. the real inference calls under
/// test, not warmup/benchmark.
class _FakeWhisperEngine implements WhisperEngine {
  _FakeWhisperEngine({this.backend = WhisperBackend.cpu});

  /// Backend reported by [status]; a GPU-backed fake exercises the
  /// GPU-only recovery paths.
  final WhisperBackend backend;

  String transcript = 'hallo welt';
  bool _loaded = false;

  WhisperFailureKind? _armedKind;
  int _remainingFailures = 0;
  bool _hang = false;
  int armedCallCount = 0;

  /// The `prompt` passed to the most recent [transcribe] call (Issue 22
  /// regression: custom-vocabulary/prompt biasing must reach the engine).
  String? lastPrompt;

  void _resetArm() {
    armedCallCount = 0;
    _armedKind = null;
    _remainingFailures = 0;
    _hang = false;
  }

  /// Fail the first [count] inference calls with [kind], then succeed.
  void armFailures(WhisperFailureKind kind, int count) {
    _resetArm();
    _armedKind = kind;
    _remainingFailures = count;
  }

  /// Fail every inference call with [kind] (used for OOM / exhausted-transient).
  void armAlways(WhisperFailureKind kind) {
    _resetArm();
    _armedKind = kind;
    _remainingFailures = 1 << 30;
  }

  /// Hang forever on the next inference call (stuck-guard).
  void armHang() {
    _resetArm();
    _hang = true;
  }

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: backend);

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
    bool reducedThreads = false,
  }) async {
    lastPrompt = prompt;
    if (_hang) {
      armedCallCount++;
      return Completer<String>().future; // never completes
    }
    if (_armedKind != null && _remainingFailures > 0) {
      armedCallCount++;
      _remainingFailures--;
      throw WhisperEngineException(_armedKind!, _messageFor(_armedKind!));
    }
    if (_armedKind != null) armedCallCount++;
    return transcript;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }

  static String _messageFor(WhisperFailureKind kind) => switch (kind) {
    // The OOM message carries the token the orchestrator's OOM-recovery path
    // keys on — the whole point of "recovery greift, kein harter Abbruch".
    WhisperFailureKind.oom => 'stt_cuda_oom: simulated GPU out-of-memory',
    WhisperFailureKind.gpuCrash => 'simulated GPU backend crash',
    WhisperFailureKind.gpuBackendLost => 'simulated lost GPU backend',
    WhisperFailureKind.transient => 'simulated transient inference failure',
    WhisperFailureKind.timeout => 'simulated timeout',
    WhisperFailureKind.other => 'simulated other failure',
  };
}

/// A GPU-backed [WhisperEngine] fake whose next [transcribe] can be armed to
/// throw a [WhisperFailureKind.gpuCrash], mirroring a native GPU fault during
/// inference. Tracks whether it was unloaded so tests can assert the crashed
/// engine is released after the swap.
class _CrashingGpuEngine implements WhisperEngine {
  bool _loaded = false;
  bool crashNextTranscribe = false;
  int crashes = 0;
  bool unloaded = false;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.vulkan);

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
    bool reducedThreads = false,
  }) async {
    if (crashNextTranscribe) {
      crashNextTranscribe = false;
      crashes++;
      throw const WhisperEngineException(
        WhisperFailureKind.gpuCrash,
        'simulated GPU backend crash',
      );
    }
    return 'gpu';
  }

  @override
  Future<void> unload() async {
    _loaded = false;
    unloaded = true;
  }
}

/// A Metal [WhisperEngine] fake whose context can be put into ggml-metal's
/// sticky error state: once [loseBackend] is called, every [transcribe] fails
/// with [WhisperFailureKind.gpuBackendLost] until the context is recreated
/// (unload + load) — or forever when [recoversOnReload] is `false`. With
/// [failReload] every load after the first throws.
class _LostBackendGpuEngine implements WhisperEngine {
  _LostBackendGpuEngine({
    this.recoversOnReload = true,
    this.failReload = false,
  });

  final bool recoversOnReload;
  final bool failReload;
  bool _loaded = false;
  bool _lost = false;
  int loads = 0;
  int unloads = 0;
  int lostFailures = 0;

  void loseBackend() => _lost = true;

  /// The GPU recovered on its own (e.g. driver restarted).
  void heal() => _lost = false;

  /// Runs inside every [load] — lets a test look at the world mid-reload.
  void Function()? onLoad;

  /// When set, the next [transcribe] waits for it before it answers.
  Completer<void>? holdNextTranscribe;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.metal);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    loads++;
    onLoad?.call();
    if (failReload && loads > 1) {
      throw StateError('simulated reload failure');
    }
    _loaded = true;
    if (recoversOnReload) _lost = false;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async {
    final hold = holdNextTranscribe;
    if (hold != null) {
      holdNextTranscribe = null;
      await hold.future;
    }
    if (_lost) {
      lostFailures++;
      throw const WhisperEngineException(
        WhisperFailureKind.gpuBackendLost,
        'whisper_full failed with code -6 on metal',
      );
    }
    return 'gpu';
  }

  @override
  Future<void> unload() async {
    unloads++;
    _loaded = false;
  }
}

/// A [WhisperEngine] fake with a fixed, non-swappable [backend] whose [load]
/// can be armed to fail — used to exercise the FLUTTER_WHISPASTE-80 load-time
/// CPU-fallback path (a GPU/driver cold-start that hangs past the engine's
/// internal load timeout), distinct from [_FakeWhisperEngine]'s
/// transcribe-time failure simulation.
class _LoadFailingEngine implements WhisperEngine {
  _LoadFailingEngine({
    required this.backend,
    this.failLoad = false,
    this.loadError,
  });

  final WhisperBackend backend;
  bool failLoad;

  /// The message [load] throws with when [failLoad] is set; defaults to the
  /// isolate timeout of FLUTTER_WHISPASTE-80.
  final String? loadError;
  int loads = 0;

  /// When set, [load] never returns — models a native hang or a process that
  /// dies inside the load, so the crash marker is left behind.
  bool hangLoad = false;

  /// Completes once a [hangLoad] load has started and hangs.
  final Completer<void> loadHung = Completer<void>();

  /// When set, [transcribe] throws — the warmup inference fails after a
  /// successful load (must not count as a surviving GPU path).
  bool failTranscribe = false;
  bool _loaded = false;
  String? lastLoadedModelPath;

  /// Optional call-order trace, appended to by [load]/[transcribe] when set
  /// — used to prove the crash-loop guard clears strictly *after* the
  /// warmup inference, not right after `load()` returns (gpu_load_crash_guard
  /// coverage test).
  List<String>? trace;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: backend);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    loads++;
    if (failLoad) {
      throw StateError(
        loadError ??
            'whisper_isolate_load_failed: TimeoutException after '
                '0:01:00.000000: Future not completed',
      );
    }
    if (hangLoad) {
      if (!loadHung.isCompleted) loadHung.complete();
      return Completer<void>().future;
    }
    trace?.add('load');
    lastLoadedModelPath = modelPath;
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
    trace?.add('transcribe');
    if (failTranscribe) throw StateError('warmup inference failed');
    // Not a bare "ok": on the silent test WAV a lone "ok" counts as invented
    // on silence and is dropped (#2013).
    return 'ok cpu';
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

// ---------------------------------------------------------------------------
// Provider fakes
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

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

  @override
  Future<void> downloadModel(String modelId) async {
    state = ModelDownloadState(downloadedModels: {modelId});
  }
}

ProviderContainer _makeContainer(
  WhisperEngine engine, {
  AppSettings? settings,
  WhisperEngine? cpuFallbackEngine,
  GpuLoadCrashGuard? crashGuard,
}) {
  return ProviderContainer(
    overrides: [
      if (crashGuard != null)
        gpuLoadCrashGuardProvider.overrideWithValue(crashGuard),
      whisperEngineProvider.overrideWithValue(engine),
      whisperCpuFallbackEngineProvider.overrideWithValue(
        cpuFallbackEngine ?? _FakeWhisperEngine(),
      ),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ?? AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async => const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
      ),
    ],
  );
}

/// Counts silent re-downloads (#561).
class _CountingModelDownloadNotifier extends _FakeModelDownloadNotifier {
  final List<String> downloads = [];

  @override
  Future<void> downloadModel(String modelId) async {
    downloads.add(modelId);
    await super.downloadModel(modelId);
  }
}

/// Answers the hash check after a load failure without reading the file.
class _FixedVerifier extends FileVerificationService {
  const _FixedVerifier({required this.intact});

  final bool intact;

  @override
  Future<VerificationResult> verify(File file, String expectedHash) async =>
      intact
      ? const VerificationOk()
      : VerificationMismatch(expectedHash: expectedHash, actualHash: '00');
}

Future<Directory> _createFakeSttDir() async {
  final dir = await Directory.systemTemp.createTemp('stt_resilience_');
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

Future<SttServerStateNotifier> _bringReady(ProviderContainer container) async {
  await container.read(settingsProvider.future);
  final notifier = container.read(localSttBundleProvider.notifier);
  await notifier.ensureRunning();
  expect(
    container.read(localSttBundleProvider).serverState,
    SttServerState.ready,
  );
  return notifier;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Duration? savedTimeout;

  setUpAll(() async {
    await SentryFlutter.init((options) {
      options.dsn = 'https://abc123@sentry.example.invalid/0';
      options.environment = 'test';
      options.beforeSend = _spyBeforeSend;
      // Tests reuse error objects; Sentry would drop the second capture of
      // the same object, so the count depended on the test order (#1492).
      options.enableDeduplication = false;
    });
    CrashReporter.init();
    CrashReporter.instance!.consentGranted = true;
  });

  tearDownAll(() async {
    await CrashReporter.instance?.dispose();
  });

  setUp(() async {
    tempDir = await _createFakeSttDir();
    savedTimeout = SttServerStateNotifier.stuckGuardTimeout;
    // Shrink the stuck-guard so the hang test finishes in milliseconds.
    SttServerStateNotifier.stuckGuardTimeout = const Duration(
      milliseconds: 200,
    );
    // A capture the previous test started can land after it ended (lab run
    // 2849: two events where one was expected); wait for it before clearing.
    await CrashReporter.instance?.flush();
    _capturedEvents.clear();
    // The reporter sends one error at most three times per session; in a
    // shuffled order earlier tests used that up (#1492, seed 1613591121).
    CrashReporter.resetThrottlesForTesting();
  });

  tearDown(() async {
    SttServerStateNotifier.stuckGuardTimeout = savedTimeout;
    paths.sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  // ── AC2: GPU crash → CPU fallback ────────────────────────────────────────
  group('CPU-fallback on GPU crash', () {
    test('a GPU crash degrades to CPU, sets cpuFallbackActive, and the '
        'retry succeeds', () async {
      final engine = _FakeWhisperEngine();
      final cpuEngine = _FakeWhisperEngine();
      final container = _makeContainer(engine, cpuFallbackEngine: cpuEngine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armFailures(WhisperFailureKind.gpuCrash, 1);
      _capturedEvents.clear();

      final text = await notifier.transcribeBytes(
        _validWav(),
        language: 'auto',
      );

      expect(text, 'hallo welt', reason: 'the CPU retry must succeed');
      expect(
        container.read(localSttBundleProvider).cpuFallbackActive,
        isTrue,
        reason: 'cpuFallbackActive must be set after a GPU crash',
      );
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      expect(
        engine.armedCallCount,
        1,
        reason:
            'the single crashing GPU attempt; the retry runs on the CPU '
            'engine, not the crashed one',
      );

      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        isEmpty,
        reason: 'a successfully recovered GPU crash is not a surfaced error',
      );
    });
  });

  // ── F3: transcribe-time GPU crash must swap the engine, not just the flag ─
  group('GPU crash during inference swaps to the CPU engine', () {
    ProviderContainer makeGpuContainer({
      required WhisperEngine gpuEngine,
      required _LoadFailingEngine cpuEngine,
    }) {
      return ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(gpuEngine),
          whisperCpuFallbackEngineProvider.overrideWithValue(cpuEngine),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
    }

    test('the retry runs on the CPU engine (loaded with the model), and the '
        'crashed GPU engine is unloaded', () async {
      final gpuEngine = _CrashingGpuEngine();
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu)
        ..trace = <String>[];
      final container = makeGpuContainer(
        gpuEngine: gpuEngine,
        cpuEngine: cpuEngine,
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      gpuEngine.crashNextTranscribe = true;
      _capturedEvents.clear();

      final text = await notifier.transcribeBytes(
        _validWav(),
        language: 'auto',
      );

      expect(
        text,
        'ok cpu',
        reason: 'the retry must be served by the CPU engine',
      );
      expect(gpuEngine.crashes, 1);
      expect(
        cpuEngine.lastLoadedModelPath,
        isNotNull,
        reason: 'the CPU engine must load the active model before the retry',
      );
      expect(
        cpuEngine.trace,
        containsAllInOrder(['load', 'transcribe']),
        reason: 'load on CPU must precede the CPU retry',
      );
      expect(
        gpuEngine.unloaded,
        isTrue,
        reason: 'the crashed GPU engine must be released after the swap',
      );
      expect(container.read(localSttBundleProvider).cpuFallbackActive, isTrue);
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      await CrashReporter.instance!.flush();
      expect(_capturedEvents, isEmpty, reason: 'a recovered crash is no error');
    });

    test('if the CPU load fails, the original GPU crash surfaces and the '
        'GPU engine stays in place', () async {
      final gpuEngine = _CrashingGpuEngine();
      final cpuEngine = _LoadFailingEngine(
        backend: WhisperBackend.cpu,
        failLoad: true,
      );
      final container = makeGpuContainer(
        gpuEngine: gpuEngine,
        cpuEngine: cpuEngine,
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      gpuEngine.crashNextTranscribe = true;
      _capturedEvents.clear();

      Object? caught;
      try {
        await notifier.transcribeBytes(_validWav(), language: 'auto');
      } catch (e) {
        caught = e;
      }

      expect(
        '$caught',
        contains('simulated GPU backend crash'),
        reason: 'the original crash must surface, not a CPU-load error',
      );
      expect(gpuEngine.unloaded, isFalse);
      expect(container.read(localSttBundleProvider).cpuFallbackActive, isFalse);

      // Drain the GPU-fatal capture here so it cannot land in the next
      // test's freshly cleared event list (seen on Windows CI).
      await CrashReporter.instance!.flush();
      expect(_capturedEvents, hasLength(1));
    });
  });

  // ── Lost GPU backend (sticky ggml-metal error) → rebuild, then CPU ───────
  group('a lost GPU backend is rebuilt, then degraded to CPU', () {
    test('a rebuilt context serves the retry on the GPU, without a CPU '
        'swap and without a Sentry event', () async {
      final gpuEngine = _LostBackendGpuEngine();
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = _makeContainer(gpuEngine, cpuFallbackEngine: cpuEngine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      final loadsBefore = gpuEngine.loads;
      gpuEngine.loseBackend();
      _capturedEvents.clear();

      final text = await notifier.transcribeBytes(
        _validWav(),
        language: 'auto',
      );

      expect(text, 'gpu');
      expect(
        gpuEngine.lostFailures,
        1,
        reason: 'the dead context must not be retried as a transient failure',
      );
      expect(gpuEngine.unloads, 1);
      expect(gpuEngine.loads, loadsBefore + 1);
      expect(cpuEngine.lastLoadedModelPath, isNull);
      expect(container.read(localSttBundleProvider).cpuFallbackActive, isFalse);
      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        isEmpty,
        reason: 'a recovered backend is no error',
      );
    });

    test('when the rebuilt context fails again, the run degrades to the CPU '
        'engine', () async {
      final gpuEngine = _LostBackendGpuEngine(recoversOnReload: false);
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = _makeContainer(gpuEngine, cpuFallbackEngine: cpuEngine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      gpuEngine.loseBackend();
      _capturedEvents.clear();

      final text = await notifier.transcribeBytes(
        _validWav(),
        language: 'auto',
      );

      expect(text, 'ok cpu', reason: 'the CPU engine serves the run');
      expect(gpuEngine.lostFailures, 2, reason: 'one try, one after rebuild');
      expect(cpuEngine.lastLoadedModelPath, isNotNull);
      expect(container.read(localSttBundleProvider).cpuFallbackActive, isTrue);
      await CrashReporter.instance!.flush();
      expect(_capturedEvents, isEmpty);
    });

    test('when the CPU fallback fails too, the typed failure reaches the '
        'caller, so the recording is parked for a retry', () async {
      final gpuEngine = _LostBackendGpuEngine(recoversOnReload: false);
      final cpuEngine = _LoadFailingEngine(
        backend: WhisperBackend.cpu,
        failLoad: true,
      );
      final container = _makeContainer(gpuEngine, cpuFallbackEngine: cpuEngine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      gpuEngine.loseBackend();
      _capturedEvents.clear();

      Object? caught;
      try {
        await notifier.transcribeBytes(_validWav(), language: 'auto');
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<WhisperEngineException>());
      expect(
        (caught! as WhisperEngineException).kind,
        WhisperFailureKind.gpuBackendLost,
      );
      final code = unclassifiedTranscribeErrorCode(caught);
      expect(code, 'stt_server_failed');
      expect(isRepeatableTranscriptionError(code), isTrue);
      await CrashReporter.instance!.flush();
      expect(_capturedEvents, hasLength(1));
    });

    test('when the rebuild and the CPU fallback both fail, the server drops '
        'to stopped, so the next dictation loads the model afresh', () async {
      final gpuEngine = _LostBackendGpuEngine(failReload: true);
      final cpuEngine = _LoadFailingEngine(
        backend: WhisperBackend.cpu,
        failLoad: true,
      );
      final container = _makeContainer(gpuEngine, cpuFallbackEngine: cpuEngine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      gpuEngine.loseBackend();

      await expectLater(
        notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(isA<WhisperEngineException>()),
      );

      expect(gpuEngine.unloads, 1);
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
        reason:
            'a ready state over an unloaded engine would fail the next '
            'dictation on the warm fast path',
      );
    });
  });

  // ── AC3: GPU OOM → recovery trigger, no hard abort ───────────────────────
  group('OOM-recovery trigger', () {
    test('a GPU OOM surfaces the stt_cuda_oom recovery token without a CPU '
        'fallback or wasteful retry', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armAlways(WhisperFailureKind.oom);
      _capturedEvents.clear();

      Object? caught;
      try {
        await notifier.transcribeBytes(_validWav(), language: 'auto');
      } catch (e) {
        caught = e;
      }

      expect(caught, isNotNull, reason: 'OOM must surface, not be swallowed');
      expect(
        '$caught',
        contains('stt_cuda_oom'),
        reason: "the orchestrator's OomRecoveryHandler keys on this token",
      );
      expect(
        container.read(localSttBundleProvider).cpuFallbackActive,
        isFalse,
        reason: 'OOM recovers via smaller-model/cloud, not a CPU retry',
      );
      expect(
        engine.armedCallCount,
        1,
        reason: 'OOM is not retried in the notifier — it hands off immediately',
      );

      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        hasLength(1),
        reason: 'the OOM is captured once under its own fingerprint',
      );
    });
  });

  // ── AC4: hanging transcription → stuck-guard, no deadlock ────────────────
  group('Stuck-guard timeout', () {
    test('a transcription that never returns ends in a clean bounded error, '
        'not a deadlock', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armHang();
      _capturedEvents.clear();

      await expectLater(
        notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(anything),
      );

      await CrashReporter.instance!.flush();
      // Only this test's report counts: under load on the win guest a late
      // event of another test landed in the spy as well (lab run 2849).
      expect(
        _capturedEvents.where(
          (e) => '${e.message?.formatted} ${e.throwable}'.contains(
            'pipeline_timeout',
          ),
        ),
        hasLength(1),
        reason: 'the stuck transcription is captured once',
      );
    });

    test(
      'a hung GPU transcription moves to the CPU engine once and the retry '
      'succeeds there, so later dictation does not queue behind the hang',
      () async {
        final gpuEngine = _FakeWhisperEngine(backend: WhisperBackend.cuda);
        final cpuEngine = _FakeWhisperEngine();
        final container = _makeContainer(
          gpuEngine,
          cpuFallbackEngine: cpuEngine,
        );
        addTearDown(container.dispose);

        final notifier = await _bringReady(container);
        gpuEngine.armHang();
        _capturedEvents.clear();

        final text = await notifier.transcribeBytes(
          _validWav(),
          language: 'auto',
        );

        expect(text, 'hallo welt', reason: 'the CPU retry must succeed');
        expect(
          gpuEngine.armedCallCount,
          1,
          reason: 'one hung GPU attempt only',
        );
        expect(
          container.read(localSttBundleProvider).cpuFallbackActive,
          isTrue,
          reason: 'the hang must leave the engine on CPU for later requests',
        );
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
        );
      },
    );

    test('a hang on a CPU engine is not retried — it ends in the bounded '
        'timeout error', () async {
      final cpuEngine = _FakeWhisperEngine();
      final fallback = _FakeWhisperEngine();
      final container = _makeContainer(cpuEngine, cpuFallbackEngine: fallback);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      cpuEngine.armHang();

      await expectLater(
        notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(anything),
      );
      expect(container.read(localSttBundleProvider).cpuFallbackActive, isFalse);
    });
  });

  // ── AC5: transient failure → retry ───────────────────────────────────────
  group('Transient retry', () {
    test('a transient failure that clears within the retry budget maps to '
        'a successful transcription (state stays ready)', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armFailures(WhisperFailureKind.transient, 2);
      _capturedEvents.clear();

      final text = await notifier.transcribeBytes(
        _validWav(),
        language: 'auto',
      );

      expect(text, 'hallo welt');
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
        reason: 'success after retry maps to ready',
      );
      expect(
        engine.armedCallCount,
        3,
        reason: 'two transient failures + one success',
      );

      await CrashReporter.instance!.flush();
      expect(_capturedEvents, isEmpty);
    });

    test('a transient failure that never clears aborts after 3 retries and '
        'is captured once', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armAlways(WhisperFailureKind.transient);
      _capturedEvents.clear();

      await expectLater(
        notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(anything),
      );

      expect(
        engine.armedCallCount,
        4,
        reason: 'one initial attempt + three retries, then abort',
      );

      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        hasLength(1),
        reason: 'the exhausted-retry failure is captured once',
      );
    });
  });

  // ── Issue 22: custom-vocabulary/prompt biasing must reach the engine ────
  group('Custom-vocabulary prompt forwarding', () {
    test('the resolved custom-vocabulary prompt is forwarded to '
        'WhisperEngine.transcribe, not just validated', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(
        engine,
        settings: AppSettings.defaults.copyWith(
          sttModel: 'whisper-small',
          customVocabulary: 'Fachbegriff, Eigenname',
        ),
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'auto');

      expect(
        engine.lastPrompt,
        contains('Fachbegriff, Eigenname'),
        reason:
            'the notifier resolves the custom-vocabulary prompt but must '
            'also hand it to the engine, not just the pre-flight validator',
      );
    });

    test('no custom vocabulary configured and language is auto-detect → the '
        'engine receives no prompt (no language to prime with yet)', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'auto');

      expect(engine.lastPrompt, isNull);
    });

    test('a decoder loop on one letter does not prime the next recording, '
        'normal text does', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      engine.transcript = 'i' * 32;
      await notifier.transcribeBytes(_validWav(), language: 'auto');
      await notifier.transcribeBytes(_validWav(), language: 'auto');
      expect(engine.lastPrompt, isNull);

      engine.transcript = 'hallo welt';
      await notifier.transcribeBytes(_validWav(), language: 'auto');
      await notifier.transcribeBytes(_validWav(), language: 'auto');
      expect(engine.lastPrompt, contains('hallo welt'));
    });

    test(
      'no custom vocabulary, known language, punctuation priming on '
      '(default) → the engine receives the default punctuation prompt',
      () async {
        final engine = _FakeWhisperEngine();
        final container = _makeContainer(engine);
        addTearDown(container.dispose);

        final notifier = await _bringReady(container);
        _capturedEvents.clear();

        await notifier.transcribeBytes(_validWav(), language: 'en');

        expect(engine.lastPrompt, isNotNull);
        expect(engine.lastPrompt, isNot(isEmpty));
      },
    );

    test('no custom vocabulary, known language, punctuation priming disabled '
        'via settings → the engine receives no prompt', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(
        engine,
        settings: AppSettings.defaults.copyWithSections(
          stt: AppSettings.defaults.stt.copyWith(
            model: 'whisper-small',
            punctuationPriming: false,
          ),
        ),
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'en');

      expect(engine.lastPrompt, isNull);
    });

    test('custom vocabulary set → punctuation priming never overrides it, even '
        'for a known language', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(
        engine,
        settings: AppSettings.defaults.copyWith(
          sttModel: 'whisper-small',
          customVocabulary: 'Fachbegriff, Eigenname',
        ),
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'en');

      expect(engine.lastPrompt, equals('Fachbegriff, Eigenname'));
    });
  });

  // ── FLUTTER_WHISPASTE-80: CPU-fallback on model-load failure/hang ────────
  group('CPU-fallback on model-load failure (FLUTTER_WHISPASTE-80)', () {
    test(
      'a hung/failed GPU-backend load degrades once to CPU and reaches ready',
      () async {
        final gpuEngine = _LoadFailingEngine(
          backend: WhisperBackend.vulkan,
          failLoad: true,
        );
        final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
        final container = ProviderContainer(
          overrides: [
            whisperEngineProvider.overrideWithValue(gpuEngine),
            whisperCpuFallbackEngineProvider.overrideWithValue(cpuEngine),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
              ),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(),
            ),
            hw.gpuInfoProvider.overrideWith(
              (_) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
        );
        expect(
          container.read(localSttBundleProvider).cpuFallbackActive,
          isTrue,
          reason: 'cpuFallbackActive must be set after the load-time fallback',
        );
        expect(cpuEngine.lastLoadedModelPath, isNotNull);
      },
    );

    test('a load failure on an already-CPU engine fails immediately — no '
        'fallback loop, no fallback engine touched', () async {
      final cpuEngine = _LoadFailingEngine(
        backend: WhisperBackend.cpu,
        failLoad: true,
      );
      final unusedFallback = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = ProviderContainer(
        overrides: [
          modelFileVerifierProvider.overrideWithValue(
            const _FixedVerifier(intact: true),
          ),
          whisperEngineProvider.overrideWithValue(cpuEngine),
          whisperCpuFallbackEngineProvider.overrideWithValue(unusedFallback),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.error,
      );
      expect(container.read(localSttBundleProvider).cpuFallbackActive, isFalse);
      expect(unusedFallback.lastLoadedModelPath, isNull);
    });
  });

  // ── #561: a failed load names its cause and heals itself ───────────────
  group('load failure triage (#561)', () {
    const gpu = hw.GpuInfo(
      vendor: hw.GpuVendor.amd,
      name: 'Radeon RX 6600',
      vramMB: 8192,
      driverVersion: '24.12.1',
    );
    late Directory probeDir;

    setUp(() async {
      probeDir = await Directory.systemTemp.createTemp('gpu_probe_561_');
    });
    tearDown(() => probeDir.delete(recursive: true));

    // The probe child passes on the first launch: only the real load fails.
    GpuProbeService probe({bool firstLaunch = false}) => GpuProbeService(
      store: GpuProbeStore(File('${probeDir.path}/gpu_probe.json')),
      run: ({required modelId, required timeout}) async => firstLaunch
          ? const GpuProbeOutcome.ok('vulkan')
          : fail('a stored verdict needs no probe'),
      appVersion: '1.4.3',
      osVersion: 'Linux 7.0',
      operatingSystem: 'linux',
    );

    ProviderContainer make({
      required WhisperEngine engine,
      WhisperEngine? cpu,
      bool? intact,
      _CountingModelDownloadNotifier? downloads,
      GpuProbeService? probeService,
    }) => ProviderContainer(
      overrides: [
        whisperEngineProvider.overrideWithValue(engine),
        whisperCpuFallbackEngineProvider.overrideWithValue(
          cpu ?? _LoadFailingEngine(backend: WhisperBackend.cpu),
        ),
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
          ),
        ),
        modelDownloadProvider.overrideWith(
          () => downloads ?? _CountingModelDownloadNotifier(),
        ),
        hw.gpuInfoProvider.overrideWith((_) async => gpu),
        if (intact != null)
          modelFileVerifierProvider.overrideWithValue(
            _FixedVerifier(intact: intact),
          ),
        if (probeService != null)
          gpuProbeServiceProvider.overrideWithValue(probeService),
      ],
    );

    Future<SttStatus> start(ProviderContainer c) async {
      await c.read(settingsProvider.future);
      await c.read(hw.gpuInfoProvider.future);
      await c.read(localSttBundleProvider.notifier).ensureRunning();
      return c.read(localSttBundleProvider);
    }

    File modelFile() =>
        File('${tempDir.path}/${findSttModel('whisper-small')!.filename}');

    // Big enough to pass the size check, so the hash check is what decides.
    void restoreModelFile() {
      final raf = modelFile().openSync(mode: FileMode.write);
      raf.truncateSync(11 * 1024 * 1024);
      raf.closeSync();
    }

    test('a damaged file fails its hash check: deleted, loaded again in the '
        'background, and the user is told', () async {
      final downloads = _CountingModelDownloadNotifier();
      final cpu = _LoadFailingEngine(
        backend: WhisperBackend.cpu,
        failLoad: true,
        loadError: 'whisper_init_failed: invalid model data (bad magic)',
      );
      final c = make(engine: cpu, intact: false, downloads: downloads);
      addTearDown(c.dispose);
      final toasts = <RecoveryToastKind>[];
      c.listen(recoveryToastNotifierProvider, (_, e) => toasts.add(e!.kind));

      final status = await start(c);

      expect(status.serverState, SttServerState.stopped);
      expect(downloads.downloads, ['whisper-small']);
      expect(modelFile().existsSync(), isFalse);
      expect(toasts, [RecoveryToastKind.modelFileRepair]);
    });

    test(
      'an intact file is not downloaded again; the load error stays',
      () async {
        final downloads = _CountingModelDownloadNotifier();
        final cpu = _LoadFailingEngine(
          backend: WhisperBackend.cpu,
          failLoad: true,
          loadError: 'whisper_init_failed: invalid model data (bad magic)',
        );
        final c = make(engine: cpu, intact: true, downloads: downloads);
        addTearDown(c.dispose);

        final status = await start(c);

        expect(status.serverState, SttServerState.error);
        expect(status.errorMessage, 'stt_model_load_failed');
        expect(downloads.downloads, isEmpty);
        expect(modelFile().existsSync(), isTrue);
      },
    );

    test(
      'a damaged file on the GPU is repaired without a CPU attempt',
      () async {
        final downloads = _CountingModelDownloadNotifier();
        final gpuEngine = _LoadFailingEngine(
          backend: WhisperBackend.vulkan,
          failLoad: true,
          loadError: 'failed to read model tensor: unexpected end of file',
        );
        final cpu = _LoadFailingEngine(backend: WhisperBackend.cpu);
        final c = make(
          engine: gpuEngine,
          cpu: cpu,
          intact: false,
          downloads: downloads,
        );
        addTearDown(c.dispose);

        final status = await start(c);

        expect(status.serverState, SttServerState.stopped);
        expect(downloads.downloads, ['whisper-small']);
        expect(cpu.loads, 0);
      },
    );

    test('same repair on macos, windows and linux: the probe platform '
        'changes nothing about the file repair', () async {
      for (final os in ['macos', 'windows', 'linux']) {
        final downloads = _CountingModelDownloadNotifier();
        final c = make(
          engine: _LoadFailingEngine(
            backend: WhisperBackend.cpu,
            failLoad: true,
            loadError: 'whisper_init_failed: invalid model data (bad magic)',
          ),
          intact: false,
          downloads: downloads,
          probeService: GpuProbeService(
            store: GpuProbeStore(File('${probeDir.path}/$os.json')),
            run: ({required modelId, required timeout}) async =>
                const GpuProbeOutcome.ok('vulkan'),
            appVersion: '1.4.3',
            osVersion: os,
            operatingSystem: os,
          ),
        );
        addTearDown(c.dispose);
        final toasts = <RecoveryToastKind>[];
        c.listen(recoveryToastNotifierProvider, (_, e) => toasts.add(e!.kind));

        final status = await start(c);

        expect(status.serverState, SttServerState.stopped, reason: os);
        expect(downloads.downloads, ['whisper-small'], reason: os);
        expect(toasts, [RecoveryToastKind.modelFileRepair], reason: os);
        // The repair deleted the file; the next system starts from a new one.
        restoreModelFile();
      }
    });

    test(
      'stt_model_corrupted goes to Sentry at most once per session',
      () async {
        final sent = <String>[];
        final c = ProviderContainer(
          overrides: [
            whisperEngineProvider.overrideWithValue(
              _LoadFailingEngine(
                backend: WhisperBackend.cpu,
                failLoad: true,
                loadError: 'invalid model data (bad magic)',
              ),
            ),
            whisperCpuFallbackEngineProvider.overrideWithValue(
              _LoadFailingEngine(backend: WhisperBackend.cpu),
            ),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
              ),
            ),
            modelDownloadProvider.overrideWith(
              _CountingModelDownloadNotifier.new,
            ),
            hw.gpuInfoProvider.overrideWith((_) async => gpu),
            modelFileVerifierProvider.overrideWithValue(
              const _FixedVerifier(intact: false),
            ),
            modelCorruptedReporterProvider.overrideWithValue(
              ModelCorruptedReporter(send: (message, _) => sent.add(message)),
            ),
          ],
        );
        addTearDown(c.dispose);

        await start(c);
        restoreModelFile();
        await start(c);

        expect(sent, hasLength(1));
      },
    );

    test('GPU and CPU both failing checks the file after all', () async {
      final downloads = _CountingModelDownloadNotifier();
      final c = make(
        engine: _LoadFailingEngine(
          backend: WhisperBackend.vulkan,
          failLoad: true,
          loadError: 'vk::DeviceLostError',
        ),
        cpu: _LoadFailingEngine(backend: WhisperBackend.cpu, failLoad: true),
        intact: false,
        downloads: downloads,
      );
      addTearDown(c.dispose);

      final status = await start(c);

      expect(status.serverState, SttServerState.stopped);
      expect(downloads.downloads, ['whisper-small']);
    });

    test('a CPU failure that names a device still checks the file', () async {
      final downloads = _CountingModelDownloadNotifier();
      final c = make(
        engine: _LoadFailingEngine(
          backend: WhisperBackend.cpu,
          failLoad: true,
          loadError: 'I/O error on device while reading the model',
        ),
        intact: false,
        downloads: downloads,
      );
      addTearDown(c.dispose);

      expect((await start(c)).serverState, SttServerState.stopped);
      expect(downloads.downloads, ['whisper-small']);
    });

    test('a GPU load timeout moves only this session to the CPU', () async {
      final first = make(
        engine: _LoadFailingEngine(
          backend: WhisperBackend.vulkan,
          failLoad: true,
        ),
        probeService: probe(firstLaunch: true),
      );
      final status = await start(first);
      first.dispose();
      expect(status.cpuFallbackActive, isTrue);

      final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan);
      final next = make(
        engine: gpuEngine,
        probeService: probe(firstLaunch: true),
      );
      addTearDown(next.dispose);
      expect((await start(next)).cpuFallbackActive, isFalse);
      expect(gpuEngine.loads, 1);
    });

    test('video memory held by other programs (whisper_init NULL, #1669) '
        'moves only this session to the CPU, with the notice', () async {
      final first = make(
        engine: _LoadFailingEngine(
          backend: WhisperBackend.vulkan,
          failLoad: true,
          loadError: whisperInitReturnedNullError(const [
            'ggml_vulkan: Device memory allocation of size 1617000000 failed.',
            'whisper_model_load: failed to allocate Vulkan0 buffer for the '
                'model weights (out of memory)',
            'whisper_init_with_params_no_state: failed to load model',
          ]),
        ),
        intact: true,
        probeService: probe(firstLaunch: true),
      );
      final status = await start(first);
      first.dispose();
      expect(status.serverState, SttServerState.ready);
      expect(status.cpuFallbackActive, isTrue);

      // Not remembered: the next start tries the GPU again.
      final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan);
      final next = make(
        engine: gpuEngine,
        probeService: probe(firstLaunch: true),
      );
      addTearDown(next.dispose);
      expect((await start(next)).cpuFallbackActive, isFalse);
      expect(gpuEngine.loads, 1);
    });

    test('an incompatible GPU moves to the CPU, and the next start goes '
        'there at once and names the cause', () async {
      final first = make(
        engine: _LoadFailingEngine(
          backend: WhisperBackend.vulkan,
          failLoad: true,
          loadError: 'vk::DeviceLostError: vk::Queue::submit',
        ),
        intact: true,
        probeService: probe(firstLaunch: true),
      );
      final status = await start(first);
      first.dispose();
      expect(status.serverState, SttServerState.ready);
      expect(status.cpuFallbackActive, isTrue);

      // Next launch: a fresh service reads the stored verdict from disk.
      final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan);
      final cpu = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final next = make(engine: gpuEngine, cpu: cpu, probeService: probe());
      addTearDown(next.dispose);
      final toasts = <RecoveryToastKind>[];
      next.listen(recoveryToastNotifierProvider, (_, e) => toasts.add(e!.kind));

      final again = await start(next);

      expect(again.serverState, SttServerState.ready);
      expect(gpuEngine.loads, 0);
      expect(cpu.loads, 1);
      expect(toasts, [RecoveryToastKind.gpuLoadIncompatible]);
    });
  });

  group('GPU loss recovery: crash guard, return to GPU, waiting dictation '
      '(#404)', () {
    late Directory guardDir;

    setUp(() async {
      guardDir = await Directory.systemTemp.createTemp('gpu_recovery_guard_');
    });

    tearDown(() async {
      await guardDir.delete(recursive: true);
    });

    test('the GPU reload after a lost backend runs under the crash marker, '
        'which stays until the retried inference proves the context', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final gpuEngine = _LostBackendGpuEngine();
      final container = _makeContainer(
        gpuEngine,
        cpuFallbackEngine: _LoadFailingEngine(backend: WhisperBackend.cpu),
        crashGuard: guard,
      );
      addTearDown(container.dispose);
      final notifier = await _bringReady(container);
      final marksBefore = guard.markCalls;
      gpuEngine.loseBackend();
      var markedDuringReload = false;
      gpuEngine.onLoad = () => markedDuringReload = guard.crashedLastAttempt;

      await notifier.transcribeBytes(_validWav(), language: 'auto');

      expect(guard.markCalls, marksBefore + 1);
      expect(
        markedDuringReload,
        isTrue,
        reason: 'a crash while reloading must be found at the next start',
      );
      expect(guard.crashedLastAttempt, isFalse);
    });

    test(
      'a failed reload clears the marker again (caught, no crash)',
      () async {
        final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
        final gpuEngine = _LostBackendGpuEngine(failReload: true);
        final container = _makeContainer(
          gpuEngine,
          cpuFallbackEngine: _LoadFailingEngine(backend: WhisperBackend.cpu),
          crashGuard: guard,
        );
        addTearDown(container.dispose);
        final notifier = await _bringReady(container);
        gpuEngine.loseBackend();

        await notifier.transcribeBytes(_validWav(), language: 'auto');

        expect(guard.crashedLastAttempt, isFalse);
      },
    );

    test(
      'after a successful CPU run the next load tries the GPU again',
      () async {
        final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
        final gpuEngine = _LostBackendGpuEngine(recoversOnReload: false);
        final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
        final container = _makeContainer(
          gpuEngine,
          cpuFallbackEngine: cpuEngine,
          crashGuard: guard,
        );
        addTearDown(container.dispose);
        final notifier = await _bringReady(container);
        gpuEngine.loseBackend();
        expect(
          await notifier.transcribeBytes(_validWav(), language: 'auto'),
          'ok cpu',
        );
        expect(
          container.read(localSttBundleProvider).cpuFallbackActive,
          isTrue,
        );

        gpuEngine.heal();
        final loadsBefore = gpuEngine.loads;
        await notifier.stop();
        await notifier.ensureRunning();

        expect(gpuEngine.loads, greaterThan(loadsBefore));
        final state = container.read(localSttBundleProvider);
        expect(state.backend, WhisperBackend.metal);
        expect(state.cpuFallbackActive, isFalse);
        expect(
          await notifier.transcribeBytes(_validWav(), language: 'auto'),
          'gpu',
        );
      },
    );

    test('a set crash marker keeps the next load on the CPU', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final gpuEngine = _LostBackendGpuEngine(recoversOnReload: false);
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = _makeContainer(
        gpuEngine,
        cpuFallbackEngine: cpuEngine,
        crashGuard: guard,
      );
      addTearDown(container.dispose);
      final notifier = await _bringReady(container);
      gpuEngine.loseBackend();
      await notifier.transcribeBytes(_validWav(), language: 'auto');

      guard.markAttempt();
      final loadsBefore = gpuEngine.loads;
      await notifier.stop();
      await notifier.ensureRunning();

      expect(gpuEngine.loads, loadsBefore);
    });

    test('a failed CPU run does not queue a GPU retry', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final gpuEngine = _LostBackendGpuEngine(recoversOnReload: false);
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = _makeContainer(
        gpuEngine,
        cpuFallbackEngine: cpuEngine,
        crashGuard: guard,
      );
      addTearDown(container.dispose);
      final notifier = await _bringReady(container);
      gpuEngine.loseBackend();
      cpuEngine.failTranscribe = true;
      await expectLater(
        notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(anything),
      );
      gpuEngine.heal();
      final loadsBefore = gpuEngine.loads;
      await notifier.stop();
      await notifier.ensureRunning();

      expect(gpuEngine.loads, loadsBefore);
    });

    test('a second dictation waiting during the rebuild never hits the dead '
        'context', () async {
      final gpuEngine = _LostBackendGpuEngine();
      final container = _makeContainer(
        gpuEngine,
        cpuFallbackEngine: _LoadFailingEngine(backend: WhisperBackend.cpu),
      );
      addTearDown(container.dispose);
      final notifier = await _bringReady(container);
      gpuEngine.loseBackend();
      final hold = Completer<void>();
      gpuEngine.holdNextTranscribe = hold;

      final first = notifier.transcribeBytes(_validWav(), language: 'auto');
      await Future<void>.delayed(Duration.zero);
      final second = notifier.transcribeBytes(_validWav(), language: 'auto');
      await Future<void>.delayed(Duration.zero);
      hold.complete();

      expect(await first, 'gpu');
      expect(await second, 'gpu');
      expect(gpuEngine.lostFailures, 1);
    });

    test('a second dictation waiting during the CPU swap runs on the CPU '
        'engine, not on the dead GPU context', () async {
      final gpuEngine = _LostBackendGpuEngine(recoversOnReload: false);
      final container = _makeContainer(
        gpuEngine,
        cpuFallbackEngine: _LoadFailingEngine(backend: WhisperBackend.cpu),
      );
      addTearDown(container.dispose);
      final notifier = await _bringReady(container);
      gpuEngine.loseBackend();
      final hold = Completer<void>();
      gpuEngine.holdNextTranscribe = hold;

      final first = notifier.transcribeBytes(_validWav(), language: 'auto');
      await Future<void>.delayed(Duration.zero);
      final second = notifier.transcribeBytes(_validWav(), language: 'auto');
      await Future<void>.delayed(Duration.zero);
      hold.complete();

      expect(await first, 'ok cpu');
      expect(await second, 'ok cpu');
      expect(gpuEngine.lostFailures, 2, reason: 'only the first dictation');
    });
  });

  group('GPU-load crash-loop breaker (gpu_load_crash_guard.dart)', () {
    late Directory guardDir;

    setUp(() async {
      guardDir = await Directory.systemTemp.createTemp('gpu_crash_guard_');
    });

    tearDown(() async {
      await guardDir.delete(recursive: true);
    });

    test('a successful GPU-backend load marks the guard before the native '
        'call and clears it right after — proving _start() is actually '
        'wired to the guard, not just coincidentally leaving no marker '
        'behind', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan);
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(gpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      expect(guard.markCalls, 1);
      expect(guard.clearCalls, 1);
      expect(guard.crashedLastAttempt, isFalse);
    });

    test('a caught GPU load failure that recovers onto CPU still marks then '
        'clears the guard — the process survived, so this must not look '
        'like a crash on the next launch', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final gpuEngine = _LoadFailingEngine(
        backend: WhisperBackend.vulkan,
        failLoad: true,
      );
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(gpuEngine),
          whisperCpuFallbackEngineProvider.overrideWithValue(cpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      expect(guard.markCalls, 1);
      expect(guard.clearCalls, 1);
      expect(guard.crashedLastAttempt, isFalse);
    });

    test('a CPU-only engine never touches the guard at all — the marker is '
        'reserved for GPU-backed attempts', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(cpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(guard.markCalls, 0);
      expect(guard.clearCalls, 0);
    });

    test('the marker clears strictly AFTER the warmup inference, not right '
        'after load() — on old/weak GPUs the first compute dispatch, not '
        'the weight load, is the more likely native crash point, so '
        'clearing too early would let that exact crash repeat the loop '
        'undetected', () async {
      final trace = <String>[];
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path, trace: trace);
      final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan)
        ..trace = trace;
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(gpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      // Only the first 4 entries are asserted: _runBenchmark's own transcribe
      // call is unawaited (fire-and-forget) and may append a trailing
      // 'transcribe' after 'clear' depending on scheduling — that's expected
      // and irrelevant to what this test checks.
      expect(
        trace.take(4),
        ['mark', 'load', 'transcribe', 'clear'],
        reason:
            '"clear" must come after "transcribe" (the warmup inference) — '
            'if it moved back to right after "load", a crash during warmup '
            'on real hardware would go undetected by the next launch',
      );
    });

    test(
      'a failed warmup inference clears the marker but does NOT reset the '
      'crash streak — only a warmup that succeeded proves the GPU works',
      () async {
        final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
        final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan)
          ..failTranscribe = true;
        final container = ProviderContainer(
          overrides: [
            whisperEngineProvider.overrideWithValue(gpuEngine),
            gpuLoadCrashGuardProvider.overrideWithValue(guard),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
              ),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(),
            ),
            hw.gpuInfoProvider.overrideWith(
              (_) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();

        expect(guard.clearCalls, 1);
        expect(guard.resetCalls, 0);
      },
    );

    group('crash streak across warm-up and reloads (P0.1, P0.2)', () {
      const modelId = 'whisper-small';

      String keyFor(String backend) => GpuLoadCrashGuard.attemptKey(
        backend: backend,
        modelId: modelId,
        appVersion: app.appVersion,
      );

      ProviderContainer makeContainer(
        GpuLoadCrashGuard guard,
        WhisperEngine engine,
      ) {
        return ProviderContainer(
          overrides: [
            whisperEngineProvider.overrideWithValue(engine),
            whisperCpuFallbackEngineProvider.overrideWithValue(
              _LoadFailingEngine(backend: WhisperBackend.cpu),
            ),
            gpuLoadCrashGuardProvider.overrideWithValue(guard),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(sttModel: modelId),
              ),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(),
            ),
            hw.gpuInfoProvider.overrideWith(
              (_) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
            ),
          ],
        );
      }

      test('a crash on the reload after an idle unload is the second strike '
          'and persists CPU-only — the successful start warm-up in between '
          'must not reset the streak', () async {
        final key = keyFor('vulkan');
        // An earlier launch crashed while loading the GPU model.
        _SpyGpuLoadCrashGuard(dataDir: guardDir.path).recordCrash(key: key);

        final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
        final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan);
        final container = makeContainer(guard, gpuEngine);
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);

        // Start with warm-up: succeeds, so the marker is cleared again.
        await notifier.ensureRunning();
        expect(guard.clearCalls, 1);
        expect(
          guard.consecutiveCrashes,
          1,
          reason:
              'a successful warm-up is no proof the GPU is healthy; the '
              'streak may only be reset after a real transcription',
        );
        expect(guard.resetCalls, 0);

        // Idle unload, then the first hotkey reloads the model and the
        // process dies inside the native load.
        await notifier.stop();
        gpuEngine.hangLoad = true;
        unawaited(notifier.ensureRunning());
        await gpuEngine.loadHung.future.timeout(const Duration(seconds: 10));
        expect(
          guard.markCalls,
          2,
          reason: 'every GPU load, including a reload, sets the marker',
        );
        expect(guard.crashedLastAttempt, isTrue);
        expect(guard.crashedLastAttemptKey, key);

        // Next launch: the recorded streak is now two, so CPU-only persists.
        final relaunch = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
        final relaunchContainer = makeContainer(
          relaunch,
          _LoadFailingEngine(backend: WhisperBackend.vulkan),
        );
        addTearDown(relaunchContainer.dispose);
        await relaunchContainer.read(settingsProvider.future);
        expect(
          relaunchContainer
              .read(settingsProvider)
              .value!
              .behavior
              .gpuAcceleration,
          isNot('disabled'),
        );
        await recoverFromGpuLoadCrash(relaunchContainer);

        expect(
          relaunchContainer
              .read(settingsProvider)
              .value!
              .behavior
              .gpuAcceleration,
          'disabled',
          reason:
              'two consecutive GPU load crashes must persist CPU-only — '
              'before this fix the launch warm-up reset the streak every time',
        );
      });

      test('a GPU never loads a model that does not fit its VRAM — the load '
          'runs on the CPU engine and no GPU crash marker is set', () async {
        final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
        final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan);
        final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
        final container = ProviderContainer(
          overrides: [
            whisperEngineProvider.overrideWithValue(gpuEngine),
            whisperCpuFallbackEngineProvider.overrideWithValue(cpuEngine),
            gpuLoadCrashGuardProvider.overrideWithValue(guard),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
              ),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(),
            ),
            hw.gpuInfoProvider.overrideWith(
              (_) async => const hw.GpuInfo(
                vendor: hw.GpuVendor.nvidia,
                name: 'NVIDIA GeForce GTX 1050',
                vramMB: 512,
                vulkanAvailable: true,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
        // The VRAM gate reads the GPU info synchronously, as main.dart
        // pre-warms it at start-up; resolve it here the same way.
        await container.read(hw.gpuInfoProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();

        expect(gpuEngine.lastLoadedModelPath, isNull);
        expect(cpuEngine.lastLoadedModelPath, isNotNull);
        expect(guard.markCalls, 0);
        final status = container.read(localSttBundleProvider);
        expect(status.serverState, SttServerState.ready);
        expect(status.backend, WhisperBackend.cpu);
      });

      test('a healthy GPU is not demoted: the streak is reset only by a real '
          'transcription that succeeds on the same key', () async {
        final key = keyFor('vulkan');
        final seeded = _SpyGpuLoadCrashGuard(dataDir: guardDir.path)
          ..recordCrash(key: key);
        expect(seeded.consecutiveCrashes, 1);

        final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
        final container = makeContainer(
          guard,
          _LoadFailingEngine(backend: WhisperBackend.vulkan),
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();
        expect(guard.consecutiveCrashes, 1);

        await notifier.transcribeBytes(_validWav(), language: 'auto');

        expect(guard.resetCalls, 1);
        expect(guard.consecutiveCrashes, 0);
        expect(guard.crashedLastAttempt, isFalse);
      });
    });
  });
}

/// Counts real [GpuLoadCrashGuard] calls so tests can assert `_start()` is
/// actually wired to the guard (mark-before-load, clear-after-return),
/// rather than only asserting on the marker file's final state — which
/// would pass even if the wiring were deleted entirely.
class _SpyGpuLoadCrashGuard extends GpuLoadCrashGuard {
  _SpyGpuLoadCrashGuard({required super.dataDir, this.trace});

  int markCalls = 0;
  int clearCalls = 0;
  int resetCalls = 0;

  /// Optional shared call-order trace — see [_LoadFailingEngine.trace].
  final List<String>? trace;

  @override
  void markAttempt({bool cuda = false, String key = ''}) {
    markCalls++;
    trace?.add('mark');
    super.markAttempt(cuda: cuda, key: key);
  }

  @override
  void clearAttempt() {
    clearCalls++;
    trace?.add('clear');
    super.clearAttempt();
  }

  @override
  void resetCrashStreak({String key = ''}) {
    resetCalls++;
    super.resetCrashStreak(key: key);
  }
}
